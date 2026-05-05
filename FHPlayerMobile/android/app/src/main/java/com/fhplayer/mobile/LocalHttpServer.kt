package com.fhplayer.mobile

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.File
import java.io.FileNotFoundException
import java.io.FileInputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.URL
import java.security.cert.CertificateException
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

class LocalHttpServer(
    private val context: Context,
    private val host: String = HOST,
    private val port: Int = PORT,
) {
    @Volatile
    private var running = false

    private var serverSocket: ServerSocket? = null
    private var acceptThread: Thread? = null
    private val clientExecutor: ExecutorService = Executors.newCachedThreadPool()
    private val selectedDocumentsByKind = mutableMapOf<String, List<SelectedDocument>>()
    private val selectedDocumentsByToken = mutableMapOf<String, SelectedDocument>()

    @Synchronized
    @Throws(IOException::class)
    fun start() {
        if (running) {
            return
        }

        val socket = ServerSocket()
        socket.reuseAddress = true
        socket.bind(InetSocketAddress(InetAddress.getByName(host), port))
        socket.soTimeout = 1000

        serverSocket = socket
        running = true
        acceptThread = Thread(::acceptLoop, "fhplayer-http-accept").apply {
            isDaemon = true
            start()
        }
        AppLogger.info(context, "Embedded HTTP server started at ${baseUrl()}.")
    }

    @Synchronized
    fun stop() {
        running = false
        try {
            serverSocket?.close()
        } catch (_: IOException) {
        }
        serverSocket = null
        acceptThread = null
        clientExecutor.shutdownNow()
        AppLogger.info(context, "Embedded HTTP server stopped.")
    }

    fun isRunning(): Boolean = running

    fun ensureLibraryDirectories() {
        resolveLibraryDirectory("videos")
        resolveLibraryDirectory("funscripts")
        resolveLibraryDirectory("exports")
    }

    @Synchronized
    private fun loadSettings(): JSONObject {
        val settingsFile = settingsFile()
        if (!settingsFile.exists()) {
            return normalizeSettings(null)
        }

        return try {
            normalizeSettings(JSONObject(settingsFile.readText(Charsets.UTF_8)))
        } catch (_: Exception) {
            normalizeSettings(null)
        }
    }

    @Synchronized
    private fun saveSettings(settings: JSONObject): JSONObject {
        val normalizedSettings = normalizeSettings(settings)
        val settingsFile = settingsFile()
        settingsFile.parentFile?.mkdirs()
        settingsFile.writeText("${normalizedSettings.toString(2)}\n", Charsets.UTF_8)
        return normalizedSettings
    }

    private fun normalizeSettings(payload: JSONObject?): JSONObject {
        val updates = payload?.optJSONObject("updates") ?: JSONObject()
        val ui = payload?.optJSONObject("ui") ?: JSONObject()
        val legal = payload?.optJSONObject("legal") ?: JSONObject()
        val normalizedUpdates =
            JSONObject()
                .put("autoCheckEnabled", updates.optBoolean("autoCheckEnabled", false))
                .put(
                    "manualDisclosureAcknowledgedVersion",
                    UpdateManifestParser.normalizeOptionalString(updates.opt("manualDisclosureAcknowledgedVersion")),
                )
                .put(
                    "releaseDisclosureSuppressedVersion",
                    UpdateManifestParser.normalizeOptionalString(updates.opt("releaseDisclosureSuppressedVersion")),
                )
        normalizeUpdateResult(updates.opt("lastResult"))?.let { normalizedUpdates.put("lastResult", it) }
        val normalizedUi =
            JSONObject()
                .put("showDiagnostics", ui.optBoolean("showDiagnostics", true))
                .put("showFunscriptOverview", ui.optBoolean("showFunscriptOverview", true))
                .put("showExecutionLog", ui.optBoolean("showExecutionLog", true))
                .put("showUpdates", ui.optBoolean("showUpdates", true))
        val normalizedLegal =
            JSONObject()
                .put(
                    "lastAcknowledgedVersion",
                    UpdateManifestParser.normalizeOptionalString(legal.opt("lastAcknowledgedVersion")),
                )
        return JSONObject()
            .put("updates", normalizedUpdates)
            .put("ui", normalizedUi)
            .put("legal", normalizedLegal)
    }

    private fun normalizeUpdateResult(value: Any?): JSONObject? {
        val updateResult = value as? JSONObject ?: return null
        val sourceUrl = UpdateManifestParser.normalizeOptionalString(updateResult.opt("sourceUrl"))
        if (sourceUrl != UPDATE_FEED_URL) {
            return null
        }

        return JSONObject()
            .put("status", UpdateManifestParser.normalizeOptionalString(updateResult.opt("status")).ifBlank { "unknown" })
            .put("checkedAt", UpdateManifestParser.normalizeOptionalString(updateResult.opt("checkedAt")))
            .put("currentVersion", UpdateManifestParser.normalizeOptionalString(updateResult.opt("currentVersion")).ifBlank { BuildConfig.VERSION_NAME })
            .put("latestVersion", UpdateManifestParser.normalizeOptionalString(updateResult.opt("latestVersion")))
            .put("updateAvailable", updateResult.optBoolean("updateAvailable", false))
            .put("releaseUrl", UpdateManifestParser.normalizeOptionalString(updateResult.opt("releaseUrl")))
            .put("downloadUrl", UpdateManifestParser.normalizeOptionalString(updateResult.opt("downloadUrl")))
            .put("assetName", UpdateManifestParser.normalizeOptionalString(updateResult.opt("assetName")))
            .put("publishedAt", UpdateManifestParser.normalizeOptionalString(updateResult.opt("publishedAt")))
            .put("message", UpdateManifestParser.normalizeOptionalString(updateResult.opt("message")))
            .put("sourceUrl", sourceUrl)
    }

    private fun buildSettingsPayload(): JSONObject =
        JSONObject()
            .put("ok", true)
            .put("currentVersion", BuildConfig.VERSION_NAME)
            .put("settings", loadSettings())
            .put(
                "updateSupport",
                JSONObject()
                    .put("configured", UPDATE_FEED_URL.isNotBlank())
                    .put("sourceUrl", UPDATE_FEED_URL)
                    .put("releaseUrl", RELEASE_PAGE_URL),
            )

    private fun settingsFile(): File = File(context.filesDir, "fhplayer-settings.json")

    @Synchronized
    fun recordDocumentSelection(kind: String, uris: Array<out Uri>) {
        val normalizedKind = kind.trim().lowercase(Locale.US).ifBlank { "files" }
        val previousDocuments = selectedDocumentsByKind.remove(normalizedKind).orEmpty()
        previousDocuments.forEach { document -> selectedDocumentsByToken.remove(document.token) }

        val nextDocuments =
            uris.map { uri ->
                val metadata = resolveDocumentMetadata(uri)
                SelectedDocument(
                    token = UUID.randomUUID().toString(),
                    uri = uri,
                    kind = normalizedKind,
                    displayName = metadata.displayName,
                    mimeType = metadata.mimeType,
                    sizeBytes = metadata.sizeBytes,
                )
            }

        selectedDocumentsByKind[normalizedKind] = nextDocuments
        nextDocuments.forEach { document -> selectedDocumentsByToken[document.token] = document }
    }

    private fun acceptLoop() {
        while (running) {
            try {
                val client = serverSocket?.accept() ?: break
                clientExecutor.execute { handleClient(client) }
            } catch (_: SocketTimeoutException) {
            } catch (exception: IOException) {
                if (running) {
                    AppLogger.error(context, "Could not accept HTTP client.", exception)
                }
            }
        }
    }

    private fun handleClient(socket: Socket) {
        try {
            socket.use { client ->
                client.soTimeout = 10000
                client.tcpNoDelay = true
                val input = BufferedInputStream(client.getInputStream())
                val output = client.getOutputStream()
                try {
                    val request = parseRequest(input) ?: return@use
                    routeRequest(request, output)
                } catch (exception: Exception) {
                    if (isClientDisconnect(exception)) {
                        logClientDisconnect(exception)
                    } else {
                        AppLogger.error(context, "Unhandled HTTP request failure.", exception)
                        try {
                            respondJson(
                                output,
                                HTTP_INTERNAL_SERVER_ERROR,
                                JSONObject()
                                    .put("ok", false)
                                    .put("error", exception.message ?: "Internal server error"),
                            )
                        } catch (responseException: Exception) {
                            if (isClientDisconnect(responseException)) {
                                logClientDisconnect(responseException)
                            } else {
                                AppLogger.error(context, "Could not write HTTP error response.", responseException)
                            }
                        }
                    }
                } finally {
                    try {
                        output.flush()
                    } catch (flushException: Exception) {
                        if (isClientDisconnect(flushException)) {
                            logClientDisconnect(flushException)
                        } else {
                            AppLogger.error(context, "Could not flush HTTP response.", flushException)
                        }
                    }
                }
            }
        } catch (exception: Exception) {
            if (isClientDisconnect(exception)) {
                logClientDisconnect(exception)
            } else {
                AppLogger.error(context, "Could not handle HTTP client.", exception)
            }
        }
    }

    private fun isClientDisconnect(exception: Throwable): Boolean {
        if (exception is EOFException || exception is SocketException) {
            return true
        }
        val normalizedMessage = exception.message?.lowercase(Locale.US).orEmpty()
        if (
            normalizedMessage.contains("broken pipe") ||
            normalizedMessage.contains("connection reset") ||
            normalizedMessage.contains("socket closed")
        ) {
            return true
        }
        return exception.cause?.let { cause -> isClientDisconnect(cause) } ?: false
    }

    private fun logClientDisconnect(exception: Throwable) {
        val detail = exception.message ?: exception.javaClass.simpleName
        AppLogger.info(context, "HTTP client disconnected before the response finished: $detail.")
    }

    private fun routeRequest(request: HttpRequest, output: OutputStream) {
        val path = request.path.substringBefore("?")
        val requestUri = Uri.parse("http://$host:$port${request.path}")
        when {
            (request.method == "GET" || request.method == "POST") && path == "/api/health" -> {
                respondJson(
                    output,
                    HTTP_OK,
                    JSONObject()
                        .put("ok", true)
                        .put("port", port)
                        .put("version", BuildConfig.VERSION_NAME)
                        .put("platform", "android")
                        .put(
                            "capabilities",
                            JSONObject()
                                .put("execute", false)
                                .put("lovense", true)
                                .put("updates", true)
                                .put("diagnostics", true),
                        ),
                )
            }

            request.method == "GET" && path == "/api/library/info" -> {
                respondJson(output, HTTP_OK, buildLibraryPayload())
            }

            request.method == "GET" && path == "/api/library/list" -> {
                handleLibraryList(requestUri, output)
            }

            (request.method == "GET" || request.method == "HEAD") && path == "/api/library/file" -> {
                handleLibraryFile(requestUri, request, output)
            }

            request.method == "GET" && path == "/api/settings" -> {
                respondJson(output, HTTP_OK, buildSettingsPayload())
            }

            request.method == "GET" && path == "/api/diagnostics/info" -> {
                respondJson(output, HTTP_OK, buildDiagnosticsPayload())
            }

            request.method == "GET" && path == "/api/android/document-selection" -> {
                handleDocumentSelection(requestUri, output)
            }

            (request.method == "GET" || request.method == "HEAD") && path == "/api/android/document-file" -> {
                handleDocumentFile(requestUri, request, output)
            }

            request.method == "POST" && (path == "/api/lovense/detect" || path == "/api/lovense-detect") -> {
                handleLovenseDetect(request, output)
            }

            request.method == "POST" && (path == "/api/lovense/command" || path == "/api/lovense-command") -> {
                handleLovenseCommand(request, output)
            }

            request.method == "PUT" && path == "/api/library/import" -> {
                handleLibraryImport(requestUri, request, output)
            }

            request.method == "DELETE" && path == "/api/library/file" -> {
                handleLibraryDelete(requestUri, output)
            }

            request.method == "POST" && path == "/api/android/import-document" -> {
                handleAndroidDocumentImport(requestUri, output)
            }

            request.method == "PUT" && path == "/api/android/document-write" -> {
                handleDocumentWrite(requestUri, request, output)
            }

            request.method == "POST" && path == "/api/settings" -> {
                handleSettingsUpdate(request, output)
            }

            request.method == "POST" && path == "/api/android/clipboard" -> {
                handleClipboardWrite(request, output)
            }

            request.method == "POST" && path == "/api/update/check" -> {
                handleUpdateCheck(output)
            }

            request.method == "POST" && path == "/api/diagnostics/open" -> {
                respondJson(
                    output,
                    HTTP_NOT_IMPLEMENTED,
                    JSONObject()
                        .put("ok", false)
                        .put("error", "Opening the diagnostics folder directly is not available in the Android app build."),
                )
            }

            request.method == "POST" && path == "/api/library/open" -> {
                respondJson(
                    output,
                    HTTP_NOT_IMPLEMENTED,
                    JSONObject()
                        .put("ok", false)
                        .put("error", "Opening folders directly is not available in the Android app build."),
                )
            }

            request.method == "GET" -> {
                handleStaticAsset(path, output)
            }

            else -> {
                respondJson(
                    output,
                    HTTP_NOT_FOUND,
                    JSONObject()
                        .put("ok", false)
                        .put("error", "Unknown route"),
                )
            }
        }
    }

    private fun handleStaticAsset(path: String, output: OutputStream) {
        val normalizedPath = when (path) {
            "", "/" -> "www/index.html"
            else -> {
                val requestedPath = path.removePrefix("/")
                if (requestedPath.contains("..")) {
                    respondJson(
                        output,
                        HTTP_BAD_REQUEST,
                        JSONObject()
                            .put("ok", false)
                            .put("error", "Invalid asset path"),
                    )
                    return
                }
                "www/$requestedPath"
            }
        }

        try {
            context.assets.open(normalizedPath).use { input ->
                respondBytes(output, HTTP_OK, guessContentType(normalizedPath), input.readBytes())
            }
        } catch (_: FileNotFoundException) {
            respondJson(
                output,
                HTTP_NOT_FOUND,
                JSONObject()
                    .put("ok", false)
                    .put("error", "Asset not found"),
            )
        }
    }

    private fun handleLovenseDetect(request: HttpRequest, output: OutputStream) {
        try {
            val payload = parseJsonObject(request.body)
            val config = payload.optJSONObject("config") ?: JSONObject()
            val timeoutMs = payload.optDouble("timeoutSeconds", 5.0).coerceIn(0.1, 60.0).times(1000).toInt()
            val (result, resolvedEndpoint) = lovenseRequest(config, JSONObject().put("command", "GetToys"), timeoutMs)
            respondJson(
                output,
                HTTP_OK,
                JSONObject()
                    .put("ok", true)
                    .put("result", result)
                    .put("resolvedEndpoint", resolvedEndpoint)
                    .put("normalized", normalizeLovenseToys(result)),
            )
        } catch (exception: IllegalArgumentException) {
            respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", exception.message))
        } catch (exception: SocketTimeoutException) {
            respondJson(output, HTTP_GATEWAY_TIMEOUT, JSONObject().put("ok", false).put("error", exception.message))
        } catch (exception: IOException) {
            respondJson(output, HTTP_BAD_GATEWAY, JSONObject().put("ok", false).put("error", exception.message))
        } catch (exception: JSONException) {
            respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", exception.message))
        }
    }

    private fun handleLovenseCommand(request: HttpRequest, output: OutputStream) {
        try {
            val payload = parseJsonObject(request.body)
            val config = payload.optJSONObject("config") ?: JSONObject()
            val commands = payload.optJSONArray("commands")
                ?: throw IllegalArgumentException("commands must be a non-empty array")
            if (commands.length() == 0) {
                throw IllegalArgumentException("commands must be a non-empty array")
            }

            val timeoutMs = payload.optDouble("timeoutSeconds", 5.0).coerceIn(0.1, 60.0).times(1000).toInt()
            val results = JSONArray()
            for (index in 0 until commands.length()) {
                val commandPayload = commands.optJSONObject(index)
                    ?: throw IllegalArgumentException("commands must only contain JSON objects")
                val (result, resolvedEndpoint) = lovenseRequest(config, commandPayload, timeoutMs)
                results.put(
                    JSONObject()
                        .put("request", commandPayload)
                        .put("resolvedEndpoint", resolvedEndpoint)
                        .put("response", result),
                )
            }

            respondJson(output, HTTP_OK, JSONObject().put("ok", true).put("results", results))
        } catch (exception: IllegalArgumentException) {
            respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", exception.message))
        } catch (exception: SocketTimeoutException) {
            respondJson(output, HTTP_GATEWAY_TIMEOUT, JSONObject().put("ok", false).put("error", exception.message))
        } catch (exception: IOException) {
            respondJson(output, HTTP_BAD_GATEWAY, JSONObject().put("ok", false).put("error", exception.message))
        } catch (exception: JSONException) {
            respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", exception.message))
        }
    }

    private fun handleLibraryImport(requestUri: Uri, request: HttpRequest, output: OutputStream) {
        try {
            val kind = requestUri.getQueryParameter("kind") ?: ""
            val fileName = requestUri.getQueryParameter("filename") ?: ""
            val destinationDirectory = resolveLibraryDirectory(kind)
            val destinationFile = File(destinationDirectory, sanitizeLibraryFileName(fileName))
            destinationFile.parentFile?.mkdirs()
            destinationFile.writeBytes(request.body)

            respondJson(
                output,
                HTTP_OK,
                JSONObject()
                    .put("ok", true)
                    .put("path", destinationFile.absolutePath)
                    .put("fileName", destinationFile.name)
                    .put("sizeBytes", destinationFile.length()),
            )
        } catch (exception: IllegalArgumentException) {
            respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", exception.message))
        } catch (exception: IOException) {
            respondJson(output, HTTP_INTERNAL_SERVER_ERROR, JSONObject().put("ok", false).put("error", exception.message))
        }
    }

    private fun handleLibraryDelete(requestUri: Uri, output: OutputStream) {
        val libraryFile =
            try {
                val kind = requestUri.getQueryParameter("kind") ?: ""
                val fileName = requestUri.getQueryParameter("filename") ?: ""
                File(resolveLibraryDirectory(kind), sanitizeLibraryFileName(fileName))
            } catch (exception: IllegalArgumentException) {
                respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", exception.message))
                return
            }

        if (!libraryFile.isFile) {
            respondJson(
                output,
                HTTP_NOT_FOUND,
                JSONObject()
                    .put("ok", false)
                    .put("error", "Library file was not found: ${libraryFile.name}"),
            )
            return
        }

        val sizeBytes = libraryFile.length()
        try {
            if (!libraryFile.delete()) {
                throw IOException("Could not delete library file: ${libraryFile.name}")
            }
            respondJson(
                output,
                HTTP_OK,
                JSONObject()
                    .put("ok", true)
                    .put("path", libraryFile.absolutePath)
                    .put("fileName", libraryFile.name)
                    .put("sizeBytes", sizeBytes),
            )
        } catch (exception: IOException) {
            respondJson(output, HTTP_INTERNAL_SERVER_ERROR, JSONObject().put("ok", false).put("error", exception.message))
        } catch (exception: SecurityException) {
            respondJson(output, HTTP_INTERNAL_SERVER_ERROR, JSONObject().put("ok", false).put("error", exception.message))
        }
    }

    private fun handleAndroidDocumentImport(requestUri: Uri, output: OutputStream) {
        val kind = requestUri.getQueryParameter("kind") ?: ""
        val fileName = requestUri.getQueryParameter("filename") ?: ""
        val rawUri = requestUri.getQueryParameter("uri")?.trim().orEmpty()
        if (rawUri.isBlank()) {
            respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", "Document URI is required"))
            return
        }

        val sourceUri =
            try {
                Uri.parse(rawUri)
            } catch (_: Exception) {
                respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", "Invalid document URI"))
                return
            }

        if (sourceUri.scheme != "content") {
            respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", "Only content document URIs are supported"))
            return
        }

        try {
            val destinationDirectory = resolveLibraryDirectory(kind)
            val destinationFile = File(destinationDirectory, sanitizeLibraryFileName(fileName))
            destinationFile.parentFile?.mkdirs()
            context.contentResolver.openInputStream(sourceUri).use { input ->
                if (input == null) {
                    throw FileNotFoundException("Document could not be opened")
                }
                destinationFile.outputStream().use { outputStream ->
                    input.copyTo(outputStream, 64 * 1024)
                    outputStream.flush()
                }
            }

            respondJson(
                output,
                HTTP_OK,
                JSONObject()
                    .put("ok", true)
                    .put("path", destinationFile.absolutePath)
                    .put("fileName", destinationFile.name)
                    .put("sizeBytes", destinationFile.length()),
            )
        } catch (exception: IllegalArgumentException) {
            respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", exception.message))
        } catch (exception: SecurityException) {
            respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", "Document access permission is missing"))
        } catch (exception: IOException) {
            respondJson(output, HTTP_INTERNAL_SERVER_ERROR, JSONObject().put("ok", false).put("error", exception.message))
        }
    }

    private fun handleLibraryList(requestUri: Uri, output: OutputStream) {
        try {
            val kind = requestUri.getQueryParameter("kind") ?: ""
            val directory = resolveLibraryDirectory(kind)
            val files = JSONArray()
            directory
                .listFiles()
                .orEmpty()
                .filter { file -> file.isFile }
                .sortedBy { file -> file.name.lowercase(Locale.US) }
                .forEach { file ->
                    files.put(
                        JSONObject()
                            .put("name", file.name)
                            .put("path", file.absolutePath)
                            .put("sizeBytes", file.length())
                            .put("modifiedMs", file.lastModified()),
                    )
                }

            respondJson(
                output,
                HTTP_OK,
                JSONObject()
                    .put("ok", true)
                    .put("kind", kind.trim().lowercase(Locale.US))
                    .put("files", files),
            )
        } catch (exception: IllegalArgumentException) {
            respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", exception.message))
        }
    }

    private fun handleLibraryFile(requestUri: Uri, request: HttpRequest, output: OutputStream) {
        val libraryFile =
            try {
                val kind = requestUri.getQueryParameter("kind") ?: ""
                val fileName = requestUri.getQueryParameter("filename") ?: ""
                File(resolveLibraryDirectory(kind), sanitizeLibraryFileName(fileName))
            } catch (exception: IllegalArgumentException) {
                respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", exception.message))
                return
            }

        if (!libraryFile.isFile) {
            respondJson(
                output,
                HTTP_NOT_FOUND,
                JSONObject()
                    .put("ok", false)
                    .put("error", "Library file was not found: ${libraryFile.name}"),
            )
            return
        }

        val requestedRange = request.headers["range"].orEmpty()
        val range =
            try {
                parseHttpRange(requestedRange, libraryFile.length())
            } catch (_: IllegalArgumentException) {
                respondRangeNotSatisfiable(output, libraryFile.length())
                return
            }

        respondFile(
            output = output,
            file = libraryFile,
            contentType = guessContentType(libraryFile.name),
            range = range,
            sendBody = request.method != "HEAD",
        )
    }

    private fun handleDocumentSelection(requestUri: Uri, output: OutputStream) {
        val kind = requestUri.getQueryParameter("kind")?.trim()?.lowercase(Locale.US).orEmpty().ifBlank { "files" }
        val documents =
            synchronized(this) {
                selectedDocumentsByKind[kind].orEmpty()
            }

        val payload = JSONArray()
        documents.forEach { document ->
            payload.put(
                JSONObject()
                    .put("token", document.token)
                    .put("kind", document.kind)
                    .put("name", document.displayName)
                    .put("uri", document.uri.toString())
                    .put("mimeType", document.mimeType)
                    .put("sizeBytes", document.sizeBytes),
            )
        }

        respondJson(output, HTTP_OK, JSONObject().put("ok", true).put("documents", payload))
    }

    private fun handleDocumentFile(requestUri: Uri, request: HttpRequest, output: OutputStream) {
        val rawUri = requestUri.getQueryParameter("uri")?.trim().orEmpty()
        if (rawUri.isBlank()) {
            respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", "Document URI is required"))
            return
        }

        val uri =
            try {
                Uri.parse(rawUri)
            } catch (_: Exception) {
                respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", "Invalid document URI"))
                return
            }

        if (uri.scheme != "content") {
            respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", "Only content document URIs are supported"))
            return
        }

        val metadata =
            try {
                resolveDocumentMetadata(uri)
            } catch (exception: Exception) {
                respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", exception.message))
                return
            }
        val contentType = context.contentResolver.getType(uri)?.ifBlank { null } ?: guessContentType(metadata.displayName)
        val requestedRange = request.headers["range"].orEmpty()

        try {
            context.contentResolver.openAssetFileDescriptor(uri, "r").use { descriptor ->
                if (descriptor == null) {
                    throw FileNotFoundException("Document could not be opened")
                }

                val fileSize =
                    when {
                        descriptor.length >= 0 -> descriptor.length
                        metadata.sizeBytes > 0 -> metadata.sizeBytes
                        else -> -1L
                    }
                if (fileSize <= 0) {
                    if (requestedRange.isNotBlank()) {
                        respondRangeNotSatisfiable(output, 0)
                        return
                    }
                    context.contentResolver.openInputStream(uri).use { input ->
                        if (input == null) {
                            throw FileNotFoundException("Document could not be opened")
                        }
                        respondBytes(output, HTTP_OK, contentType, input.readBytes())
                    }
                    return
                }

                val range =
                    try {
                        parseHttpRange(requestedRange, fileSize)
                    } catch (_: IllegalArgumentException) {
                        respondRangeNotSatisfiable(output, fileSize)
                        return
                    }

                respondAssetFile(
                    output = output,
                    descriptor = descriptor,
                    contentType = contentType,
                    fileSize = fileSize,
                    range = range,
                    sendBody = request.method != "HEAD",
                )
            }
        } catch (exception: FileNotFoundException) {
            respondJson(output, HTTP_NOT_FOUND, JSONObject().put("ok", false).put("error", exception.message))
        } catch (exception: SecurityException) {
            respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", "Document access permission is missing"))
        } catch (exception: IOException) {
            respondJson(output, HTTP_INTERNAL_SERVER_ERROR, JSONObject().put("ok", false).put("error", exception.message))
        }
    }

    private fun handleDocumentWrite(requestUri: Uri, request: HttpRequest, output: OutputStream) {
        val token = requestUri.getQueryParameter("token")?.trim().orEmpty()
        if (token.isBlank()) {
            respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", "Document token is required"))
            return
        }

        val document =
            synchronized(this) {
                selectedDocumentsByToken[token]
            }

        if (document == null) {
            respondJson(output, HTTP_NOT_FOUND, JSONObject().put("ok", false).put("error", "Document token was not found"))
            return
        }

        try {
            openDocumentOutputStream(document.uri).use { stream ->
                stream.write(request.body)
                stream.flush()
            }
            respondJson(
                output,
                HTTP_OK,
                JSONObject()
                    .put("ok", true)
                    .put("token", document.token)
                    .put("name", document.displayName)
                    .put("uri", document.uri.toString()),
            )
        } catch (exception: IOException) {
            respondJson(output, HTTP_INTERNAL_SERVER_ERROR, JSONObject().put("ok", false).put("error", exception.message))
        }
    }

    private fun handleSettingsUpdate(request: HttpRequest, output: OutputStream) {
        try {
            val payload = parseJsonObject(request.body)
            val currentSettings = loadSettings()
            val updates = payload.optJSONObject("updates") ?: JSONObject()
            currentSettings.optJSONObject("updates")?.let { updateSettings ->
                if (updates.has("autoCheckEnabled")) {
                    updateSettings.put("autoCheckEnabled", updates.optBoolean("autoCheckEnabled"))
                }
                if (updates.has("manualDisclosureAcknowledgedVersion")) {
                    updateSettings.put(
                        "manualDisclosureAcknowledgedVersion",
                        UpdateManifestParser.normalizeOptionalString(updates.opt("manualDisclosureAcknowledgedVersion")),
                    )
                }
                if (updates.has("releaseDisclosureSuppressedVersion")) {
                    updateSettings.put(
                        "releaseDisclosureSuppressedVersion",
                        UpdateManifestParser.normalizeOptionalString(updates.opt("releaseDisclosureSuppressedVersion")),
                    )
                }
            }
            val ui = payload.optJSONObject("ui") ?: JSONObject()
            currentSettings.optJSONObject("ui")?.let { uiSettings ->
                if (ui.has("showDiagnostics")) {
                    uiSettings.put("showDiagnostics", ui.optBoolean("showDiagnostics"))
                }
                if (ui.has("showFunscriptOverview")) {
                    uiSettings.put("showFunscriptOverview", ui.optBoolean("showFunscriptOverview"))
                }
                if (ui.has("showExecutionLog")) {
                    uiSettings.put("showExecutionLog", ui.optBoolean("showExecutionLog"))
                }
                if (ui.has("showUpdates")) {
                    uiSettings.put("showUpdates", ui.optBoolean("showUpdates"))
                }
            }
            val legal = payload.optJSONObject("legal") ?: JSONObject()
            currentSettings.optJSONObject("legal")?.let { legalSettings ->
                if (legal.has("lastAcknowledgedVersion")) {
                    legalSettings.put(
                        "lastAcknowledgedVersion",
                        UpdateManifestParser.normalizeOptionalString(legal.opt("lastAcknowledgedVersion")),
                    )
                }
            }
            val savedSettings = saveSettings(currentSettings)
            respondJson(
                output,
                HTTP_OK,
                JSONObject()
                    .put("ok", true)
                    .put("currentVersion", BuildConfig.VERSION_NAME)
                    .put("settings", savedSettings)
                    .put(
                        "updateSupport",
                        JSONObject()
                            .put("configured", UPDATE_FEED_URL.isNotBlank())
                            .put("sourceUrl", UPDATE_FEED_URL)
                            .put("releaseUrl", RELEASE_PAGE_URL),
                    ),
            )
        } catch (exception: JSONException) {
            respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", exception.message))
        } catch (exception: IOException) {
            respondJson(output, HTTP_INTERNAL_SERVER_ERROR, JSONObject().put("ok", false).put("error", exception.message))
        }
    }

    private fun handleClipboardWrite(request: HttpRequest, output: OutputStream) {
        try {
            val payload = parseJsonObject(request.body)
            val text = UpdateManifestParser.normalizeOptionalString(payload.opt("text"))
            if (text.isBlank()) {
                throw IllegalArgumentException("Clipboard text is required")
            }

            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(ClipData.newPlainText("FHPlayer diagnostics log", text))
            respondJson(output, HTTP_OK, JSONObject().put("ok", true))
        } catch (exception: IllegalArgumentException) {
            respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", exception.message))
        } catch (exception: JSONException) {
            respondJson(output, HTTP_BAD_REQUEST, JSONObject().put("ok", false).put("error", exception.message))
        }
    }

    private fun handleUpdateCheck(output: OutputStream) {
        val updateResult = fetchUpdateResult(platform = "android")
        val currentSettings = loadSettings()
        currentSettings.optJSONObject("updates")?.put("lastResult", updateResult)
        val savedSettings =
            try {
                saveSettings(currentSettings)
            } catch (exception: IOException) {
                respondJson(output, HTTP_INTERNAL_SERVER_ERROR, JSONObject().put("ok", false).put("error", exception.message))
                return
            }

        val statusCode = if (updateResult.optString("status") == "error") HTTP_BAD_GATEWAY else HTTP_OK
        AppLogger.info(
            context,
            "Update check finished with status=${updateResult.optString("status")} latest=${updateResult.optString("latestVersion")}.",
        )
        respondJson(
            output,
            statusCode,
            JSONObject()
                .put("ok", statusCode == HTTP_OK)
                .put("currentVersion", BuildConfig.VERSION_NAME)
                .put("result", updateResult)
                .put("settings", savedSettings)
                .put(
                    "updateSupport",
                    JSONObject()
                        .put("configured", UPDATE_FEED_URL.isNotBlank())
                        .put("sourceUrl", UPDATE_FEED_URL)
                        .put("releaseUrl", RELEASE_PAGE_URL),
                ),
        )
    }

    @Throws(IOException::class, JSONException::class)
    private fun lovenseRequest(config: JSONObject, payload: JSONObject, timeoutMs: Int): Pair<JSONObject, String> {
        val platformName = config.optString("platformName", "FHPlayer").trim().ifEmpty { "FHPlayer" }
        val candidates = buildLovenseRequestCandidates(config)
        val errors = mutableListOf<String>()
        var lastError: Exception? = null

        candidates.forEach { (scheme, hostValue, portValue) ->
            val url = "$scheme://$hostValue:$portValue/command"
            try {
                return executeLovenseRequest(url, platformName, payload, timeoutMs) to url
            } catch (exception: IllegalArgumentException) {
                throw exception
            } catch (exception: Exception) {
                lastError = exception
                errors += "$url: ${exception.message ?: exception.javaClass.simpleName}"
            }
        }

        val exception = lastError ?: IOException("No Lovense request candidates were generated.")
        val detail = errors.takeLast(4).joinToString(" | ")
        throw IOException("${exception.message ?: exception.javaClass.simpleName}. Tried: $detail", exception)
    }

    private fun buildLovenseRequestCandidates(config: JSONObject): List<Triple<String, String, String>> {
        val scheme = config.optString("scheme", "https").trim().lowercase(Locale.US).ifEmpty { "https" }
        val hostValue = config.optString("host", "").trim()
        val portValue = config.optString("port", "").trim()

        if (hostValue.isEmpty()) {
            throw IllegalArgumentException("Lovense host is required")
        }
        if (portValue.isEmpty()) {
            throw IllegalArgumentException("Lovense port is required")
        }
        if (scheme != "http" && scheme != "https") {
            throw IllegalArgumentException("Lovense scheme must be http or https")
        }

        val candidates = mutableListOf<Triple<String, String, String>>()
        val seen = linkedSetOf<Triple<String, String, String>>()
        fun addCandidate(candidateScheme: String, candidateHost: String, candidatePort: String) {
            val normalized = Triple(candidateScheme, candidateHost.trim(), candidatePort.trim())
            if (normalized.second.isEmpty() || normalized.third.isEmpty() || !seen.add(normalized)) {
                return
            }
            candidates += normalized
        }

        addCandidate(scheme, hostValue, portValue)

        val ipv4 = extractLovenseIpv4(hostValue)
        if (ipv4 != null) {
            val dashedHost = "${ipv4.replace(".", "-")}.lovense.club"
            val dottedHost = "$ipv4.lovense.club"
            listOf(dashedHost, dottedHost).forEach { httpsHost ->
                addCandidate("https", httpsHost, portValue)
                addCandidate("https", httpsHost, "30010")
            }
            addCandidate("https", ipv4, portValue)
            addCandidate("https", ipv4, "30010")
            addCandidate("http", ipv4, portValue)
            addCandidate("http", ipv4, "20010")
        }

        return candidates
    }

    private fun executeLovenseRequest(url: String, platformName: String, payload: JSONObject, timeoutMs: Int): JSONObject {
        val parsedUrl = URL(url)
        validateLovenseRequestUrl(parsedUrl)

        // Certificate pinning is intentionally not applied here: Lovense endpoints are local,
        // user/device-specific, and may use dynamically generated hostnames or certificates.
        // The request is restricted to local Lovense endpoints before opening the connection.
        val connection = (parsedUrl.openConnection() as HttpURLConnection).apply {
            connectTimeout = timeoutMs
            readTimeout = timeoutMs
            requestMethod = "POST"
            doInput = true
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("X-platform", platformName)
        }

        if (connection is HttpsURLConnection && shouldUseUnsafeLovenseTls(parsedUrl)) {
            connection.sslSocketFactory = unsafeSslSocketFactory
            connection.hostnameVerifier = localLovenseHostnameVerifier
        }

        connection.outputStream.use { stream ->
            stream.write(payload.toString().toByteArray(StandardCharsets.UTF_8))
        }

        val responseCode = connection.responseCode
        val responseBody = (if (responseCode >= 400) connection.errorStream else connection.inputStream)?.use { stream ->
            stream.bufferedReader(StandardCharsets.UTF_8).readText()
        } ?: ""

        if (responseCode >= 400) {
            throw IOException(responseBody.ifBlank { "Lovense request failed with HTTP $responseCode" })
        }

        if (responseBody.isBlank()) {
            return JSONObject()
        }

        return JSONObject(responseBody)
    }

    private fun shouldUseUnsafeLovenseTls(url: URL): Boolean {
        return url.protocol.equals("https", ignoreCase = true) && isLocalLovenseTlsHost(url.host)
    }

    private fun validateLovenseRequestUrl(url: URL) {
        val protocol = url.protocol.trim().lowercase(Locale.US)
        if (protocol != "http" && protocol != "https") {
            throw IllegalArgumentException("Lovense scheme must be http or https")
        }

        val hostValue = url.host?.trim()?.lowercase(Locale.US).orEmpty()
        if (hostValue.isBlank()) {
            throw IllegalArgumentException("Lovense host is required")
        }

        val portValue = if (url.port == -1) url.defaultPort else url.port
        if (portValue !in 1..65535) {
            throw IllegalArgumentException("Lovense port is invalid")
        }

        if (hostValue == "localhost") {
            return
        }

        val embeddedIpv4 = extractLovenseIpv4(hostValue)
        if (embeddedIpv4 != null && isLocalLovenseTlsHost(embeddedIpv4)) {
            return
        }

        if (isLocalLovenseTlsHost(hostValue)) {
            return
        }

        throw IllegalArgumentException("Lovense requests are restricted to local device endpoints")
    }

    @Throws(IOException::class)
    private fun openDocumentOutputStream(uri: Uri): OutputStream {
        val modes = listOf("rwt", "wt", "w")
        modes.forEach { mode ->
            try {
                val stream = context.contentResolver.openOutputStream(uri, mode)
                if (stream != null) {
                    return stream
                }
            } catch (_: Exception) {
            }
        }
        throw IOException("Could not open the selected document for writing.")
    }

    private fun resolveDocumentMetadata(uri: Uri): DocumentMetadata {
        var displayName = uri.lastPathSegment ?: "document"
        var sizeBytes = -1L
        val mimeType = context.contentResolver.getType(uri).orEmpty()

        val cursor: Cursor? = context.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null,
        )
        cursor?.use {
            if (it.moveToFirst()) {
                val displayNameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (displayNameIndex >= 0 && !it.isNull(displayNameIndex)) {
                    displayName = it.getString(displayNameIndex)
                }
                val sizeIndex = it.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && !it.isNull(sizeIndex)) {
                    sizeBytes = it.getLong(sizeIndex)
                }
            }
        }

        return DocumentMetadata(
            displayName = displayName,
            mimeType = mimeType,
            sizeBytes = sizeBytes,
        )
    }

    private fun extractLovenseIpv4(hostValue: String): String? {
        val normalizedHost = hostValue.trim().lowercase(Locale.US)
        if (normalizedHost.isBlank()) {
            return null
        }

        var candidate = normalizedHost.removeSuffix(".lovense.club")
        if ('-' in candidate && '.' !in candidate) {
            candidate = candidate.replace("-", ".")
        }

        val parts = candidate.split('.')
        if (parts.size != 4) {
            return null
        }

        return if (parts.all { part -> part.toIntOrNull() in 0..255 }) candidate else null
    }

    private fun normalizeLovenseToys(payload: JSONObject): JSONObject {
        val data = payload.optJSONObject("data") ?: JSONObject()
        val toysRaw = data.opt("toys")
        val toysMap = when (toysRaw) {
            is JSONObject -> toysRaw
            is String -> {
                if (toysRaw.isBlank()) {
                    JSONObject()
                } else {
                    val parsedValue = JSONTokener(toysRaw).nextValue()
                    if (parsedValue is JSONObject) parsedValue else JSONObject()
                }
            }
            else -> JSONObject()
        }

        val toys = JSONArray()
        val keys = toysMap.keys()
        while (keys.hasNext()) {
            val toyId = keys.next()
            val toyData = toysMap.optJSONObject(toyId) ?: JSONObject()
            val fullFunctionNames = normalizeJsonArray(toyData.opt("fullFunctionNames"))
            val shortFunctionNames = normalizeJsonArray(toyData.opt("shortFunctionNames"))
            val toyType = firstNonBlank(
                toyData.optString("type", ""),
                toyData.optString("toyType", ""),
                toyData.optString("name", ""),
                toyData.optString("nickName", ""),
            )

            toys.put(
                JSONObject()
                    .put("id", firstNonBlank(toyData.optString("id", ""), toyId))
                    .put("name", toyData.optString("name", ""))
                    .put("nickName", toyData.optString("nickName", ""))
                    .put("type", toyType)
                    .put("battery", toyData.opt("battery"))
                    .put("status", toyData.opt("status"))
                    .put("version", toyData.optString("version", ""))
                    .put("fullFunctionNames", fullFunctionNames)
                    .put("shortFunctionNames", shortFunctionNames),
            )
        }

        return JSONObject()
            .put("platform", data.optString("platform", ""))
            .put("appType", data.optString("appType", ""))
            .put("toys", toys)
    }

    private fun normalizeJsonArray(value: Any?): JSONArray {
        return when (value) {
            is JSONArray -> value
            is String -> {
                if (value.isBlank()) {
                    JSONArray()
                } else {
                    val parsed = JSONTokener(value).nextValue()
                    if (parsed is JSONArray) parsed else JSONArray()
                }
            }
            else -> JSONArray()
        }
    }

    @Throws(IOException::class)
    private fun parseRequest(input: InputStream): HttpRequest? {
        val requestLine = readHttpLine(input) ?: return null
        if (requestLine.isBlank()) {
            return null
        }

        val parts = requestLine.split(" ")
        if (parts.size < 2) {
            throw IOException("Invalid HTTP request line: $requestLine")
        }

        val headers = linkedMapOf<String, String>()
        while (true) {
            val line = readHttpLine(input) ?: break
            if (line.isEmpty()) {
                break
            }

            val separatorIndex = line.indexOf(':')
            if (separatorIndex <= 0) {
                continue
            }

            val name = line.substring(0, separatorIndex).trim().lowercase(Locale.US)
            val value = line.substring(separatorIndex + 1).trim()
            headers[name] = value
        }

        val contentLength = headers["content-length"]?.toIntOrNull() ?: 0
        val body = if (contentLength > 0) readExactBytes(input, contentLength) else ByteArray(0)

        return HttpRequest(
            method = parts[0].uppercase(Locale.US),
            path = parts[1],
            headers = headers,
            body = body,
        )
    }

    @Throws(IOException::class)
    private fun readHttpLine(input: InputStream): String? {
        val buffer = ByteArrayOutputStream()
        while (true) {
            val value = input.read()
            if (value == -1) {
                if (buffer.size() == 0) {
                    return null
                }
                break
            }
            if (value == '\n'.code) {
                break
            }
            buffer.write(value)
        }

        val rawLine = buffer.toString(StandardCharsets.US_ASCII.name())
        return rawLine.trimEnd('\r')
    }

    @Throws(IOException::class)
    private fun readExactBytes(input: InputStream, length: Int): ByteArray {
        val buffer = ByteArray(length)
        var offset = 0
        while (offset < length) {
            val bytesRead = input.read(buffer, offset, length - offset)
            if (bytesRead == -1) {
                throw EOFException("Unexpected end of request body.")
            }
            offset += bytesRead
        }
        return buffer
    }

    @Throws(JSONException::class)
    private fun parseJsonObject(body: ByteArray): JSONObject {
        val text = body.toString(StandardCharsets.UTF_8)
        if (text.isBlank()) {
            return JSONObject()
        }
        return JSONObject(text)
    }

    private fun contentSecurityPolicy(): String {
        val localBaseUrl = baseUrl()
        val localhostBaseUrl = localBaseUrl.replace("127.0.0.1", "localhost")
        return listOf(
            "default-src 'self'",
            "base-uri 'none'",
            "object-src 'none'",
            "frame-ancestors 'none'",
            "form-action 'self'",
            "script-src 'self'",
            "style-src 'self' 'unsafe-inline'",
            "img-src 'self' data: blob:",
            "font-src 'self' data:",
            "media-src 'self' blob: $localBaseUrl $localhostBaseUrl",
            "connect-src 'self' $localBaseUrl $localhostBaseUrl",
            "worker-src 'self' blob:",
            "manifest-src 'self'",
        ).joinToString("; ")
    }

    private fun StringBuilder.appendSecurityHeaders() {
        append("Content-Security-Policy: ")
        append(contentSecurityPolicy())
        append("\r\n")
        append("X-Content-Type-Options: nosniff\r\n")
        append("Referrer-Policy: no-referrer\r\n")
        append("Permissions-Policy: camera=(), microphone=(), geolocation=()\r\n")
        append("X-Frame-Options: DENY\r\n")
    }

    private fun respondJson(output: OutputStream, statusCode: Int, payload: JSONObject) {
        respondBytes(
            output,
            statusCode,
            "application/json; charset=utf-8",
            payload.toString().toByteArray(StandardCharsets.UTF_8),
        )
    }

    private fun respondBytes(output: OutputStream, statusCode: Int, contentType: String, body: ByteArray) {
        val headerText =
            buildString {
                append("HTTP/1.1 ")
                append(statusCode)
                append(' ')
                append(statusMessage(statusCode))
                append("\r\n")
                append("Content-Type: ")
                append(contentType)
                append("\r\n")
                append("Content-Length: ")
                append(body.size)
                append("\r\n")
                append("Cache-Control: no-store\r\n")
                appendSecurityHeaders()
                append("Connection: close\r\n")
                append("\r\n")
            }
        output.write(headerText.toByteArray(StandardCharsets.US_ASCII))
        output.write(body)
    }

    private fun respondFile(
        output: OutputStream,
        file: File,
        contentType: String,
        range: LongRange?,
        sendBody: Boolean,
    ) {
        val fileSize = file.length()
        val start = range?.first ?: 0L
        val end = range?.last ?: if (fileSize > 0) fileSize - 1 else 0L
        val contentLength = if (fileSize > 0) end - start + 1 else 0L
        val statusCode = if (range != null) HTTP_PARTIAL_CONTENT else HTTP_OK
        val headerText =
            buildString {
                append("HTTP/1.1 ")
                append(statusCode)
                append(' ')
                append(statusMessage(statusCode))
                append("\r\n")
                append("Content-Type: ")
                append(contentType)
                append("\r\n")
                append("Content-Length: ")
                append(contentLength)
                append("\r\n")
                append("Accept-Ranges: bytes\r\n")
                append("Cache-Control: no-store\r\n")
                appendSecurityHeaders()
                if (range != null) {
                    append("Content-Range: bytes ")
                    append(start)
                    append('-')
                    append(end)
                    append('/')
                    append(fileSize)
                    append("\r\n")
                }
                append("Connection: close\r\n")
                append("\r\n")
            }
        output.write(headerText.toByteArray(StandardCharsets.US_ASCII))

        if (!sendBody || contentLength <= 0) {
            return
        }

        RandomAccessFile(file, "r").use { randomAccessFile ->
            randomAccessFile.seek(start)
            val buffer = ByteArray(64 * 1024)
            var remaining = contentLength
            while (remaining > 0) {
                val bytesRead = randomAccessFile.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
                if (bytesRead <= 0) {
                    break
                }
                output.write(buffer, 0, bytesRead)
                remaining -= bytesRead.toLong()
            }
        }
    }

    private fun respondAssetFile(
        output: OutputStream,
        descriptor: android.content.res.AssetFileDescriptor,
        contentType: String,
        fileSize: Long,
        range: LongRange?,
        sendBody: Boolean,
    ) {
        val start = range?.first ?: 0L
        val end = range?.last ?: if (fileSize > 0) fileSize - 1 else 0L
        val contentLength = if (fileSize > 0) end - start + 1 else 0L
        val statusCode = if (range != null) HTTP_PARTIAL_CONTENT else HTTP_OK
        val headerText =
            buildString {
                append("HTTP/1.1 ")
                append(statusCode)
                append(' ')
                append(statusMessage(statusCode))
                append("\r\n")
                append("Content-Type: ")
                append(contentType)
                append("\r\n")
                append("Content-Length: ")
                append(contentLength)
                append("\r\n")
                append("Accept-Ranges: bytes\r\n")
                append("Cache-Control: no-store\r\n")
                appendSecurityHeaders()
                if (range != null) {
                    append("Content-Range: bytes ")
                    append(start)
                    append('-')
                    append(end)
                    append('/')
                    append(fileSize)
                    append("\r\n")
                }
                append("Connection: close\r\n")
                append("\r\n")
            }
        output.write(headerText.toByteArray(StandardCharsets.US_ASCII))

        if (!sendBody || contentLength <= 0) {
            return
        }

        FileInputStream(descriptor.fileDescriptor).use { input ->
            skipFully(input, descriptor.startOffset + start)
            val buffer = ByteArray(64 * 1024)
            var remaining = contentLength
            while (remaining > 0) {
                val bytesRead = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
                if (bytesRead <= 0) {
                    break
                }
                output.write(buffer, 0, bytesRead)
                remaining -= bytesRead.toLong()
            }
        }
    }

    @Throws(IOException::class)
    private fun skipFully(input: InputStream, bytesToSkip: Long) {
        var remaining = bytesToSkip
        while (remaining > 0) {
            val skipped = input.skip(remaining)
            if (skipped > 0) {
                remaining -= skipped
                continue
            }
            if (input.read() == -1) {
                throw EOFException("Unexpected end of document stream.")
            }
            remaining -= 1
        }
    }

    private fun respondRangeNotSatisfiable(output: OutputStream, fileSize: Long) {
        val headerText =
            buildString {
                append("HTTP/1.1 ")
                append(HTTP_RANGE_NOT_SATISFIABLE)
                append(' ')
                append(statusMessage(HTTP_RANGE_NOT_SATISFIABLE))
                append("\r\n")
                append("Content-Range: bytes */")
                append(fileSize)
                append("\r\n")
                append("Content-Length: 0\r\n")
                append("Accept-Ranges: bytes\r\n")
                append("Cache-Control: no-store\r\n")
                appendSecurityHeaders()
                append("Connection: close\r\n")
                append("\r\n")
            }
        output.write(headerText.toByteArray(StandardCharsets.US_ASCII))
    }

    private fun parseHttpRange(rangeHeader: String, fileSize: Long): LongRange? {
        val normalizedHeader = rangeHeader.trim()
        if (normalizedHeader.isBlank()) {
            return null
        }
        val match = Regex("""bytes=(\d*)-(\d*)""").matchEntire(normalizedHeader)
            ?: throw IllegalArgumentException("Invalid Range header")
        if (fileSize <= 0) {
            throw IllegalArgumentException("Invalid Range header")
        }

        val startText = match.groupValues[1]
        val endText = match.groupValues[2]
        if (startText.isBlank() && endText.isBlank()) {
            throw IllegalArgumentException("Invalid Range header")
        }

        val start: Long
        val end: Long
        if (startText.isBlank()) {
            val suffixLength = endText.toLongOrNull() ?: throw IllegalArgumentException("Invalid Range header")
            if (suffixLength <= 0) {
                throw IllegalArgumentException("Invalid Range header")
            }
            start = (fileSize - suffixLength).coerceAtLeast(0)
            end = fileSize - 1
        } else {
            start = startText.toLongOrNull() ?: throw IllegalArgumentException("Invalid Range header")
            end = if (endText.isBlank()) {
                fileSize - 1
            } else {
                endText.toLongOrNull() ?: throw IllegalArgumentException("Invalid Range header")
            }
        }

        val normalizedEnd = end.coerceAtMost(fileSize - 1)
        if (start < 0 || start >= fileSize || normalizedEnd < start) {
            throw IllegalArgumentException("Invalid Range header")
        }
        return start..normalizedEnd
    }

    private fun guessContentType(path: String): String {
        return when {
            path.endsWith(".html") -> "text/html; charset=utf-8"
            path.endsWith(".js") -> "application/javascript; charset=utf-8"
            path.endsWith(".css") -> "text/css; charset=utf-8"
            path.endsWith(".json") -> "application/json; charset=utf-8"
            path.endsWith(".funscript") -> "application/json; charset=utf-8"
            path.endsWith(".mp4") -> "video/mp4"
            path.endsWith(".webm") -> "video/webm"
            path.endsWith(".m4v") -> "video/mp4"
            path.endsWith(".mov") -> "video/quicktime"
            path.endsWith(".svg") -> "image/svg+xml"
            path.endsWith(".png") -> "image/png"
            path.endsWith(".jpg") || path.endsWith(".jpeg") -> "image/jpeg"
            else -> "application/octet-stream"
        }
    }

    private fun statusMessage(statusCode: Int): String {
        return when (statusCode) {
            HTTP_OK -> "OK"
            HTTP_PARTIAL_CONTENT -> "Partial Content"
            HTTP_BAD_REQUEST -> "Bad Request"
            HTTP_NOT_FOUND -> "Not Found"
            HTTP_BAD_GATEWAY -> "Bad Gateway"
            HTTP_GATEWAY_TIMEOUT -> "Gateway Timeout"
            HTTP_NOT_IMPLEMENTED -> "Not Implemented"
            HTTP_RANGE_NOT_SATISFIABLE -> "Range Not Satisfiable"
            else -> "Internal Server Error"
        }
    }

    private fun firstNonBlank(vararg values: String): String {
        values.forEach { value ->
            if (value.isNotBlank()) {
                return value
            }
        }
        return ""
    }

    private fun utcNowIso(): String = Instant.now().toString()

    private fun fetchUpdateResult(platform: String): JSONObject {
        if (UPDATE_FEED_URL.isBlank()) {
            return JSONObject()
                .put("status", "unconfigured")
                .put("checkedAt", utcNowIso())
                .put("currentVersion", BuildConfig.VERSION_NAME)
                .put("latestVersion", "")
                .put("updateAvailable", false)
                .put("releaseUrl", RELEASE_PAGE_URL)
                .put("downloadUrl", "")
                .put("assetName", "")
                .put("publishedAt", "")
                .put("message", "No update feed is configured.")
                .put("sourceUrl", UPDATE_FEED_URL)
        }

        return try {
            val connection = (URL(UPDATE_FEED_URL).openConnection() as HttpURLConnection).apply {
                connectTimeout = 5000
                readTimeout = 5000
                requestMethod = "GET"
                doInput = true
                setRequestProperty("Accept", "application/json")
                setRequestProperty("User-Agent", "FHPlayer/${BuildConfig.VERSION_NAME}")
            }
            val responseCode = connection.responseCode
            val responseBody = (if (responseCode >= 400) connection.errorStream else connection.inputStream)?.use { stream ->
                stream.bufferedReader(StandardCharsets.UTF_8).readText()
            }.orEmpty()

            if (UPDATE_FEED_URL == DEFAULT_UPDATE_FEED_URL && responseCode == HTTP_NOT_FOUND) {
                return JSONObject()
                    .put("status", "unavailable")
                    .put("checkedAt", utcNowIso())
                    .put("currentVersion", BuildConfig.VERSION_NAME)
                    .put("latestVersion", "")
                    .put("updateAvailable", false)
                    .put("releaseUrl", RELEASE_PAGE_URL)
                    .put("downloadUrl", "")
                    .put("assetName", "")
                    .put("publishedAt", "")
                    .put("message", "No GitHub release has been published yet.")
                    .put("sourceUrl", UPDATE_FEED_URL)
            }

            if (responseCode >= 400) {
                throw IOException(responseBody.ifBlank { "Update check failed with HTTP $responseCode" })
            }

            UpdateManifestParser.parseReleasePayload(JSONObject(responseBody), platform, BuildConfig.VERSION_NAME, utcNowIso())
                .put("sourceUrl", UPDATE_FEED_URL)
        } catch (exception: Exception) {
            JSONObject()
                .put("status", "error")
                .put("checkedAt", utcNowIso())
                .put("currentVersion", BuildConfig.VERSION_NAME)
                .put("latestVersion", "")
                .put("updateAvailable", false)
                .put("releaseUrl", RELEASE_PAGE_URL)
                .put("downloadUrl", "")
                .put("assetName", "")
                .put("publishedAt", "")
                .put("message", exception.message ?: exception.javaClass.simpleName)
                .put("sourceUrl", UPDATE_FEED_URL)
        }
    }

    private fun buildDiagnosticsPayload(): JSONObject {
        val logDirectory = AppLogger.logDirectory(context)
        val logFile = AppLogger.logFile(context)
        return JSONObject()
            .put("ok", true)
            .put("platform", "android")
            .put("version", BuildConfig.VERSION_NAME)
            .put(
                "paths",
                JSONObject()
                    .put("appData", context.filesDir.absolutePath)
                    .put("libraryRoot", libraryRootDirectory().absolutePath)
                    .put("settingsFile", settingsFile().absolutePath)
                    .put("logDirectory", logDirectory.absolutePath)
                    .put("logFile", logFile.absolutePath),
            )
            .put(
                "capabilities",
                JSONObject()
                    .put("openLogFolder", false),
            )
            .put("recentLog", AppLogger.recentLogText(context))
    }

    private fun libraryRootDirectory(): File {
        val externalDirectory = context.getExternalFilesDir(null)
        val baseDirectory = externalDirectory ?: context.filesDir
        return File(baseDirectory, "Library").apply { mkdirs() }
    }

    private fun resolveLibraryDirectory(kind: String): File {
        val normalizedKind = kind.trim().lowercase(Locale.US)
        val childName =
            when (normalizedKind) {
                "video", "videos" -> "Videos"
                "funscript", "funscripts" -> "Funscripts"
                "export", "exports" -> "Exports"
                else -> throw IllegalArgumentException("Unsupported library kind")
            }
        return File(libraryRootDirectory(), childName).apply { mkdirs() }
    }

    private fun buildLibraryPayload(): JSONObject {
        val rootDirectory = libraryRootDirectory()
        val videosDirectory = resolveLibraryDirectory("videos")
        val funscriptsDirectory = resolveLibraryDirectory("funscripts")
        val exportsDirectory = resolveLibraryDirectory("exports")
        return JSONObject()
            .put("ok", true)
            .put("platform", "android")
            .put("rootPath", rootDirectory.absolutePath)
            .put(
                "directories",
                JSONObject()
                    .put("videos", videosDirectory.absolutePath)
                    .put("funscripts", funscriptsDirectory.absolutePath)
                    .put("exports", exportsDirectory.absolutePath),
            )
            .put(
                "capabilities",
                JSONObject()
                    .put("import", true)
                    .put("reveal", false)
                    .put("serve", true)
                    .put("delete", true),
            )
    }

    private fun sanitizeLibraryFileName(fileName: String): String {
        val normalized = fileName.replace("\\", "/").substringAfterLast('/').trim()
        val safeName = normalized.filterNot { character -> "<>:\"/\\|?*".contains(character) }.trim().trim('.')
        if (safeName.isBlank()) {
            throw IllegalArgumentException("A valid filename is required")
        }
        return safeName
    }

    data class HttpRequest(
        val method: String,
        val path: String,
        val headers: Map<String, String>,
        val body: ByteArray,
    )

    data class SelectedDocument(
        val token: String,
        val uri: Uri,
        val kind: String,
        val displayName: String,
        val mimeType: String,
        val sizeBytes: Long,
    )

    data class DocumentMetadata(
        val displayName: String,
        val mimeType: String,
        val sizeBytes: Long,
    )

    companion object {
        private const val HOST = "127.0.0.1"
        private const val PORT = 8765
        private const val HTTP_OK = 200
        private const val HTTP_PARTIAL_CONTENT = 206
        private const val HTTP_BAD_REQUEST = 400
        private const val HTTP_NOT_FOUND = 404
        private const val HTTP_RANGE_NOT_SATISFIABLE = 416
        private const val HTTP_INTERNAL_SERVER_ERROR = 500
        private const val HTTP_BAD_GATEWAY = 502
        private const val HTTP_GATEWAY_TIMEOUT = 504
        private const val HTTP_NOT_IMPLEMENTED = 501
        private const val DEFAULT_UPDATE_FEED_URL = "https://api.github.com/repos/Honaro19/FHPlayer/releases/latest"
        private const val RELEASE_PAGE_URL = "https://github.com/Honaro19/FHPlayer/releases"
        private val UPDATE_FEED_URL = BuildConfig.FHPLAYER_UPDATE_FEED_URL.ifBlank { DEFAULT_UPDATE_FEED_URL }

        private val localLovenseHostnameVerifier = HostnameVerifier { hostname, _ ->
            isLocalLovenseTlsHost(hostname)
        }

        private val unsafeSslSocketFactory: SSLSocketFactory by lazy {
            val trustManager = object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<java.security.cert.X509Certificate>, authType: String) {
                    throw CertificateException("Client certificates are not supported")
                }

                override fun checkServerTrusted(chain: Array<java.security.cert.X509Certificate>, authType: String) {
                    val certificates = chain?.toList().orEmpty()
                    if (certificates.isEmpty()) {
                        throw CertificateException("Server certificate chain is empty")
                    }
                }

                override fun getAcceptedIssuers(): Array<java.security.cert.X509Certificate> = emptyArray()
            }

            val context = SSLContext.getInstance("TLS")
            context.init(null, arrayOf<TrustManager>(trustManager), java.security.SecureRandom())
            context.socketFactory
        }

        private fun isLocalLovenseTlsHost(host: String?): Boolean {
            val normalizedHost = host?.trim().orEmpty()
            if (normalizedHost.isEmpty()) {
                return false
            }

            return try {
                val address = InetAddress.getByName(normalizedHost)
                address.hostAddress == normalizedHost && (
                    address.isSiteLocalAddress ||
                        address.isLoopbackAddress ||
                        address.isLinkLocalAddress
                    )
            } catch (_: Exception) {
                false
            }
        }

        fun baseUrl(): String = "http://$HOST:$PORT"
    }
}
