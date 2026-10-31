// Copyright (c) 2026 IQ Online Studio. MIT.
package com.iqonli.ezcd.fonts

import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.Menu
import android.view.MenuItem
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.*
import com.iqonli.ezcd.R
import com.iqonli.ezcd.ui.BaseActivity
import com.iqonli.ezcd.ui.FocusAwareDialog
import com.iqonli.ezcd.ui.NativeUi

class FontPreviewActivity : BaseActivity() {
    private val selecting: Boolean get() = intent.getBooleanExtra(FontSelectorActivity.EXTRA_SELECT,false)
    private var font: ImportedFont? = null
    private var face: Typeface? = null
    private var generation = 0
    private lateinit var sample: String
    private val samples = mutableListOf<TextView>()
    private var information: AlertDialog? = null
    private var editor: AlertDialog? = null
    private var editField: EditText? = null
    private var customSize = 100
    private var customField: EditText? = null
    private var customDraft: String? = null
    private var scroll: ScrollView?=null
    private var scrollPosition=0

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        title = getString(R.string.ez_font_preview)
        customSize = (state?.getInt("customSize") ?: getSharedPreferences("font_preview", MODE_PRIVATE).getInt("customSize", 100)).coerceIn(1, 512)
        sample = state?.getString("sample") ?: getSharedPreferences("font_preview", MODE_PRIVATE)
            .getString("sample", null) ?: getString(R.string.ez_font_sample)
        customDraft=state?.getString("customDraft")
        scrollPosition=state?.getInt("scrollPosition") ?: 0
        val loading = TextView(this).apply { text = getString(R.string.ez_font_loading); gravity = Gravity.CENTER }
        setContentView(loading)
        val context = applicationContext; val token = ++generation
        val id = intent.getStringExtra(EXTRA_FONT_ID).orEmpty()
        FontIo.submit({
            FontRuntime.preview(context,id)
        }) { result ->
            if (isDestroyed || isFinishing || token != generation) return@submit
            result.onSuccess { (font, face) ->
                this.font = font; this.face = face; actionBar?.subtitle = font.fileName
                showSamples(); invalidateOptionsMenu()
                if (!selecting && state?.getBoolean("editing") == true) editSample(state.getString("editDraft") ?: sample)
                else if (state?.getBoolean("information") == true) showInformation()
            }.onFailure {
                loading.text = getString(R.string.ez_font_load_error)
                NativeUi.message(this, getString(R.string.ez_font_load_error))
            }
        }
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menu.add(0, 1, 0, R.string.ez_font_information).setIcon(NativeUi.actionIcon(this, "ic_info_outline_material", R.drawable.ic_action_info))
            .setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
        menu.add(0, 2, 1, if(selecting) R.string.ez_font_select else R.string.ez_font_edit_sample).setIcon(if(selecting) getDrawable(R.drawable.ic_font_check) else NativeUi.actionIcon(this, "ic_edit_material", R.drawable.ic_action_edit))
            .setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
        return true
    }
    override fun onPrepareOptionsMenu(menu: Menu): Boolean {
        menu.findItem(1)?.isEnabled = font != null; menu.findItem(2)?.isEnabled = font != null
        return super.onPrepareOptionsMenu(menu)
    }
    override fun onOptionsItemSelected(item: MenuItem): Boolean = when (item.itemId) {
        1 -> { if (font != null) showInformation(); true }
        2 -> { if (font != null) { if(selecting) { setResult(RESULT_OK,Intent().putExtra(FontSelectorActivity.EXTRA_FONT_ID,font!!.id));finish() } else editSample(sample) }; true }
        else -> super.onOptionsItemSelected(item)
    }

    private fun showSamples() {
        val body = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            isFocusableInTouchMode=true
            descendantFocusability=android.view.ViewGroup.FOCUS_BEFORE_DESCENDANTS
            setPadding(NativeUi.dp(context, 6), NativeUi.dp(context, 12), NativeUi.dp(context, 6), NativeUi.dp(context, 24))
        }
        val alphabet = TextView(this).apply {
            text = ALPHABET;setTag(R.id.font_ui_skip,true); typeface = face; textSize = 20f; setTextColor(0xff111111.toInt())
            setHorizontallyScrolling(true); includeFontPadding = true
        }
        body.addView(HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false; addView(alphabet, android.view.ViewGroup.LayoutParams(-2, -2))
        }, LinearLayout.LayoutParams(-1, -2))
        samples.clear()
        fun sampleText(size: Int): TextView = TextView(this).apply {
            text=sample;tag=size;setTag(R.id.font_ui_skip,true);typeface=face;textSize=size.toFloat();setTextColor(0xff111111.toInt())
            setSingleLine(true);includeFontPadding=true;contentDescription=getString(R.string.ez_font_sample_size,size,sample)
            samples+=this
        }
        fun scroll(text: TextView) = HorizontalScrollView(this).apply { isHorizontalScrollBarEnabled=false;addView(text,android.view.ViewGroup.LayoutParams(-2,-2)) }
        SIZES.forEach { size ->
            val row=LinearLayout(this).apply { orientation=LinearLayout.HORIZONTAL;gravity=Gravity.CENTER_VERTICAL;setPadding(0,NativeUi.dp(context,12),0,NativeUi.dp(context,10)) }
            row.addView(TextView(this).apply { text=size.toString();textSize=12f;setTextColor(0xff333333.toInt()) },LinearLayout.LayoutParams(NativeUi.dp(this,22),-2))
            row.addView(scroll(sampleText(size)),LinearLayout.LayoutParams(0,-2,1f));body.addView(row,LinearLayout.LayoutParams(-1,-2))
        }
        val customRow=LinearLayout(this).apply { gravity=Gravity.CENTER_VERTICAL;setPadding(0,NativeUi.dp(context,12),0,NativeUi.dp(context,4)) }
        customRow.addView(TextView(this).apply { text=getString(R.string.ez_font_custom_size);textSize=14f },LinearLayout.LayoutParams(0,-2,1f))
        val field=EditText(this).apply {
            inputType=android.text.InputType.TYPE_CLASS_NUMBER;setSingleLine(true);setSelectAllOnFocus(true)
            filters=arrayOf(android.text.InputFilter.LengthFilter(3));contentDescription=getString(R.string.ez_font_custom_size_hint)
            setText(customDraft ?: customSize.toString())
        }
        customField=field;customRow.addView(field,LinearLayout.LayoutParams(NativeUi.dp(this,96),-2))
        customRow.addView(TextView(this).apply { text="sp";textSize=14f })
        body.addView(customRow,LinearLayout.LayoutParams(-1,-2))
        val customText=sampleText(customSize)
        body.addView(scroll(customText),LinearLayout.LayoutParams(-1,-2))
        field.addTextChangedListener(object: android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?,start: Int,count: Int,after: Int)=Unit
            override fun onTextChanged(s: CharSequence?,start: Int,before: Int,count: Int) {
                customDraft=s?.toString();val size=s?.toString()?.toIntOrNull()
                field.error=if(size==null || size !in 1..512) getString(R.string.ez_font_custom_size_error) else null
                if(size!=null && size in 1..512) {
                    customSize=size;customText.textSize=size.toFloat();customText.tag=size
                    customText.contentDescription=getString(R.string.ez_font_sample_size,size,sample)
                    getSharedPreferences("font_preview",MODE_PRIVATE).edit().putInt("customSize",size).apply()
                }
            }
            override fun afterTextChanged(s: android.text.Editable?)=Unit
        })
        field.error=if(field.text.toString().toIntOrNull()?.let { it in 1..512 }==true) null else getString(R.string.ez_font_custom_size_error)
        scroll=object: ScrollView(this) {
            private var restore=true
            override fun onLayout(changed: Boolean,l: Int,t: Int,r: Int,b: Int) {
                super.onLayout(changed,l,t,r,b)
                if(restore) { restore=false;scrollTo(0,scrollPosition) }
            }
        }.apply { isFillViewport=true;addView(body) }
        setContentView(scroll);body.requestFocus()
    }

    private fun editSample(value: String) {
        val body = NativeUi.column(this)
        val field = EditText(this).apply {
            setSingleLine(true); setText(value); selectAll()
            filters = arrayOf(android.text.InputFilter.LengthFilter(2000))
        }
        body.addView(field); editField = field
        editor = FocusAwareDialog(this).apply {
            setTitle(R.string.ez_edit); setView(body)
            setButton(AlertDialog.BUTTON_NEGATIVE, getString(android.R.string.cancel)) { _, _ -> }
            setButton(AlertDialog.BUTTON_POSITIVE, getString(android.R.string.ok)) { _, _ ->
                sample = field.text.toString()
                getSharedPreferences("font_preview", MODE_PRIVATE).edit().putString("sample", sample).apply()
                samples.forEach { text ->
                    text.text = sample; text.contentDescription = getString(R.string.ez_font_sample_size, text.tag as Int, sample)
                    (text.parent as? HorizontalScrollView)?.scrollTo(0, 0)
                }
            }
            show()
            window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)
            field.post { field.requestFocus(); field.selectAll(); getSystemService(InputMethodManager::class.java).showSoftInput(field, InputMethodManager.SHOW_IMPLICIT) }
        }
    }

    private fun showInformation() {
        val font = font ?: return
        val body = NativeUi.column(this)
        val fields = listOf(4 to "Full Name", 1 to "Font Family", 2 to "Font Subfamily", 3 to "Unique Subfamily Identification",
            5 to "Version", 6 to "PostScript", 9 to "Designer", 0 to "Copyright", 13 to "License")
        fun field(label: String, value: String) {
            NativeUi.label(body, label, 16f).apply { setTextColor(0xff1976d2.toInt()); setTypeface(typeface, Typeface.BOLD) }
            TextView(this).apply {
                text = value.take(16000); textSize = 16f; setTextColor(0xff555555.toInt()); setTextIsSelectable(true)
                setPadding(NativeUi.dp(context, 4), 0, NativeUi.dp(context, 4), NativeUi.dp(context, 12))
                body.addView(this, LinearLayout.LayoutParams(-1, -2))
            }
        }
        fields.forEach { (id, label) -> field(label, font.metadata.names[id] ?: "-") }
        font.metadata.names[14]?.let { field("License URL", it) }
        font.metadata.names[16]?.let { field("Typographic Family", it) }
        font.metadata.names[17]?.let { field("Typographic Subfamily", it) }
        if (font.metadata.axes.isNotEmpty()) field(getString(R.string.ez_font_axes), font.metadata.axes.joinToString("\n") {
            "${it.tag}: ${it.minimum} – ${it.maximum} (${it.default})"
        })
        information = FocusAwareDialog(this).apply {
            setView(ScrollView(this@FontPreviewActivity).apply { addView(body) })
            setButton(AlertDialog.BUTTON_POSITIVE, getString(R.string.ez_font_close)) { _, _ -> }
            show()
        }
    }

    override fun onSaveInstanceState(out: Bundle) {
        out.putString("sample", sample)
        out.putInt("customSize", customSize)
        out.putString("customDraft",customField?.text?.toString())
        out.putInt("scrollPosition",scroll?.scrollY ?: scrollPosition)
        out.putBoolean("editing", editor?.isShowing == true); out.putString("editDraft", editField?.text?.toString())
        out.putBoolean("information", information?.isShowing == true)
        super.onSaveInstanceState(out)
    }
    override fun onDestroy() { generation++; editor?.dismiss(); information?.dismiss(); super.onDestroy() }

    companion object {
        const val EXTRA_FONT_ID = "fontId"
        val SIZES = listOf(12, 18, 24, 36, 48, 60, 72, 80, 88, 96)
        private const val ALPHABET = "abcdefghijklmnopqrstuvwxyz\nABCDEFGHIJKLMNOPQRSTUVWXYZ\n01234567890123456789\n. : , ; ' \" ! ? + - * / % = ~ |\n@ # \$ _ ^ \\ & < > ( ) [ ] { }"
        fun intent(context: Context, fontId: String): Intent = Intent(context, FontPreviewActivity::class.java).putExtra(EXTRA_FONT_ID, fontId)
    }
}
