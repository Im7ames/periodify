package com.im7ames.periodify

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File

class UpdateFileProvider : FileProvider()

object UpdateInstaller {
    fun offer(activity: Activity, file: File): Boolean {
        val root = File(activity.cacheDir, "periodify-updates").canonicalFile
        val update = file.canonicalFile
        require(update.toPath().startsWith(root.toPath()) && update.isFile)
        @Suppress("DEPRECATION")
        val packageInfo = activity.packageManager.getPackageArchiveInfo(update.path, 0)
        require(packageInfo?.packageName == activity.packageName)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !activity.packageManager.canRequestPackageInstalls()) {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}")))
            return false
        }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", update)
        activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
        return true
    }
}
