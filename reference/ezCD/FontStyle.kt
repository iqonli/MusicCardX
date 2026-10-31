// Copyright (c) 2026 IQ Online Studio. MIT.
package com.iqonli.ezcd.fonts

import java.text.Normalizer
import java.util.Locale
import kotlin.math.abs

/** Broken OS/2 classes are common in repackaged font families; explicit style names are useful evidence. */
object FontStyle {
    private fun normalized(value: String) = Normalizer.normalize(value, Normalizer.Form.NFKC)
        .replace(Regex("([a-z])([A-Z])"), "$1 $2").lowercase(Locale.ROOT)
    private fun named(value: String): Int? {
        val s=normalized(value);val compact=s.replace(Regex("[\\s_-]+"),"")
        val explicit=Regex("(?:^|[\\s_-])(?:w|weight)?(1000|[1-9]00)(?:$|[\\s_-])").find(s)?.groupValues?.get(1)?.toIntOrNull()
        if(explicit!=null) return explicit
        Regex("(?:^|[\\s_-])w([1-9])(?:$|[\\s_-])").find(s)?.let { return it.groupValues[1].toInt()*100 }
        val english=listOf("extrablack" to 950,"ultrablack" to 950,"extrabold" to 800,"ultrabold" to 800,"semibold" to 600,"demibold" to 600,
            "extralight" to 200,"ultralight" to 200,"semilight" to 350,"demilight" to 350,"hairline" to 100,"thin" to 100,
            "light" to 300,"book" to 350,"medium" to 500,"black" to 900,"heavy" to 900,"bold" to 700,"regular" to 400,"normal" to 400,"roman" to 400)
        english.firstOrNull { (word,_) -> compact==word || Regex("(?:^|[\\s_-])"+word+"(?:$|[\\s_-])").containsMatchIn(s) ||
            word.length>=8 && compact.contains(word) }?.let { return it.second }
        val chinese=listOf("极细" to 100,"極細" to 100,"特细" to 200,"特細" to 200,"纤细" to 200,"纖細" to 200,"半粗" to 600,"特粗" to 800,"超粗" to 900,
            "中等" to 500,"常规" to 400,"常規" to 400,"标准" to 400,"標準" to 400,"细体" to 300,"細體" to 300,"粗体" to 700,"粗體" to 700)
        chinese.firstOrNull { compact.contains(it.first) }?.let { return it.second }
        return when(compact) { "细","細","l" -> 300;"中","m" -> 500;"粗","b" -> 700;"重","h" -> 900;"r" -> 400;else -> null }
    }
    fun weight(font: ImportedFont): Int = font.styleWeight
    internal fun detectWeight(font: ImportedFont): Int {
        font.metadata.axes.firstOrNull { it.tag=="wght" }?.let { return it.default.toInt().coerceIn(1,1000) }
        val m=font.metadata
        val primary=named(m.subfamily)
        if(primary!=null && primary!=400) return primary
        val family=m.family
        val extra=listOf(m.names[6].orEmpty(),m.fullName,font.fileName.substringBeforeLast('.'))
            .map { it.replace(family,"",ignoreCase=true) }.mapNotNull(::named).firstOrNull { it!=400 }
        if(extra!=null) return extra
        return if(m.weight in 1..9) m.weight*100 else m.weight.coerceIn(1,1000)
    }
    fun italic(font: ImportedFont): Boolean = font.styleItalic
    internal fun detectItalic(font: ImportedFont): Boolean = font.metadata.italic ||
        listOf(font.metadata.subfamily,font.metadata.fullName.replace(font.metadata.family,"",ignoreCase=true),font.fileName.replace(font.metadata.family,"",ignoreCase=true))
            .any { Regex("italic|oblique|slanted|斜体|斜體",RegexOption.IGNORE_CASE).containsMatchIn(it) }
    fun standard(fonts: List<ImportedFont>): ImportedFont = fonts.minWith(compareBy<ImportedFont> { italic(it) }
        .thenBy { abs(weight(it)-400) }.thenBy { if(it.metadata.subfamily.equals("Regular",true)) 0 else 1 }.thenBy { it.id })
    fun compareNames(a: String,b: String): Int {
        val aa=Regex("\\d+|\\D+").findAll(a.lowercase(Locale.ROOT)).map { it.value }.toList()
        val bb=Regex("\\d+|\\D+").findAll(b.lowercase(Locale.ROOT)).map { it.value }.toList()
        for(i in 0 until minOf(aa.size,bb.size)) {
            val x=aa[i];val y=bb[i]
            val c=if(x.first().isDigit() && y.first().isDigit()) x.trimStart('0').length.compareTo(y.trimStart('0').length).takeIf { it!=0 } ?: x.trimStart('0').compareTo(y.trimStart('0')) else x.compareTo(y)
            if(c!=0) return c
        }
        return aa.size.compareTo(bb.size)
    }
}
