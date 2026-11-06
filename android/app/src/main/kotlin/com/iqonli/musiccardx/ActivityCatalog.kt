package com.iqonli.musiccardx

import android.content.Context
import android.content.ComponentName
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import java.io.ByteArrayOutputStream

/** Independently implemented PackageManager adapter; no third-party launcher code. */
object ActivityCatalog {
  val loaded = java.util.concurrent.atomic.AtomicInteger(0)
  val total = java.util.concurrent.atomic.AtomicInteger(0)
  @Suppress("DEPRECATION")
  fun read(context: Context, method: String, args: Map<*, *>): Any {
    val pm = context.packageManager
    fun activities(pkg: String): List<Map<String, Any>> {
      val info = pm.getPackageInfo(pkg, PackageManager.GET_ACTIVITIES or PackageManager.MATCH_DISABLED_COMPONENTS or PackageManager.MATCH_DIRECT_BOOT_AWARE or PackageManager.MATCH_DIRECT_BOOT_UNAWARE)
      return (info.activities ?: emptyArray()).map { a ->
        val permission = a.permission
        mapOf("name" to a.loadLabel(pm).toString(), "className" to a.name,
          "component" to ComponentName(pkg, a.name).flattenToString(), "enabled" to (a.enabled && info.applicationInfo?.enabled != false),
          "exported" to a.exported, "permission" to (permission ?: ""),
          "callable" to (a.enabled && info.applicationInfo?.enabled != false && a.exported && (permission == null || context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED)))
      }.sortedBy { it["className"].toString() }
    }
    return when(method) {
      "catalogLoad" -> {
        loaded.set(0);total.set(0)
        val packages = pm.getInstalledPackages(PackageManager.GET_ACTIVITIES or PackageManager.MATCH_DISABLED_COMPONENTS or PackageManager.MATCH_DIRECT_BOOT_AWARE or PackageManager.MATCH_DIRECT_BOOT_UNAWARE)
        total.set(packages.sumOf { it.activities?.size ?: 0 })
        packages.map { info ->
          val list = runCatching { activities(info.packageName) }.getOrDefault(emptyList())
          loaded.addAndGet(info.activities?.size ?: 0)
          mapOf("name" to (info.applicationInfo?.loadLabel(pm)?.toString() ?: info.packageName), "package" to info.packageName, "activities" to list)
        }.sortedBy { it["name"].toString().lowercase() }
      }
      "catalogApps" -> pm.getInstalledApplications(PackageManager.MATCH_DISABLED_COMPONENTS).map { a ->
        mapOf("name" to a.loadLabel(pm).toString(), "package" to a.packageName, "enabled" to a.enabled)
      }.sortedBy { it["name"].toString().lowercase() }
      "catalogActivities" -> activities(args["package"] as String)
      "catalogSearch" -> {
        val query = (args["query"] as String).lowercase()
        pm.getInstalledApplications(PackageManager.MATCH_DISABLED_COMPONENTS).mapNotNull { app ->
          val label = app.loadLabel(pm).toString()
          val rows = runCatching { activities(app.packageName) }.getOrDefault(emptyList())
          val matches = if(label.lowercase().contains(query) || app.packageName.lowercase().contains(query)) rows else rows.filter { it["name"].toString().lowercase().contains(query) || it["className"].toString().lowercase().contains(query) }
          if(matches.isEmpty()) null else mapOf("name" to label,"package" to app.packageName,"activities" to matches)
        }.sortedBy { it["name"].toString().lowercase() }
      }
      "catalogIcon" -> {
        val drawable = pm.getApplicationIcon(args["package"] as String)
        val bitmap = Bitmap.createBitmap(64,64,Bitmap.Config.ARGB_8888)
        drawable.setBounds(0,0,64,64);drawable.draw(Canvas(bitmap))
        val bytes = ByteArrayOutputStream();bitmap.compress(Bitmap.CompressFormat.PNG,100,bytes);bitmap.recycle();bytes.toByteArray()
      }
      else -> throw IllegalArgumentException("未知列表操作")
    }
  }
}
