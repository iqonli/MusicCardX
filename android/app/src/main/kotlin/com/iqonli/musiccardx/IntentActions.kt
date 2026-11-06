package com.iqonli.musiccardx

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings

/** Platform adapter only: configuration and UI live in Flutter. */
object IntentActions {
  fun handle(activity: Activity, method: String, args: Map<*, *>): Any? {
    val pm = activity.packageManager
    return when(method) {
      "textActions" -> {
        @Suppress("DEPRECATION")
        val entries = pm.queryIntentActivities(Intent(Intent.ACTION_PROCESS_TEXT).setType("text/plain"), 0)
        entries.filter { it.activityInfo.exported && it.activityInfo.enabled &&
          (it.activityInfo.permission == null || activity.checkSelfPermission(it.activityInfo.permission) == PackageManager.PERMISSION_GRANTED) }
          .map { mapOf("name" to it.loadLabel(pm).toString(), "component" to ComponentName(it.activityInfo.packageName,it.activityInfo.name).flattenToString()) }
          .sortedBy { it["name"] }
      }
      "actionPermissions" -> {
        val missing = mutableListOf<String>()
        if (android.os.Build.VERSION.SDK_INT >= 30 && activity.checkSelfPermission("android.permission.QUERY_ALL_PACKAGES") != PackageManager.PERMISSION_GRANTED) missing.add("读取应用列表")
        // MIUI's app-list AppOp is vendor-specific. Unknown operations are ignored.
        if (android.os.Build.MANUFACTURER.equals("Xiaomi", true)) {
          val denied = runCatching {
            val manager = activity.getSystemService(android.content.Context.APP_OPS_SERVICE) as android.app.AppOpsManager
            val mode = manager.checkOpNoThrow("android:get_installed_apps", android.os.Process.myUid(), activity.packageName)
            mode == android.app.AppOpsManager.MODE_IGNORED || mode == android.app.AppOpsManager.MODE_ERRORED
          }.getOrDefault(false)
          if (denied && !missing.contains("读取应用列表")) missing.add("读取应用列表")
        }
        missing
      }
      "actionPermissionSettings" -> {
        activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:"+activity.packageName))); null
      }
      "launchAction" -> {
        val component = ComponentName.unflattenFromString(args["component"] as? String ?: "") ?: throw IllegalArgumentException("目标Activity格式应为包名/完整类名")
        val intent = Intent((args["action"] as? String).orEmpty()).setComponent(component)
        val mime = (args["mime"] as? String).orEmpty()
        if(mime.isNotBlank()) intent.type = mime
        val extras = args["extras"] as? List<*> ?: emptyList<Any>()
        for(raw in extras) {
          val e = raw as Map<*, *>; val key=e["key"] as String; val v=e["value"] as String
          when(e["type"]) {
            "charSequence" -> intent.putExtra(key,v as CharSequence)
            "boolean" -> { require(v == "true" || v == "false") { "布尔值应为true或false" };intent.putExtra(key,v.toBoolean()) }
            "int" -> intent.putExtra(key,v.toInt())
            "long" -> intent.putExtra(key,v.toLong())
            "double" -> intent.putExtra(key,v.toDouble())
            else -> intent.putExtra(key,v)
          }
        }
        activity.startActivity(intent); null
      }
      else -> throw IllegalArgumentException("未知Intent操作")
    }
  }
}
