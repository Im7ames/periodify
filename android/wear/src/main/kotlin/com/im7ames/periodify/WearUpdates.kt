package com.im7ames.periodify

import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.security.MessageDigest

data class WearUpdate(val version: String, val url: String, val size: Long, val digest: String)

object WearUpdates {
    private const val releases = "https://github.com/Im7ames/periodify/releases/download"
    private const val api = "https://api.github.com/repos/Im7ames/periodify/releases?per_page=12"
    private val versionPattern = Regex("^[0-9]+\\.[0-9]+\\.[0-9]+$")

    fun check(installed: String): WearUpdate? {
        if (!versionPattern.matches(installed)) return null
        val feed = JSONArray(readText(api))
        val versions = mutableListOf<String>()
        for (index in 0 until feed.length()) {
            val release = feed.getJSONObject(index)
            val tag = release.optString("tag_name")
            if (!tag.startsWith('v') || release.optBoolean("draft")) continue
            val version = tag.substring(1)
            if (!versionPattern.matches(version) || compareVersions(version, installed) <= 0) continue
            val assets = release.optJSONArray("assets") ?: continue
            if ((0 until assets.length()).any { assets.getJSONObject(it).optString("name") == "updates.json" }) {
                versions.add(version)
            }
        }
        for (version in versions.sortedWith { a, b -> compareVersions(b, a) }) {
            val manifest = JSONObject(readText("$releases/v$version/updates.json"))
            if (manifest.optInt("schema") != 1 || manifest.optString("version") != version) continue
            val assets = manifest.getJSONArray("assets")
            for (index in 0 until assets.length()) {
                val asset = assets.getJSONObject(index)
                if (asset.optString("name") != "periodify-wear-os.apk") continue
                val url = "$releases/v$version/periodify-wear-os.apk"
                val size = asset.optLong("size")
                val digest = asset.optString("sha256")
                if (asset.optString("url") == url && size in 1..30_000_000 && Regex("^[0-9a-f]{64}$").matches(digest)) {
                    return WearUpdate(version, url, size, digest)
                }
            }
        }
        return null
    }

    fun download(update: WearUpdate, cache: File): File {
        val root = File(cache, "periodify-updates").apply { mkdirs() }
        val file = File.createTempFile("periodify-wear-", ".apk", root)
        val connection = connect(update.url)
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            var downloaded = 0L
            connection.inputStream.use { input ->
                file.outputStream().use { output ->
                    val buffer = ByteArray(16 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        downloaded += count
                        check(downloaded <= update.size)
                        output.write(buffer, 0, count)
                        digest.update(buffer, 0, count)
                    }
                }
            }
            check(downloaded == update.size && digest.digest().joinToString("") { "%02x".format(it) } == update.digest)
            return file
        } catch (error: Exception) {
            file.delete()
            throw error
        } finally {
            connection.disconnect()
        }
    }

    private fun readText(url: String): String {
        val connection = connect(url)
        try {
            return connection.inputStream.use {
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = it.read(buffer)
                    if (count < 0) break
                    check(output.size() + count <= 1_500_000)
                    output.write(buffer, 0, count)
                }
                output.toString(Charsets.UTF_8.name())
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun connect(url: String) = (URI(url).toURL().openConnection() as HttpURLConnection).apply {
        connectTimeout = 12_000
        readTimeout = 20_000
    }

    private fun compareVersions(a: String, b: String): Int {
        val first = a.split('.').map(String::toInt)
        val second = b.split('.').map(String::toInt)
        for (index in 0..2) {
            val comparison = first[index].compareTo(second[index])
            if (comparison != 0) return comparison
        }
        return 0
    }
}
