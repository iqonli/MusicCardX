// Copyright (c) 2026 IQ Online Studio. MIT.
package com.iqonli.ezcd.fonts

import android.app.Activity
import android.app.AlertDialog
import android.view.inputmethod.EditorInfo
import android.widget.*
import com.iqonli.ezcd.R
import com.iqonli.ezcd.ui.DirectoryAccess
import com.iqonli.ezcd.ui.FocusAwareDialog
import com.iqonli.ezcd.ui.NativeUi
import java.io.File
import java.util.Locale

internal object FontLocalPicker {
    fun show(activity: Activity, selected: (List<File>) -> Unit): AlertDialog {
        val body = NativeUi.column(activity)
        val path = EditText(activity).apply { setSingleLine(true); imeOptions = EditorInfo.IME_ACTION_GO }
        body.addView(path)
        val list = ListView(activity).apply { choiceMode = ListView.CHOICE_MODE_MULTIPLE }
        body.addView(list, LinearLayout.LayoutParams(-1, (activity.resources.displayMetrics.heightPixels * .62f).toInt().coerceAtLeast(NativeUi.dp(activity, 180))))
        var current = DirectoryAccess.downloads()
        var entries = emptyList<File>()
        var serial = 0
        val chosen = linkedSetOf<File>()
        val dialog = FocusAwareDialog(activity).apply {
            setTitle(R.string.ez_font_local_picker); setView(body)
            setButton(AlertDialog.BUTTON_NEGATIVE, activity.getString(android.R.string.cancel)) { _, _ -> }
            setButton(AlertDialog.BUTTON_POSITIVE, activity.getString(R.string.ez_font_import_selected, 0)) { _, _ -> }
        }
        fun updateButton() {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE)?.apply {
                text = activity.getString(R.string.ez_font_import_selected, chosen.size); isEnabled = chosen.isNotEmpty()
            }
        }
        fun load(file: File) {
            val token = ++serial
            FontIo.submit({
                val folder = file.canonicalFile; require(folder.isDirectory && folder.canRead()) { "Unreadable directory" }
                val children = folder.listFiles()?.filter { it.isDirectory || FontImporter.supported(it.name) || it.extension.equals("zip", true) }
                    ?.sortedWith(compareBy<File> { !it.isDirectory }.thenBy { it.name.lowercase(Locale.ROOT) }) ?: error("Unreadable directory")
                folder to children
            }) { result ->
                if (!dialog.isShowing || activity.isDestroyed || token != serial) return@submit
                result.onSuccess { (folder, children) ->
                    current = folder; entries = children; path.setText(folder.path); path.error = null
                    list.adapter = ArrayAdapter(activity, android.R.layout.simple_list_item_multiple_choice,
                        listOf(activity.getString(R.string.ez_parent_directory)) + children.map { it.name + if (it.isDirectory) "/" else "" })
                    list.clearChoices()
                    children.forEachIndexed { index, child -> list.setItemChecked(index + 1, child in chosen) }
                }.onFailure { path.error = activity.getString(R.string.ez_font_picker_error) }
            }
        }
        dialog.setOnShowListener {
            updateButton()
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener { selected(chosen.toList()); dialog.dismiss() }
            list.setOnItemClickListener { _, _, position, _ ->
                if (position == 0) load(current.parentFile ?: current)
                else entries.getOrNull(position - 1)?.let { file ->
                    if (file.isDirectory) load(file)
                    else { if (file in chosen) chosen -= file else chosen += file; list.setItemChecked(position, file in chosen); updateButton() }
                }
            }
            path.setOnEditorActionListener { _, action, _ ->
                if (action == EditorInfo.IME_ACTION_GO) { load(File(path.text.toString())); true } else false
            }
            load(current)
        }
        dialog.setOnDismissListener { serial++ }
        dialog.show()
        dialog.window?.setLayout((activity.resources.displayMetrics.widthPixels * .96f).toInt(), android.view.ViewGroup.LayoutParams.WRAP_CONTENT)
        return dialog
    }
}
