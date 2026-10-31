// Copyright (c) 2026 IQ Online Studio. MIT.
package com.iqonli.ezcd.fonts

import java.util.Locale

data class FontSource(val uri: String, val zipEntry: String? = null, val zipIndex: Int = -1)
data class ImportedFont(val id: String, val blob: String, val fileName: String, val metadata: FontMetadata, val source: FontSource? = null) {
    // Records are immutable; sorting and paint matching can share the parsed style.
    internal val styleWeight by lazy(LazyThreadSafetyMode.PUBLICATION) { FontStyle.detectWeight(this) }
    internal val styleItalic by lazy(LazyThreadSafetyMode.PUBLICATION) { FontStyle.detectItalic(this) }
}

enum class FontStorageMode { DIRECTORY, INTERNAL, REFERENCE, UNSELECTED }
data class FontStorage(val mode: FontStorageMode = FontStorageMode.UNSELECTED, val directory: String? = null, val root: String? = null)
data class FontChangeResult(val pendingCleanup: Int = 0)

data class FontFamilyGroup(val key: String, val fonts: List<ImportedFont>) {
    val representative: ImportedFont by lazy(LazyThreadSafetyMode.PUBLICATION) { FontStyle.standard(fonts) }
    val ids: List<String> by lazy(LazyThreadSafetyMode.PUBLICATION) { fonts.map { it.id } }
    val label: String get() = representative.metadata.fullName
    val single: Boolean get() = fonts.size == 1
}

object FontCatalog {
    fun groups(fonts: List<ImportedFont>): List<FontFamilyGroup> = fonts.groupBy { it.metadata.familyKey }
        .map { (key, faces) -> FontFamilyGroup(key, faces.sortedWith(Comparator { a,b ->
            compareValuesBy(a,b,{ FontStyle.weight(it) },{ FontStyle.italic(it) }).takeIf { it!=0 }
                ?: FontStyle.compareNames(a.metadata.subfamily,b.metadata.subfamily).takeIf { it!=0 }
                ?: FontStyle.compareNames(a.fileName,b.fileName).takeIf { it!=0 } ?: a.id.compareTo(b.id)
        })) }
        .sortedWith(compareBy<FontFamilyGroup> { it.label.lowercase(Locale.ROOT) }.thenBy { it.key })
}
