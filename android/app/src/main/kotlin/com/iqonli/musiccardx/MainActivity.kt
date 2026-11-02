package com.iqonli.musiccardx
import android.app.Activity
import android.content.*
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.provider.MediaStore
import android.media.MediaScannerConnection
import android.Manifest
import android.content.pm.PackageManager
import android.provider.OpenableColumns
import android.util.AtomicFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import android.provider.DocumentsContract
import java.io.ByteArrayOutputStream

class MainActivity:FlutterActivity() {
  private val storage by lazy { StorageMaintenance(filesDir, cacheDir) }
  private val cleanupHandler = android.os.Handler(android.os.Looper.getMainLooper())
  private val cleanupTick = object : Runnable {
    override fun run() { io.execute { maintainStorage() }; cleanupHandler.postDelayed(this, 120_000) }
  }
  private fun maintainStorage(startup: Boolean = false) {
    runCatching {
      val state = File(filesDir, "document.json")
      // A damaged state/preset must never cause its referenced cover to be lost.
      val references = runCatching {
        val paths = mutableSetOf<String>()
        // Older Android AtomicFile versions may recover document.json.bak on read.
        // Retain both references until the atomic transaction has been resolved.
        for (candidate in listOf(state, File(filesDir,"document.json.bak"))) {
          if (candidate.exists()) paths.add(org.json.JSONObject(candidate.readText()).optString("coverPath"))
        }
        File(filesDir,"presets").listFiles()?.filter { it.extension == "json" }?.forEach {
          paths.add(org.json.JSONObject(it.readText()).optString("coverPath"))
        }
        paths.filter { it.isNotEmpty() }.toSet()
      }.getOrNull()
      storage.clean(references, getPreferences(Context.MODE_PRIVATE).getString("clipboardImage", null), startup)
    }
  }
  override fun onCreate(savedInstanceState: Bundle?) {
    // Queue startup cleanup before configureFlutterEngine queues new incoming files.
    io.execute { maintainStorage(true) }
    super.onCreate(savedInstanceState)
    cleanupHandler.postDelayed(cleanupTick, 120_000)
  }
  override fun onStop() { super.onStop(); io.execute { maintainStorage() } }
  override fun onDestroy() {
    cleanupHandler.removeCallbacks(cleanupTick)
    io.execute { maintainStorage() }
    super.onDestroy()
    io.shutdown()
  }
  private val incoming=java.util.ArrayDeque<Map<String,Any>>()
  private var channel:MethodChannel?=null
  private val io=Executors.newSingleThreadExecutor()
  private var pending:MethodChannel.Result?=null
  private var output:ByteArray?=null
  private var storageResult:MethodChannel.Result?=null
  private fun storageAllowed()=if(Build.VERSION.SDK_INT>=30)Environment.isExternalStorageManager() else checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)==PackageManager.PERMISSION_GRANTED
  private val presets get()=File(filesDir,"presets").apply { mkdirs() }
  override fun configureFlutterEngine(engine:FlutterEngine){super.configureFlutterEngine(engine);channel=MethodChannel(engine.dartExecutor.binaryMessenger,"com.iqonli.musiccardx/platform");channel!!.setMethodCallHandler(::call);capture(intent)}
  override fun onNewIntent(intent:Intent){super.onNewIntent(intent);setIntent(intent);capture(intent)}
  private fun capture(intent:Intent?){if(intent==null || intent.action !in listOf(Intent.ACTION_SEND,Intent.ACTION_VIEW))return
    @Suppress("DEPRECATION") val uri=if(intent.action==Intent.ACTION_SEND)intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)else intent.data
    val mime=intent.type ?: uri?.let{runCatching{contentResolver.getType(it)}.getOrNull()} ?: ""
    val image=mime.startsWith("image/");val audio=mime.startsWith("audio/") || mime in listOf("application/ogg","application/x-ogg")
    val text=intent.getStringExtra(Intent.EXTRA_TEXT)
    io.execute {val r=runCatching {if(audio){require(uri!=null);val root=File(cacheDir,"audio-import").apply{mkdirs()};val f=File(root,"${java.util.UUID.randomUUID()}.audio");try{contentResolver.openInputStream(uri)!!.use{input->f.outputStream().use{out->val buffer=ByteArray(65536);var count=0L;while(true){val n=input.read(buffer);if(n<0)break;count+=n;require(count<=2147483648L){"音频文件超过2GB"};out.write(buffer,0,n)}}};mapOf<String,Any>("kind" to "audio","path" to f.path)}catch(e:Exception){f.delete();throw e}}else if(image){require(uri!=null);val root=File(cacheDir,"incoming-images").apply{mkdirs()};val f=File(root,"shared-${java.util.UUID.randomUUID()}.image");contentResolver.openInputStream(uri)!!.use{input->f.outputStream().use{out->val b=ByteArray(65536);var size=0;while(true){val n=input.read(b);if(n<0)break;size+=n;require(size<=67108864);out.write(b,0,n)}}};mapOf<String,Any>("kind" to "image","path" to f.path)}else{val body=if(uri!=null)contentResolver.openInputStream(uri)!!.use{input->val out=ByteArrayOutputStream();val b=ByteArray(65536);while(true){val n=input.read(b);if(n<0)break;require(out.size()+n<=8388608);out.write(b,0,n)};out.toByteArray().toString(Charsets.UTF_8).removePrefix("\uFEFF")}else text?:"";mapOf<String,Any>("kind" to "json","text" to body,"jsonFile" to (mime.contains("json") || uri?.path?.endsWith(".json",true)==true))}}
    r.getOrNull()?.get("path")?.let { storage.leases.add(it.toString()) }
    runOnUiThread{incoming.addLast(r.getOrElse{mapOf("kind" to "error","text" to (it.message?:"读取失败"))});channel?.invokeMethod("incoming",null)}}}

  private fun work(result:MethodChannel.Result,task:()->Any?){io.execute {val r=runCatching(task);runOnUiThread {r.fold(result::success){result.error("MCX_IO",it.message,null)}}}}
  private fun call(call:MethodCall,result:MethodChannel.Result){
    try {when(call.method){
      "catalogProgress" -> result.success(mapOf("loaded" to ActivityCatalog.loaded.get(), "total" to ActivityCatalog.total.get()))
      "catalogLoad", "catalogApps", "catalogActivities", "catalogSearch", "catalogIcon" -> work(result) { ActivityCatalog.read(this, call.method, call.arguments as? Map<*, *> ?: emptyMap<String, Any>()) }
      "textActions", "actionPermissions", "actionPermissionSettings", "launchAction" -> result.success(IntentActions.handle(this, call.method, call.arguments as? Map<*, *> ?: emptyMap<String, Any>()))
      "maintainStorage"->work(result){maintainStorage();null}
      "releaseIncoming"->work(result){storage.release(checkNotNull(call.argument<String>("path")));maintainStorage();null}
      "openUrl"->{val uri=Uri.parse(checkNotNull(call.argument<String>("url")));require(uri.scheme=="https" && !uri.host.isNullOrEmpty());startActivity(Intent(Intent.ACTION_VIEW,uri));result.success(null)}
      "takeIncoming"->result.success(incoming.pollFirst())
      "requestStorage"->{if(storageAllowed())result.success(true) else {check(storageResult==null);storageResult=result;if(Build.VERSION.SDK_INT>=30){try{startActivityForResult(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,Uri.parse("package:$packageName")),108)}catch(e:ActivityNotFoundException){startActivityForResult(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION),108)}}else requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE,Manifest.permission.WRITE_EXTERNAL_STORAGE),109)}}
      "scanImage"->{val path=checkNotNull(call.argument<String>("path"));MediaScannerConnection.scanFile(this,arrayOf(path),arrayOf(call.argument<String>("mime") ?: "image/png"),null);result.success(null)}
      "loadState"->work(result){val file=AtomicFile(File(filesDir,"document.json"));if(file.baseFile.exists())file.openRead().use { it.readBytes().toString(Charsets.UTF_8) } else null}
      "saveState"->work(result){val file=AtomicFile(File(filesDir,"document.json"));val stream=file.startWrite();try {stream.write(checkNotNull(call.argument<String>("json")).toByteArray());file.finishWrite(stream)}catch(e:Exception){file.failWrite(stream);throw e};null}
      "uriRead"->work(result){val uri=Uri.parse(checkNotNull(call.argument<String>("uri")));contentResolver.openInputStream(uri)!!.use { input->val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(65536);while(true){val n=input.read(buffer);if(n<0)break;require(out.size().toLong()+n<=268435456);out.write(buffer,0,n)};out.toByteArray() }}
      "storageRoot"->result.success(filesDir.absolutePath)
      "pickFiles"->{begin(result);startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*").putExtra(Intent.EXTRA_ALLOW_MULTIPLE,true).addCategory(Intent.CATEGORY_OPENABLE),106)}
      "pickTree"->{begin(result);startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION),107)}
      "treeRead"->work(result){
        val tree=Uri.parse(checkNotNull(call.argument<String>("tree")));val path=checkNotNull(call.argument<String>("path"));val parts=path.split('/')
        require((path=="ezcd-fonts.json" || parts.size==2) && parts.all { it.isNotEmpty() && it!="." && it!=".." && !it.contains('\\') && !it.contains(':') && it.none { c->c.code<32 || c.code==127 } })
        var id=DocumentsContract.getTreeDocumentId(tree)
        for(part in parts){val children=DocumentsContract.buildChildDocumentsUriUsingTree(tree,id);var next:String?=null;contentResolver.query(children,arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,DocumentsContract.Document.COLUMN_DISPLAY_NAME),null,null,null)?.use { cursor->while(cursor.moveToNext()){if(cursor.getString(1)==part){check(next==null){"Duplicate document name"};next=cursor.getString(0)}} };id=checkNotNull(next){"文件不存在：$part"}}
        val uri=DocumentsContract.buildDocumentUriUsingTree(tree,id);val limit=(call.argument<Number>("limit")?.toInt()?:8388608).coerceIn(1,268435456);contentResolver.openInputStream(uri)!!.use { input->val out=ByteArrayOutputStream();val buffer=ByteArray(65536);while(true){val n=input.read(buffer);if(n<0)break;require(out.size().toLong()+n<=limit){"文件超过大小限制"};out.write(buffer,0,n)};out.toByteArray() }
      }
      "pickCover"->{begin(result);val photo=Intent("android.provider.action.PICK_IMAGES").setType("image/*");startActivityForResult(if(photo.resolveActivity(packageManager)!=null)photo else Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE),103)}
      "importJson"->{begin(result);startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*").addCategory(Intent.CATEGORY_OPENABLE),104)}
      "saveImage","exportJson"->{begin(result);output=if(call.method=="saveImage")checkNotNull(call.argument<ByteArray>("bytes"))else checkNotNull(call.argument<String>("json")).toByteArray();val mime=if(call.method=="saveImage")(call.argument<String>("mime") ?: "image/png") else "application/json";startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).setType(mime).addCategory(Intent.CATEGORY_OPENABLE).putExtra(Intent.EXTRA_TITLE,safe(checkNotNull(call.argument<String>("name")))),105)}
      "shareImage","copyImage"->{val mime=call.argument<String>("mime") ?: "image/png";require(mime in listOf("image/png","image/jpeg"));val extension=if(mime=="image/jpeg")"jpg" else "png";val bytes=checkNotNull(call.argument<ByteArray>("bytes"));val displayName=call.argument<String>("name") ?: "MusicCardX.$extension";io.execute {val created=runCatching {val root=File(cacheDir,"images").apply{mkdirs()};val digest=java.security.MessageDigest.getInstance("SHA-256").digest(bytes).joinToString(""){"%02x".format(it.toInt() and 255)};val file=File(root,"MusicCardX-$digest.$extension");if(!file.exists()){val temporary=File(root,file.name+".tmp");try {temporary.outputStream().use { stream ->
          var offset=0
          while(offset<bytes.size){val count=minOf(256*1024,bytes.size-offset);stream.write(bytes,offset,count);offset+=count;val progress=offset.toDouble()/bytes.size;runOnUiThread {channel?.invokeMethod("exportProgress",progress)}}
        };check(temporary.renameTo(file)){"图片缓存写入失败"}} finally {temporary.delete()}};file.setLastModified(System.currentTimeMillis());maintainStorage();Uri.parse("content://$packageName.images/${file.name}").buildUpon().appendQueryParameter("name",displayName).build()};runOnUiThread {created.fold({uri->try {if(call.method=="copyImage"){getPreferences(Context.MODE_PRIVATE).edit().putString("clipboardImage",uri.lastPathSegment).apply();(getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newUri(contentResolver,"MusicCardX",uri));result.success("图片已复制；部分应用仅支持通过分享接收图片")}else{startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM,uri).apply { clipData=ClipData.newRawUri("MusicCardX",uri) }.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),"分享卡片"));result.success(null)}}catch(e:Exception){result.error("MCX_SHARE",e.message,null)}},{result.error("MCX_SHARE",it.message,null)})}}}
      "listPresets"->work(result){presets.listFiles()?.filter {it.extension=="json"}?.map { it.nameWithoutExtension }?.sorted()?:emptyList<String>()}
      "savePreset"->work(result){val target=File(presets,safe(checkNotNull(call.argument<String>("name")))+".json");require(!target.exists()){ "同名配置已存在，请换一个名称" };target.writeText(checkNotNull(call.argument<String>("json")));null}
      "loadPreset"->work(result){File(presets,safe(checkNotNull(call.argument<String>("name")))+".json").readText()}
      "renamePreset"->work(result){val source=File(presets,safe(checkNotNull(call.argument<String>("name")))+".json");val target=File(presets,safe(checkNotNull(call.argument<String>("newName")))+".json");require(source.exists()){"配置不存在"};require(!target.exists()){"同名配置已存在"};check(source.renameTo(target)){"配置重命名失败"};null}
      "deletePreset"->work(result){File(presets,safe(checkNotNull(call.argument<String>("name")))+".json").delete();null}
      else->result.notImplemented()
    }}catch(e:Exception){pending=null;output=null;result.error("MCX",e.message,null)}
  }
  @Deprecated("Permission API") override fun onRequestPermissionsResult(request:Int,permissions:Array<out String>,grants:IntArray){super.onRequestPermissionsResult(request,permissions,grants);if(request==109){storageResult?.success(storageAllowed());storageResult=null}}
  private fun begin(result:MethodChannel.Result){check(pending==null){"另一个文件操作正在进行"};pending=result}
  private fun safe(name:String)=name.replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"),"_").trim().take(120).ifBlank { "MusicCardX" }
  @Deprecated("Activity result API") override fun onActivityResult(request:Int,status:Int,data:Intent?){super.onActivityResult(request,status,data);if(request==108){storageResult?.success(storageAllowed());storageResult=null;return};if(request !in 103..107)return;val result=pending?:return;pending=null
    if(status!=Activity.RESULT_OK){output=null;result.success(null);return}
    if(request==106){val uris=mutableListOf<Uri>();data?.data?.let {uris.add(it)};data?.clipData?.let { clip->repeat(clip.itemCount){uris.add(clip.getItemAt(it).uri)} };work(result){uris.distinct().map { uri->var name="font";contentResolver.query(uri,arrayOf(OpenableColumns.DISPLAY_NAME),null,null,null)?.use {if(it.moveToFirst())name=it.getString(0)};val root=File(cacheDir,"font-import").apply{mkdirs()};val f=File(root,"${java.util.UUID.randomUUID()}");contentResolver.openInputStream(uri)!!.use {input->f.outputStream().use {out->val buffer=ByteArray(65536);var count=0L;while(true){val n=input.read(buffer);if(n<0)break;count+=n;require(count<=268435456);out.write(buffer,0,n)}} };mapOf("path" to f.path,"name" to name)}};return}
    if(request==107){val uri=data?.data;if(uri==null){result.success(null);return};try{contentResolver.takePersistableUriPermission(uri,Intent.FLAG_GRANT_READ_URI_PERMISSION);result.success(uri.toString())}catch(e:Exception){result.error("MCX_SAF",e.message,null)};return}
    val uri=data?.data;if(uri==null){output=null;result.error("MCX_URI","文件选择器未返回文件",null);return}
    val bytes=output;output=null
    work(result){when(request){
      103->{val root=File(filesDir,"covers").apply{mkdirs()};val file=File(root,"${System.currentTimeMillis()}.image");checkNotNull(contentResolver.openInputStream(uri)).use { input->file.outputStream().use { out->val buffer=ByteArray(65536);var total=0L;while(true){val n=input.read(buffer);if(n<0)break;total+=n;require(total<=64*1024*1024){"封面文件超过 64 MB"};out.write(buffer,0,n)}} };file.absolutePath}
      104->checkNotNull(contentResolver.openInputStream(uri)).use { input->val text=input.readBytes();require(text.size<=8*1024*1024){"配置文件过大"};if(text.size>=2&&text[0]==(-1).toByte()&&text[1]==(-2).toByte())text.toString(Charsets.UTF_16)else text.toString(Charsets.UTF_8).removePrefix("\uFEFF")}
      105->{checkNotNull(contentResolver.openOutputStream(uri,"wt")).use { it.write(checkNotNull(bytes)) };"已保存"}
      else->null
    }}
  }
}
