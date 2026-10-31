// Copyright (c) 2026 IQ Online Studio. MIT.
package com.iqonli.ezcd.fonts
import android.content.Context
import android.content.Intent
class FontSelectorActivity : FontManagerActivity() {
    companion object {
        const val EXTRA_SELECT="selectFont"
        const val EXTRA_FONT_ID="fontId"
        internal const val REQUEST_PREVIEW=74
        fun intent(context: Context)=Intent(context,FontSelectorActivity::class.java)
    }
}
