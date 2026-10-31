package com.iqonli.musiccardx
import android.content.*
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
class ImageProvider:ContentProvider(){
  override fun onCreate()=true
  private fun file(uri:Uri):File{val name=uri.lastPathSegment?:error("Invalid image");require(Regex("MusicCardX-[0-9a-f]+\\.(png|jpg)").matches(name));val root=File(checkNotNull(context).cacheDir,"images").canonicalFile;return File(root,name).canonicalFile.also{require(it.parentFile==root)}}
  override fun getType(uri:Uri)=if(file(uri).extension=="jpg")"image/jpeg" else "image/png"
  override fun openFile(uri:Uri,mode:String):ParcelFileDescriptor{require(mode=="r");return ParcelFileDescriptor.open(file(uri),ParcelFileDescriptor.MODE_READ_ONLY)}
  override fun query(uri:Uri,projection:Array<out String>?,selection:String?,args:Array<out String>?,sort:String?):Cursor{val f=file(uri);return MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE)).apply{addRow(arrayOf(uri.getQueryParameter("name")?.take(200)?.map { if(it.code<32 || it in "/\\:*?\"<>|") '_' else it }?.joinToString("")?.takeIf {it.isNotBlank()} ?: f.name,f.length()))}}
  override fun insert(uri:Uri,values:ContentValues?):Uri?=throw UnsupportedOperationException()
  override fun update(uri:Uri,values:ContentValues?,selection:String?,args:Array<out String>?)=throw UnsupportedOperationException()
  override fun delete(uri:Uri,selection:String?,args:Array<out String>?)=throw UnsupportedOperationException()
}
