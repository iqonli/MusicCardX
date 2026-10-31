// Copyright (c) 2026 IQ Online Studio. MIT.
package com.iqonli.ezcd.fonts

import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.ActionMode
import android.view.Menu
import android.view.MotionEvent
import android.view.MenuItem
import android.view.View
import android.view.ViewGroup
import android.widget.*
import com.iqonli.ezcd.R
import com.iqonli.ezcd.ui.BaseActivity
import com.iqonli.ezcd.ui.DirectoryAccess
import com.iqonli.ezcd.ui.NativeUi

/** Standalone destination: future font pickers can reuse this catalog and preview routes. */
open class FontManagerActivity : BaseActivity() {
    private val selecting: Boolean get() = this is FontSelectorActivity
    private sealed interface Outcome {
        data class Imported(val report: FontImportReport) : Outcome
        data class Changed(val result: FontChangeResult, val deleted: Boolean = false) : Outcome
    }
    private class Session {
        val task = FontTask<Outcome>()
        var pendingMode: FontStorageMode? = null
        var parent: String? = null
        var choosingDirectory = false
        var choosingAppFont=false
    }
    private lateinit var session: Session
    private lateinit var list: ExpandableListView
    private lateinit var adapter: FontAdapter
    private lateinit var status: TextView
    private lateinit var progressRow: LinearLayout
    private lateinit var progressBar: ProgressBar
    private lateinit var percent: TextView
    private lateinit var empty: TextView
    private var groups = emptyList<FontFamilyGroup>()
    private var storage = FontStorage()
    private var loaded = false
    private var actionMode: ActionMode? = null
    private val selected = linkedSetOf<String>()
    private val expanded = mutableSetOf<String>()
    private var generation = 0
    private var resumed = false
    private var waitingLocal = false
    private var reportDialog: AlertDialog? = null
    private var pickerDialog: AlertDialog? = null
    private var loadedRevision=-1L
    private var loadingRevision: Long?=null
    private var lastBusy: Boolean?=null
    private var restoringGroups=false
    private data class Anchor(val key: String,val font: String?,val group: Int,val child: Int,val top: Int)
    private var restoredAnchor: Anchor?=null

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        title = getString(if(selecting) R.string.ez_font_selector else R.string.ez_fonts)
        session = lastNonConfigurationInstance as? Session ?: Session()
        session.task.onChanged = { consume() }
        expanded.addAll(state?.getStringArrayList("expanded").orEmpty())
        selected.addAll(state?.getStringArrayList("selected").orEmpty())
        waitingLocal = state?.getBoolean("waitingLocal") ?: false
        state?.getString("anchorKey")?.let { restoredAnchor=Anchor(it,state.getString("anchorFont"),state.getInt("anchorGroup"),state.getInt("anchorChild",-1),state.getInt("anchorTop")) }
        val column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        progressRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            val pad = NativeUi.dp(context, 12); setPadding(pad, pad, pad, pad)
        }
        status = TextView(this).apply { text = getString(R.string.ez_font_working); textSize = 14f }
        progressRow.addView(status, LinearLayout.LayoutParams(-2, -2))
        progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply { max = 100; isIndeterminate = false }
        progressRow.addView(progressBar, LinearLayout.LayoutParams(0, NativeUi.dp(this, 20), 1f).apply {
            marginStart = NativeUi.dp(this@FontManagerActivity, 12); marginEnd = marginStart
        })
        percent = TextView(this).apply { textSize = 14f }
        progressRow.addView(percent, LinearLayout.LayoutParams(-2, -2))
        column.addView(progressRow, LinearLayout.LayoutParams(-1, -2))
        val frame = FrameLayout(this)
        list = ExpandableListView(this).apply {
            setGroupIndicator(null)
            descendantFocusability=ViewGroup.FOCUS_BLOCK_DESCENDANTS
            divider = android.graphics.drawable.ColorDrawable(0xffdddddd.toInt()); dividerHeight = NativeUi.dp(context, 1)
            setOnGroupClickListener { _, _, index, _ ->
                val group = groups[index]
                if (session.task.running) true
                else if (selected.isNotEmpty()) { toggle(group.fonts.map { it.id }); true }
                else if (group.single || selecting) { preview(group.representative); true }
                else { toggleExpanded(index);true }
            }
            setOnChildClickListener { _, _, group, child, _ ->
                val font = groups[group].fonts[child]
                if (!session.task.running) { if (selected.isNotEmpty()) toggle(listOf(font.id)) else preview(font) }; true
            }
            setOnItemLongClickListener { _, _, position, _ ->
                if(selecting) return@setOnItemLongClickListener false
                if (session.task.running) return@setOnItemLongClickListener true
                val packed = getExpandableListPosition(position)
                val group = groups.getOrNull(ExpandableListView.getPackedPositionGroup(packed)) ?: return@setOnItemLongClickListener false
                val fonts = if (ExpandableListView.getPackedPositionType(packed) == ExpandableListView.PACKED_POSITION_TYPE_CHILD) listOf(group.fonts[ExpandableListView.getPackedPositionChild(packed)]) else group.fonts
                toggle(fonts.map { it.id }); true
            }
            setOnGroupExpandListener { if(!restoringGroups) expanded += groups[it].key }
            setOnGroupCollapseListener { if(!restoringGroups) expanded -= groups[it].key }
        }
        adapter=FontAdapter();list.setAdapter(adapter)
        if(selecting) { list.onItemLongClickListener=null;list.isLongClickable=false }
        frame.addView(list, FrameLayout.LayoutParams(-1, -1))
        empty = TextView(this).apply {
            text = getString(if(selecting) R.string.ez_font_selector_empty else R.string.ez_font_empty); textSize = 16f; gravity = Gravity.CENTER
            setPadding(NativeUi.dp(context, 24), 24, NativeUi.dp(context, 24), 24)
        }
        frame.addView(empty, FrameLayout.LayoutParams(-1, -1)); list.emptyView = empty
        column.addView(frame, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(column)
        refreshBusy()
    }

    override fun onResume() {
        super.onResume(); resumed = true; consume(); load()
        if (waitingLocal && DirectoryAccess.full(this)) { waitingLocal = false; localPicker() }
    }
    override fun onPause() { resumed = false; super.onPause() }
    override fun onDestroy() {
        generation++; session.task.onChanged = null
        reportDialog?.dismiss(); pickerDialog?.dismiss(); super.onDestroy()
    }
    override fun onRetainNonConfigurationInstance(): Any = session
    override fun onSaveInstanceState(out: Bundle) {
        out.putStringArrayList("expanded", ArrayList(expanded)); out.putBoolean("waitingLocal", waitingLocal)
        out.putStringArrayList("selected", ArrayList(selected))
        (anchor() ?: restoredAnchor)?.let {
            out.putString("anchorKey",it.key);out.putString("anchorFont",it.font);out.putInt("anchorGroup",it.group)
            out.putInt("anchorChild",it.child);out.putInt("anchorTop",it.top)
        }
        super.onSaveInstanceState(out)
    }
    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        if(selecting) return false
        menu.add(0, 2, 0, R.string.ez_font_storage).setIcon(NativeUi.actionIcon(this,"ic_settings_material",R.drawable.ic_action_settings)).setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
        menu.add(0, 1, 1, R.string.ez_font_add).setIcon(R.drawable.ic_action_add).setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
        return true
    }
    override fun onPrepareOptionsMenu(menu: Menu): Boolean {
        listOf(1,2).forEach { menu.findItem(it)?.isEnabled = loaded && !session.task.running }
        return super.onPrepareOptionsMenu(menu)
    }
    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        if(selecting) return super.onOptionsItemSelected(item)
        if (item.itemId == 2) { if (!session.task.running && loaded) storageSettings(); return true }
        if (item.itemId != 1) return super.onOptionsItemSelected(item)
        if (!session.task.running && loaded) chooseSource()
        return true
    }

    private fun requireStorage(): Boolean {
        if (storage.mode != FontStorageMode.UNSELECTED) return true
        pickerDialog = com.iqonli.ezcd.ui.FontDialogBuilder(this).setMessage(R.string.ez_font_storage_required)
            .setPositiveButton(android.R.string.ok, null).show()
        return false
    }

    private fun chooseSource() {
        if (!requireStorage()) return
        pickerDialog = com.iqonli.ezcd.ui.FontDialogBuilder(this).setTitle(R.string.ez_font_add)
            .setItems(arrayOf(getString(R.string.ez_font_system_picker), getString(R.string.ez_file_manager), getString(R.string.ez_font_local_picker))) { _, which ->
                if (which == 2) localPicker() else {
                    // Wildcard is intentional: providers often label fonts/ZIPs as application/octet-stream.
                    val intent = Intent(if (which == 0) Intent.ACTION_OPEN_DOCUMENT else Intent.ACTION_GET_CONTENT)
                        .setType("*/*").addCategory(Intent.CATEGORY_OPENABLE)
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION).putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                    runCatching {
                        @Suppress("DEPRECATION")
                        startActivityForResult(if (which == 0) intent else Intent.createChooser(intent, getString(R.string.ez_font_add)), PICK_FILES)
                    }.onFailure { NativeUi.message(this, getString(R.string.ez_font_picker_error)) }
                }
            }.setNegativeButton(android.R.string.cancel, null).show()
    }

    private fun localPicker() {
        if (!DirectoryAccess.full(this)) {
            waitingLocal = true
            runCatching { DirectoryAccess.request(this) }.onFailure { waitingLocal = false; NativeUi.message(this, getString(R.string.ez_font_picker_error)) }
            return
        }
        pickerDialog = FontLocalPicker.show(this) { files -> import(files.map(Uri::fromFile)) }
    }

    @Deprecated("Native activity result API; no AndroidX dependency.")
    override fun onActivityResult(request: Int, result: Int, data: Intent?) {
        super.onActivityResult(request, result, data)
        if(request==APP_FONT) {
            session.choosingAppFont=false
            if(result==RESULT_OK) data?.getStringExtra(FontSelectorActivity.EXTRA_FONT_ID)?.let { AppFonts.choose(this,it) }
            storageSettings();return
        }
        if(request==FontSelectorActivity.REQUEST_PREVIEW) {
            if(result==RESULT_OK && selecting) { setResult(RESULT_OK,data);finish() }
            return
        }
        if (request == PICK_DIRECTORY) {
            session.choosingDirectory = false
            if (result != RESULT_OK || data?.data == null) { session.pendingMode = null; return }
            val uri = checkNotNull(data.data)
            try {
                if (uri.scheme != "file") contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                session.parent = uri.toString(); confirmStorage()
            } catch (_: Exception) { session.pendingMode = null; NativeUi.message(this, getString(R.string.ez_font_action_error)) }
            return
        }
        if (request != PICK_FILES || result != RESULT_OK || data == null || session.task.running) return
        val uris = LinkedHashSet<Uri>()
        data.data?.let(uris::add)
        data.clipData?.let { clip -> repeat(clip.itemCount) { uris += clip.getItemAt(it).uri } }
        uris.filter { it.scheme == "content" }.forEach { uri ->
            runCatching { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
        }
        if (uris.isNotEmpty()) import(uris.toList())
    }

    @Deprecated("Native storage permission API.")
    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, grants: IntArray) {
        super.onRequestPermissionsResult(code, permissions, grants)
        if (code == 4 && waitingLocal) {
            waitingLocal = false
            if (DirectoryAccess.full(this)) localPicker()
        }
    }

    private fun import(uris: List<Uri>) {
        if (!requireStorage()) return
        val context = applicationContext
        session.task.start { progress -> Outcome.Imported(FontImporter(context).import(uris, progress)) }
        refreshBusy()
    }
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if(::session.isInitialized && session.task.running) return true
        return super.dispatchTouchEvent(event)
    }
    private fun refreshBusy() {
        val busy=session.task.running
        if(lastBusy!=busy) {
            val position=anchor()
            window.decorView.alpha=if(busy) .55f else 1f
            fun enable(view: View) { view.isEnabled=!busy;if(view is ViewGroup) for(i in 0 until view.childCount) enable(view.getChildAt(i)) }
            enable(list)
            progressRow.visibility = if (busy) View.VISIBLE else View.GONE
            lastBusy=busy;restore(position);invalidateOptionsMenu()
        }
        progressBar.progress = session.task.progress
        percent.text = getString(R.string.ez_font_percent, session.task.progress)
        progressRow.contentDescription = getString(R.string.ez_font_progress, session.task.progress)
        empty.text = if (session.task.running) "" else getString(if(selecting) R.string.ez_font_selector_empty else R.string.ez_font_empty)
    }
    private fun consume() {
        refreshBusy()
        if (!resumed) return
        val completed = session.task.takeResult() ?: return
        load()
        val app=applicationContext
        com.iqonli.ezcd.data.CountdownIo.execute { runCatching { com.iqonli.ezcd.widget.CountdownWidgetProvider.updateAllWidgets(app) } }
        completed.fold({ outcome ->
            if (outcome is Outcome.Changed) {
                NativeUi.message(this, getString(if (outcome.result.pendingCleanup > 0) R.string.ez_font_cleanup_pending
                    else if (outcome.deleted) R.string.ez_font_deleted else R.string.ez_font_storage_done))
                return@fold
            }
            val report = (outcome as Outcome.Imported).report
            val summary = FontImportSummary.text(this, report)
            if (summary.isNotBlank()) NativeUi.message(this, summary)
            if (report.issues.isNotEmpty()) {
                val text = TextView(this).apply {
                    this.text = summary + "\n\n" + report.issues.joinToString("\n\n") { it.name + "\n" + it.reason }
                    textSize = 14f; setTextIsSelectable(true)
                    val pad = NativeUi.dp(context, 20); setPadding(pad, pad, pad, pad)
                }
                reportDialog = com.iqonli.ezcd.ui.FontDialogBuilder(this).setTitle(R.string.ez_font_import_result)
                    .setView(ScrollView(this).apply { addView(text) }).setPositiveButton(android.R.string.ok, null).show()
            }
        }, { NativeUi.message(this, getString(R.string.ez_font_action_error)) })
    }
    private fun load() {
        val revision=FontRuntime.revision()
        if(loaded && loadedRevision==revision || loadingRevision==revision) return
        loadingRevision=revision
        val token = ++generation; val context = applicationContext
        invalidateOptionsMenu()
        FontIo.submit({ FontCatalog.groups(FontRuntime.fonts(context)) to FontStore(context).storage() }) { result ->
            if (isDestroyed || isFinishing || token != generation) return@submit
            loadingRevision=null
            result.onSuccess {
                val position=anchor() ?: restoredAnchor
                val open=expanded.toSet()
                if(groups!=it.first) {
                    restoringGroups=true
                    groups.indices.forEach { index -> if(list.isGroupExpanded(index)) list.collapseGroup(index) }
                    groups = it.first;adapter.notifyDataSetChanged()
                    groups.forEachIndexed { index, group -> if (!group.single && group.key in open) list.expandGroup(index) }
                    restoringGroups=false
                    expanded.retainAll(groups.map { it.key }.toSet())
                }
                storage = it.second; loaded = true;loadedRevision=revision;AppFonts.refresh(this)
                selected.retainAll(groups.flatMap { it.fonts }.map { it.id }.toSet())
                updateSelection();restore(position);restoredAnchor=null;invalidateOptionsMenu()
                if (session.pendingMode != null && !session.choosingDirectory && !session.task.running && pickerDialog?.isShowing != true) confirmStorage()
            }.onFailure { NativeUi.message(this, getString(R.string.ez_font_load_error)) }
        }
    }
    private fun anchor(): Anchor? {
        if(!::list.isInitialized || list.childCount==0) return null
        val packed=list.getExpandableListPosition(list.firstVisiblePosition)
        val index=ExpandableListView.getPackedPositionGroup(packed)
        val group=groups.getOrNull(index) ?: return null
        val child=ExpandableListView.getPackedPositionChild(packed)
        return Anchor(group.key,group.fonts.getOrNull(child)?.id,index,child,list.getChildAt(0).top-list.paddingTop)
    }
    private fun restore(position: Anchor?) {
        if(position==null || groups.isEmpty()) return
        val index=groups.indexOfFirst { it.key==position.key }.takeIf { it>=0 } ?: position.group.coerceIn(groups.indices)
        val group=groups[index]
        val child=if(group.key==position.key && position.child>=0 && list.isGroupExpanded(index))
            group.fonts.indexOfFirst { it.id==position.font }.takeIf { it>=0 } ?: position.child.coerceIn(group.fonts.indices) else -1
        val packed=if(child>=0) ExpandableListView.getPackedPositionForChild(index,child) else ExpandableListView.getPackedPositionForGroup(index)
        val flat=list.getFlatListPosition(packed)
        if(flat>=0) list.setSelectionFromTop(flat,position.top)
    }
    private fun toggleExpanded(index: Int) {
        if(session.task.running) return
        val position=anchor()
        if(list.isGroupExpanded(index)) list.collapseGroup(index) else list.expandGroup(index)
        restore(position)
    }
    private fun refreshRows() { val position=anchor();adapter.notifyDataSetChanged();restore(position) }
    private fun preview(font: ImportedFont) {
        val intent=FontPreviewActivity.intent(this,font.id).putExtra(FontSelectorActivity.EXTRA_SELECT,selecting)
        if(selecting) startActivityForResult(intent,FontSelectorActivity.REQUEST_PREVIEW) else startActivity(intent)
    }

    private fun storageSettings() {
        pickerDialog = com.iqonli.ezcd.ui.FontDialogBuilder(this).setTitle(R.string.ez_font_storage)
            .setSingleChoiceItems(arrayOf(getString(R.string.ez_font_choose_directory), getString(R.string.ez_font_internal), getString(R.string.ez_font_reference)), storage.mode.ordinal.takeIf { it < 3 } ?: -1) { dialog, which ->
                dialog.dismiss()
                val mode = FontStorageMode.entries[which]
                if (mode == storage.mode && mode != FontStorageMode.DIRECTORY) return@setSingleChoiceItems
                session.pendingMode = mode; session.parent = null
                if (mode == FontStorageMode.DIRECTORY) {
                    session.choosingDirectory = true
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                    storage.directory?.let { intent.putExtra(android.provider.DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(it)) }
                    runCatching { startActivityForResult(intent, PICK_DIRECTORY) }.onFailure {
                        session.choosingDirectory = false; session.pendingMode = null; NativeUi.message(this, getString(R.string.ez_font_picker_error))
                    }
                } else confirmStorage()
            }.setNegativeButton(android.R.string.cancel, null).show()
        val footer=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL;val pad=NativeUi.dp(context,20);setPadding(pad,pad,pad,pad) }
        footer.addView(TextView(this).apply { text=getString(R.string.ez_font_app_display);setTextAppearance(android.R.style.TextAppearance_Material_Title);setTag(R.id.dialog_heading,true) })
        val row=LinearLayout(this);footer.addView(row)
        val selected=groups.flatMap { it.fonts }.firstOrNull { it.id==AppFonts.selected(this) }
        NativeUi.button(row,selected?.metadata?.family ?: getString(R.string.ez_font_system)) {
            session.choosingAppFont=true;pickerDialog?.dismiss();startActivityForResult(FontSelectorActivity.intent(this),APP_FONT)
        }.layoutParams=LinearLayout.LayoutParams(0,-2,1f)
        NativeUi.button(row,getString(R.string.ez_font_restore)) {
            AppFonts.choose(this,null);pickerDialog?.dismiss();storageSettings()
        }.layoutParams=LinearLayout.LayoutParams(0,-2,1f)
        pickerDialog?.listView?.addFooterView(footer,null,false)
        AppFonts.watch(pickerDialog?.window)
    }

    private fun confirmStorage() {
        val mode = session.pendingMode ?: return
        val from = storage.mode
        val parent = session.parent
        if (mode == FontStorageMode.DIRECTORY && parent == null) return
        fun apply(deleteDirectory: Boolean) {
            session.pendingMode = null; session.parent = null
            val context = applicationContext
            session.task.start { progress -> Outcome.Changed(FontStore(context).switchStorage(mode, parent, deleteDirectory, progress)) }
            refreshBusy()
        }
        if (from == FontStorageMode.UNSELECTED) { apply(false); return }
        val dialog = com.iqonli.ezcd.ui.FontDialogBuilder(this).setMessage(FontStoragePolicy.confirmation(from, mode))
            .setOnCancelListener { session.pendingMode = null; session.parent = null }
        if (from == FontStorageMode.DIRECTORY && mode == FontStorageMode.REFERENCE) {
            dialog.setNegativeButton(android.R.string.cancel) { _, _ -> session.pendingMode = null; session.parent = null }
                .setNeutralButton(R.string.ez_delete) { _, _ -> apply(true) }
                .setPositiveButton(R.string.ez_font_keep) { _, _ -> apply(false) }
        } else {
            dialog.setNegativeButton(android.R.string.cancel) { _, _ -> session.pendingMode = null; session.parent = null }
                .setPositiveButton(android.R.string.ok) { _, _ -> apply(false) }
        }
        pickerDialog = dialog.show()
    }

    private fun toggle(ids: List<String>) {
        if (ids.all { it in selected }) selected.removeAll(ids.toSet()) else selected.addAll(ids)
        val position=anchor();updateSelection();refreshRows();restore(position)
    }
    private fun updateSelection() {
        if (selected.isEmpty()) { actionMode?.finish(); return }
        if (actionMode == null) actionMode = startActionMode(object : ActionMode.Callback {
            override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
                menu.add(0, 1, 0, R.string.ez_font_select_all).setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
                menu.add(0, 2, 1, R.string.ez_delete).setIcon(R.drawable.ic_action_delete).setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
                return true
            }
            override fun onPrepareActionMode(mode: ActionMode, menu: Menu) = false
            override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean {
                if (session.task.running) return true
                if (item.itemId == 1) {
                    selected.addAll(groups.flatMap { it.fonts }.map { it.id }); updateSelection()
                    refreshRows()
                } else if (item.itemId == 2) deleteSelected()
                return true
            }
            override fun onDestroyActionMode(mode: ActionMode) {
                actionMode = null; selected.clear(); refreshRows()
            }
        })
        actionMode?.title = getString(R.string.ez_font_selected, selected.size)
    }
    private fun deleteSelected() {
        if (selected.isEmpty()) return
        val ids = selected.toSet(); val context = applicationContext
        pickerDialog = com.iqonli.ezcd.ui.FontDialogBuilder(this).setMessage(R.string.ez_library_delete_question)
            .setNegativeButton(android.R.string.cancel, null).setPositiveButton(R.string.ez_delete) { _, _ ->
                session.task.start { progress -> Outcome.Changed(FontStore(context).delete(ids, progress), true) }
                actionMode?.finish(); refreshBusy()
            }.show()
    }
    override fun navigateBack() { if(session.task.running) return;if (actionMode != null) actionMode?.finish() else super.navigateBack() }

    private inner class FontRow : LinearLayout(this@FontManagerActivity) {
        val checkbox = CheckBox(context).apply { isClickable = false; isFocusable = false; importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }
        val arrow = ImageView(context).apply {
            setImageResource(R.drawable.ic_font_chevron); isFocusable = false
            scaleType=ImageView.ScaleType.CENTER_INSIDE
            val pad=NativeUi.dp(context,4);setPadding(pad,pad,pad,pad)
            val value=android.util.TypedValue();context.theme.resolveAttribute(android.R.attr.selectableItemBackgroundBorderless,value,true)
            setBackgroundResource(value.resourceId)
        }
        val label = TextView(context).apply { setTextColor(0xff333333.toInt()); gravity = Gravity.CENTER_VERTICAL }
        private var childStyle: Boolean?=null
        init {
            orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; minimumHeight = NativeUi.dp(context, 56)
            val toggleSize=NativeUi.dp(context,32)
            addView(checkbox, LayoutParams(toggleSize,toggleSize))
            addView(arrow, LayoutParams(toggleSize,toggleSize))
            addView(label, LayoutParams(0, -2, 1f))
            val value = android.util.TypedValue(); context.theme.resolveAttribute(android.R.attr.selectableItemBackground, value, true); setBackgroundResource(value.resourceId)
        }
        fun bind(text: String, ids: List<String>, child: Boolean) {
            if(label.text.toString()!=text) label.text = text
            if(childStyle!=child) {
                label.textSize = if (child) 15f else 16f
                label.setTypeface(android.graphics.Typeface.DEFAULT, if (child) android.graphics.Typeface.NORMAL else android.graphics.Typeface.BOLD)
                childStyle=child
            }
            checkbox.visibility = if (selected.isEmpty()) View.GONE else View.VISIBLE
            checkbox.isChecked = ids.all { it in selected }
            isActivated = selected.isNotEmpty() && ids.any { it in selected }
            setBackgroundColor(if (isActivated) 0xffe3f2fd.toInt() else android.graphics.Color.TRANSPARENT)
            val vertical=NativeUi.dp(context,if(child) 12 else 4)
            setPadding(NativeUi.dp(context, if (child) 32 else 12), vertical, NativeUi.dp(context, 16), vertical)
            contentDescription = text
            AppFonts.apply(this)
        }
    }

    private inner class FontAdapter : BaseExpandableListAdapter() {
        private val stable=HashMap<String,Long>()
        private fun id(key: String)=stable.getOrPut(key) { stable.size.toLong() }
        override fun getGroupCount() = groups.size
        override fun getChildrenCount(group: Int) = if (groups[group].single) 0 else groups[group].fonts.size
        override fun getGroup(group: Int) = groups[group]
        override fun getChild(group: Int, child: Int) = groups[group].fonts[child]
        override fun getGroupId(group: Int) = id("group:"+groups[group].key)
        override fun getChildId(group: Int, child: Int) = id("font:"+groups[group].fonts[child].id)
        override fun hasStableIds() = true
        override fun isChildSelectable(group: Int, child: Int) = true
        override fun getGroupView(group: Int, open: Boolean, recycled: View?, parent: ViewGroup): View {
            val item = groups[group]
            return (recycled as? FontRow ?: FontRow()).apply {
                bind(if (item.single) "${item.label} (${item.representative.fileName})" else item.label, item.ids, false)
                arrow.visibility = if (item.single) View.GONE else View.VISIBLE
                arrow.rotation = if (open) 90f else 0f
                arrow.contentDescription = getString(R.string.ez_font_expand)
                arrow.setOnClickListener { toggleExpanded(group) }
            }
        }
        override fun getChildView(group: Int, child: Int, last: Boolean, recycled: View?, parent: ViewGroup): View = (recycled as? FontRow ?: FontRow()).apply {
            val font = getChild(group, child)
            bind("${font.metadata.subfamily} (${font.fileName})", listOf(font.id), true)
            arrow.visibility = View.GONE; arrow.setOnClickListener(null)
        }
    }
    companion object {
        private const val APP_FONT=75
        private const val PICK_FILES = 71
        private const val PICK_DIRECTORY = 72
        fun intent(context: Context): Intent = Intent(context, FontManagerActivity::class.java)
    }
}
