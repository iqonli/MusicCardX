// Copyright (c) 2026 IQ Online Studio. MIT.
package com.iqonli.ezcd.fonts

import java.io.File
import java.io.RandomAccessFile
import java.nio.charset.Charset
import java.text.Normalizer
import java.util.Locale

data class FontAxis(val tag: String, val minimum: Float, val default: Float, val maximum: Float)

data class FontMetadata(
    val faceIndex: Int,
    val names: Map<Int, String>,
    val weight: Int,
    val italic: Boolean,
    val axes: List<FontAxis> = emptyList(),
) {
    val family: String = names[16] ?: names[1] ?: names[4].orEmpty()
    val subfamily: String = names[17] ?: names[2] ?: "Regular"
    val fullName: String = names[4] ?: listOf(family, subfamily).filter(String::isNotBlank).joinToString(" ")
    val familyKey: String = Normalizer.normalize(family, Normalizer.Form.NFC).trim().lowercase(Locale.ROOT)
}

/** Reads bounded SFNT tables, never trusting offsets from an imported file. TTC offsets are absolute. */
object FontMetadataReader {
    const val MAX_FACES = 128
    private const val MAX_NAME_BYTES = 2 * 1024 * 1024

    fun read(file: File): List<FontMetadata> = RandomAccessFile(file, "r").use { input ->
        require(input.length() >= 12) { "Invalid font header" }
        val signature = input.readInt()
        val offsets = if (signature == 0x74746366) {
            val version = input.readInt()
            require(version == 0x00010000 || version == 0x00020000) { "Unsupported font collection" }
            val count = input.readInt()
            require(count in 1..MAX_FACES) { "Invalid font collection size" }
            require(12L + count * 4L <= input.length()) { "Truncated font collection" }
            List(count) { input.readInt().toLong() and 0xffffffffL }
        } else listOf(0L)
        offsets.mapIndexed { index, offset -> readFace(input, offset, index) }
    }

    private data class Table(val offset: Long, val length: Long)

    private fun readFace(input: RandomAccessFile, offset: Long, faceIndex: Int): FontMetadata {
        range(input, offset, 12)
        input.seek(offset)
        require(input.readInt() in setOf(0x00010000, 0x4f54544f, 0x74727565)) { "Unsupported font format" }
        val count = input.readUnsignedShort()
        require(count in 1..256) { "Invalid font table count" }
        range(input, offset + 12, count * 16L)
        input.seek(offset + 12)
        val tables = LinkedHashMap<String, Table>()
        repeat(count) {
            val tag = ByteArray(4).also(input::readFully).toString(Charsets.ISO_8859_1)
            input.readInt()
            val tableOffset = input.readInt().toLong() and 0xffffffffL
            val length = input.readInt().toLong() and 0xffffffffL
            range(input, tableOffset, length)
            require(tables.put(tag, Table(tableOffset, length)) == null) { "Duplicate font table" }
        }
        val names = readNames(input, tables["name"] ?: error("Missing font names"))
        require(!names[4].isNullOrBlank() || !names[1].isNullOrBlank() || !names[16].isNullOrBlank()) { "Missing font name" }
        var weight = 400
        var italic = false
        tables["OS/2"]?.let { table ->
            if (table.length >= 6) {
                input.seek(table.offset + 4)
                weight = input.readUnsignedShort().takeIf { it in 1..1000 } ?: 400
            }
            if (table.length >= 64) {
                input.seek(table.offset + 62)
                italic = input.readUnsignedShort() and 0x201 != 0
            }
        }
        tables["head"]?.takeIf { it.length>=46 }?.let { table ->
            input.seek(table.offset+44);val flags=input.readUnsignedShort();italic=italic || flags and 2!=0
            if(weight==400 && flags and 1!=0) weight=700
        }
        tables["post"]?.takeIf { it.length>=8 }?.let { table -> input.seek(table.offset+4);italic=italic || input.readInt()!=0 }
        val axes = tables["fvar"]?.let { readAxes(input, it) }.orEmpty()
        return FontMetadata(faceIndex, names, weight, italic, axes)
    }

    private fun readNames(input: RandomAccessFile, table: Table): Map<Int, String> {
        require(table.length in 6..MAX_NAME_BYTES.toLong()) { "Invalid naming table" }
        input.seek(table.offset)
        require(input.readUnsignedShort() in 0..1) { "Unsupported naming table" }
        val count = input.readUnsignedShort()
        val strings = input.readUnsignedShort()
        require(6L + count * 12L <= table.length && strings >= 6L + count * 12L && strings <= table.length) { "Invalid name records" }
        val chosen = mutableMapOf<Int, Pair<Int, String>>()
        repeat(count) { index ->
            input.seek(table.offset + 6 + index * 12L)
            val platform = input.readUnsignedShort()
            val encoding = input.readUnsignedShort()
            val language = input.readUnsignedShort()
            val id = input.readUnsignedShort()
            val length = input.readUnsignedShort()
            val offset = input.readUnsignedShort()
            require(strings + offset.toLong() + length <= table.length) { "Invalid font name offset" }
            val charset = when {
                platform == 0 || platform == 3 && encoding in setOf(0, 1, 10) -> Charsets.UTF_16BE
                platform == 1 && encoding == 0 -> Charset.forName("x-MacRoman")
                else -> null
            } ?: return@repeat
            if (charset == Charsets.UTF_16BE && length % 2 != 0) return@repeat
            input.seek(table.offset + strings + offset)
            val text = ByteArray(length).also(input::readFully).toString(charset)
                .filter { !it.isISOControl() || it == '\n' || it == '\t' }.trim()
            if (text.isBlank()) return@repeat
            // Pick the same language for all faces, independent of the current UI locale.
            val score = when {
                platform == 3 && language == 0x0409 -> 100
                platform == 0 -> 90
                platform == 1 && language == 0 -> 80
                platform == 3 && language and 0x3ff == 9 -> 70
                platform == 3 -> 60
                else -> 10
            }
            if (score > (chosen[id]?.first ?: -1)) chosen[id] = score to text
        }
        return chosen.mapValues { it.value.second }
    }

    private fun readAxes(input: RandomAccessFile, table: Table): List<FontAxis> {
        require(table.length >= 16) { "Invalid variation table" }
        input.seek(table.offset)
        require(input.readUnsignedShort() == 1) { "Unsupported variation table" }
        input.readUnsignedShort()
        val offset = input.readUnsignedShort()
        input.readUnsignedShort()
        val count = input.readUnsignedShort()
        val size = input.readUnsignedShort()
        require(count <= 64 && size >= 20 && offset >= 16 && offset + count * size.toLong() <= table.length) { "Invalid font axes" }
        return List(count) { index ->
            input.seek(table.offset + offset + index * size.toLong())
            val tag = ByteArray(4).also(input::readFully).toString(Charsets.ISO_8859_1)
            val minimum = input.readInt() / 65536f
            val default = input.readInt() / 65536f
            val maximum = input.readInt() / 65536f
            require(minimum <= default && default <= maximum) { "Invalid font axis range" }
            FontAxis(tag, minimum, default, maximum)
        }
    }

    private fun range(input: RandomAccessFile, offset: Long, length: Long) {
        require(offset >= 0 && length >= 0 && offset <= input.length() && length <= input.length() - offset) { "Font table outside file" }
    }
}
