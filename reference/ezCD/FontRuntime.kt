// Copyright (c) 2026 IQ Online Studio. MIT.
package com.iqonli.ezcd.fonts

import android.content.Context
import android.graphics.Typeface
import android.os.Build
import android.text.TextPaint
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs

/** Bounded shared typeface cache. No file access is performed by the UI's cached lookup. */
internal object FontRuntime {
    private val revision=AtomicLong()
    private data class Catalog(val root: String,val revision: Long,val fonts: List<ImportedFont>) {
        val byId=fonts.associateBy { it.id }
        val families=fonts.groupBy { it.metadata.familyKey }
        fun family(id: String?)=byId[id]?.let { families[it.metadata.familyKey] }.orEmpty()
    }
    @Volatile private var catalog=Catalog("",-1L,emptyList())
    private val faces=android.util.LruCache<String,Typeface>(32)
    fun invalidate() { revision.incrementAndGet() }
    fun revision(): Long=revision.get()
    @Synchronized fun fonts(context: Context): List<ImportedFont> {
        val token=revision.get()
        if(catalog.revision!=token || catalog.root!=context.filesDir.path) {
            val fonts=FontStore(context).fonts()
            faces.evictAll();catalog=Catalog(context.filesDir.path,token,fonts)
        }
        return catalog.fonts
    }
    fun family(fonts: List<ImportedFont>,id: String?): List<ImportedFont> {
        val selected=fonts.firstOrNull { it.id==id } ?: return emptyList()
        return fonts.filter { it.metadata.familyKey==selected.metadata.familyKey }
    }
    fun variable(fonts: List<ImportedFont>) = fonts.firstNotNullOfOrNull { font -> font.metadata.axes.firstOrNull { it.tag=="wght" } }
    data class Match(val font: ImportedFont,val weight: Int,val variations: String?,val syntheticItalic: Boolean)
    fun match(family: List<ImportedFont>,weight: Int,italic: Boolean): Match? {
        if(family.isEmpty()) return null
        fun supports(font: ImportedFont) = FontStyle.italic(font)==italic || font.metadata.axes.any {
            if(italic) it.tag=="ital" && it.maximum>0 || it.tag=="slnt" && (it.minimum<0 || it.maximum>0)
            else it.tag in setOf("ital","slnt") && 0f in it.minimum..it.maximum
        }
        val styled=family.filter(::supports).ifEmpty { family }
        val selected=styled.minWith(compareBy<ImportedFont> { f ->
            val axis=f.metadata.axes.firstOrNull { it.tag=="wght" }
            if(axis!=null && weight.toFloat() in axis.minimum..axis.maximum) 0 else abs(FontStyle.weight(f)-weight)
        }.thenBy { if(it.metadata.axes.any { a -> a.tag=="wght" }) 0 else 1 }.thenBy { it.id })
        val axes=selected.metadata.axes
        val settings=axes.mapNotNull { a ->
            val value=when(a.tag) {
                "wght" -> weight.toFloat().coerceIn(a.minimum,a.maximum)
                "ital" -> (if(italic) 1f else 0f).coerceIn(a.minimum,a.maximum)
                "slnt" -> (if(italic) (if(a.minimum<0) -12f else 12f) else 0f).coerceIn(a.minimum,a.maximum)
                else -> return@mapNotNull null
            }
            "'${a.tag}' $value"
        }.joinToString(", ").ifBlank { null }
        return Match(selected,axes.firstOrNull { it.tag=="wght" }?.let { weight.toFloat().coerceIn(it.minimum,it.maximum).toInt() } ?: FontStyle.weight(selected),settings,
            italic && !FontStyle.italic(selected) && axes.none { it.tag=="ital" && it.maximum>0 || it.tag=="slnt" && (it.minimum<0 || it.maximum>0) })
    }
    fun resolve(context: Context,id: String?,weight: Int,italic: Boolean): Pair<Typeface,Boolean> {
        if(id.isNullOrEmpty()) return system(weight,italic) to false
        fonts(context)
        val match=match(catalog.family(id),weight,italic) ?: return system(weight,italic) to false
        val key="${match.font.id}|${match.variations}"
        val face=faces.get(key) ?: runCatching { FontStore(context).typeface(match.font,match.variations) }.getOrNull()?.also { faces.put(key,it) }
        return if(face==null) system(weight,italic) to false else face to match.syntheticItalic
    }
    // This UI lookup must never wait for a ZIP/provider read held by resolve().
    fun cachedPaint(id: String,weight: Int,italic: Boolean): TextPaint? {
        val match=match(catalog.family(id),weight,italic) ?: return null
        val face=faces.get("${match.font.id}|${match.variations}") ?: return null
        return TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG or android.graphics.Paint.SUBPIXEL_TEXT_FLAG).apply { typeface=face;textSkewX=if(match.syntheticItalic) -.2f else 0f }
    }
    fun preview(context: Context,id: String): Pair<ImportedFont,Typeface> {
        val font=fonts(context).firstOrNull { it.id==id } ?: error("Font was removed")
        val key="${font.id}|null"
        val face=faces.get(key) ?: FontStore(context).typeface(font).also { faces.put(key,it) }
        return font to face
    }
    fun system(weight: Int,italic: Boolean): Typeface = if(Build.VERSION.SDK_INT>=28) Typeface.create(Typeface.SANS_SERIF,weight.coerceIn(1,1000),italic)
        else Typeface.create(if(weight<350) "sans-serif-light" else "sans-serif",when { weight>=600 && italic -> Typeface.BOLD_ITALIC;weight>=600 -> Typeface.BOLD;italic -> Typeface.ITALIC;else -> Typeface.NORMAL })
    fun paint(context: Context,id: String?,weight: Int,italic: Boolean): TextPaint {
        if(id.isNullOrEmpty() || fonts(context).none { it.id==id }) {
            // Match the RemoteViews/TextAppearance path, including OEM family and fake-bold flags.
            return com.iqonli.ezcd.widget.NativeWidgetRenderer.paint(context,weight).apply {
                if(italic) {
                    val variation=fontVariationSettings
                    typeface=Typeface.create(typeface,if(typeface.isBold) Typeface.BOLD_ITALIC else Typeface.ITALIC)
                    if(variation!=null) fontVariationSettings=variation
                }
            }
        }
        val (face,skew)=resolve(context,id,weight,italic)
        return TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG or android.graphics.Paint.SUBPIXEL_TEXT_FLAG).apply { typeface=face;textSkewX=if(skew) -.2f else 0f }
    }
}
