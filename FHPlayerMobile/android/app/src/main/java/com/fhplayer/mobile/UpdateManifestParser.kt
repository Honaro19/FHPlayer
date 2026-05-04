package com.fhplayer.mobile

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.time.Instant
import java.util.Locale

internal object UpdateManifestParser {
    private val versionPattern = Regex("""^v?(\d+)\.(\d+)\.(\d+)$""")

    fun normalizeOptionalString(value: Any?): String {
        val normalized = value?.toString()?.trim().orEmpty()
        return if (normalized.isEmpty() || normalized.equals("null", ignoreCase = true) || normalized.equals("none", ignoreCase = true)) {
            ""
        } else {
            normalized
        }
    }

    fun parseReleasePayload(payload: JSONObject, platform: String, currentVersion: String, checkedAt: String = Instant.now().toString()): JSONObject {
        if (!isGitHubReleasePayload(payload)) {
            requireManifestSchemaVersion(payload)
        }
        val normalizedPlatform = normalizeUpdatePlatform(platform)
        val platformPayload = extractPlatformPayload(payload, normalizedPlatform)
        val latestVersionRaw =
            firstNonBlankValue(
                getStringValue(platformPayload, "latest_version", "latestVersion", "version", "tag_name", "name"),
                getStringValue(payload, "latest_version", "latestVersion", "version", "tag_name", "name"),
            )
        val latestVersionParts =
            parseVersionParts(latestVersionRaw)
                ?: throw IllegalArgumentException("Update feed did not provide a valid semantic version")
        val currentVersionParts = parseVersionParts(currentVersion) ?: listOf(0, 0, 0)
        val normalizedLatestVersion = latestVersionParts.joinToString(".")
        val updateAvailable = isVersionNewer(latestVersionParts, currentVersionParts)
        val preferredDownloadKeys =
            if (normalizedPlatform == "android") {
                arrayOf("apk_url", "apkUrl", "aab_url", "aabUrl", "download_url", "downloadUrl")
            } else {
                arrayOf("installer_url", "installerUrl", "portable_url", "portableUrl", "download_url", "downloadUrl")
            }
        var downloadUrl =
            firstNonBlankValue(
                getStringValue(platformPayload, *preferredDownloadKeys),
                getStringValue(payload, *preferredDownloadKeys),
            )
        var assetName = assetNameFromUrl(downloadUrl)
        if (downloadUrl.isBlank()) {
            val asset = selectReleaseAsset(platformPayload.optJSONArray("assets"), normalizedPlatform)
            downloadUrl = asset.first
            assetName = asset.second
        }
        if (downloadUrl.isBlank()) {
            val asset = selectReleaseAsset(payload.optJSONArray("assets"), normalizedPlatform)
            downloadUrl = asset.first
            assetName = asset.second
        }
        val releaseUrl =
            firstNonBlankValue(
                getStringValue(platformPayload, "folder_url", "folderUrl", "release_url", "releaseUrl", "html_url", "url"),
                getStringValue(payload, "folder_url", "folderUrl", "release_url", "releaseUrl", "html_url", "url"),
            )

        return JSONObject()
            .put("status", if (updateAvailable) "available" else "current")
            .put("checkedAt", checkedAt)
            .put("currentVersion", currentVersion)
            .put("latestVersion", normalizedLatestVersion)
            .put("updateAvailable", updateAvailable)
            .put("releaseUrl", releaseUrl)
            .put("downloadUrl", downloadUrl)
            .put("assetName", assetName)
            .put(
                "publishedAt",
                firstNonBlankValue(
                    getStringValue(platformPayload, "published_at", "publishedAt", "created_at", "createdAt"),
                    getStringValue(payload, "published_at", "publishedAt", "created_at", "createdAt"),
                ),
            )
            .put(
                "message",
                if (updateAvailable) {
                    "Version $normalizedLatestVersion is available."
                } else {
                    "You are already on the latest version ($currentVersion)."
                },
            )
    }

    private fun requireManifestSchemaVersion(payload: JSONObject) {
        val schemaVersionValue = payload.opt("schema_version")
        val schemaVersion =
            when (schemaVersionValue) {
                null, JSONObject.NULL -> null
                is Number -> schemaVersionValue.toInt()
                is String -> schemaVersionValue.trim().toIntOrNull()
                is Boolean -> null
                else -> schemaVersionValue.toString().trim().toIntOrNull()
            }
        require(schemaVersion == 1) { "Update manifest schema_version must be 1" }
    }

    private fun isGitHubReleasePayload(payload: JSONObject): Boolean {
        val htmlUrl = getStringValue(payload, "html_url")
        val tagName = getStringValue(payload, "tag_name")
        val uri = runCatching { URI(htmlUrl) }.getOrNull()
        val host = uri?.host?.lowercase(Locale.US).orEmpty()
        return uri?.scheme == "https" &&
            host == "github.com" &&
            uri.path.orEmpty().contains("/releases/tag/") &&
            tagName.isNotBlank()
    }

    private fun parseVersionParts(version: String): List<Int>? {
        val match = versionPattern.matchEntire(version.trim()) ?: return null
        return match.destructured.toList().map { it.toInt() }
    }

    private fun isVersionNewer(candidateVersion: List<Int>, currentVersion: List<Int>): Boolean {
        val maxLength = maxOf(candidateVersion.size, currentVersion.size)
        for (index in 0 until maxLength) {
            val candidatePart = candidateVersion.getOrElse(index) { 0 }
            val currentPart = currentVersion.getOrElse(index) { 0 }
            if (candidatePart != currentPart) {
                return candidatePart > currentPart
            }
        }
        return false
    }

    private fun normalizeUpdatePlatform(platform: String): String =
        when (platform.trim().lowercase(Locale.US)) {
            "android" -> "android"
            else -> "windows"
        }

    private fun extractPlatformPayload(payload: JSONObject, platform: String): JSONObject {
        payload.optJSONObject("platforms")?.optJSONObject(platform)?.let { return it }
        payload.optJSONObject(platform)?.let { return it }
        return JSONObject()
    }

    private fun getStringValue(payload: JSONObject?, vararg keys: String): String {
        if (payload == null) {
            return ""
        }

        keys.forEach { key ->
            val value = normalizeOptionalString(payload.opt(key))
            if (value.isNotEmpty()) {
                return value
            }
        }
        return ""
    }

    private fun firstNonBlankValue(vararg values: String?): String {
        values.forEach { value ->
            val normalized = normalizeOptionalString(value)
            if (normalized.isNotEmpty()) {
                return normalized
            }
        }
        return ""
    }

    private fun assetNameFromUrl(url: String): String {
        val path = URI(url).path.orEmpty().trimEnd('/')
        if (path.isBlank()) {
            return ""
        }
        return path.substringAfterLast('/')
    }

    private fun selectReleaseAsset(assets: JSONArray?, platform: String): Pair<String, String> {
        if (assets == null) {
            return "" to ""
        }

        val preferredSuffixes = if (normalizeUpdatePlatform(platform) == "android") listOf(".apk", ".aab") else listOf(".exe", ".zip")
        val normalizedAssets =
            buildList {
                for (index in 0 until assets.length()) {
                    val asset = assets.optJSONObject(index) ?: continue
                    val downloadUrl =
                        firstNonBlankValue(
                            normalizeOptionalString(asset.opt("browser_download_url")),
                            normalizeOptionalString(asset.opt("downloadUrl")),
                            normalizeOptionalString(asset.opt("download_url")),
                            normalizeOptionalString(asset.opt("url")),
                        )
                    add(downloadUrl to normalizeOptionalString(asset.opt("name")))
                }
            }

        preferredSuffixes.forEach { suffix ->
            normalizedAssets.firstOrNull { (_, name) -> name.lowercase(Locale.US).endsWith(suffix) }?.let { (url, name) ->
                if (url.isNotBlank()) {
                    return url to name
                }
            }
        }

        return "" to ""
    }
}
