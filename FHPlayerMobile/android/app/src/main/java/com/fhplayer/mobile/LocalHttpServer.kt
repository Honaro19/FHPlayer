package com.fhplayer.mobile

import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.net.URL
import java.nio.charset.StandardCharsets
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
    }

    fun isRunning(): Boolean = running

    fun ensureLibraryDirectories() {
        resolveLibraryDirectory("videos")
        resolveLibraryDirectory("funscripts")
        resolveLibraryDirectory("exports")
    }

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
                    Log.e(TAG, "Could not accept HTTP client.", exception)
                }
            }
        }
    }

    private fun handleClient(socket: Socket) {
        socket.use { client ->
            client.soTimeout = 10000
            client.tcpNoDelay = true
            val input = BufferedInputStream(client.getInputStream())
            val output = client.getOutputStream()
            try {
                val request = parseRequest(input) ?: return
                routeRequest(request, output)
            } catch (exception: Exception) {
                respondJson(
                    output,
                    HTTP_INTERNAL_SERVER_ERROR,
                    JSONObject()
                        .put("ok", false)
                        .put("error", exception.message ?: "Internal server error"),
                )
            } finally {
                output.flush()
            }
        }
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
                        .put("platform", "android")
                        .put(
                            "capabilities",
                            JSONObject()
                                .put("execute", false)
                                .put("lovense", true),
                        ),
                )
            }

            request.method == "GET" && path == "/api/library/info" -> {
                respondJson(output, HTTP_OK, buildLibraryPayload())
            }

            request.method == "GET" && path == "/api/android/document-selection" -> {
                handleDocumentSelection(requestUri, output)
            }

            request.method == "POST" && path == "/api/execute" -> {
                respondJson(
                    output,
                    HTTP_NOT_IMPLEMENTED,
                    JSONObject()
                        .put("ok", false)
                        .put("shell", "android")
                        .put("error", "Shell execution is not available in the Android app build.")
                        .put(
                            "result",
                            JSONObject()
                                .put("returnCode", -1)
                                .put("stdout", "")
                                .put("stderr", "Shell execution is not available in the Android app build.")
                                .put("durationMs", 0),
                        ),
                )
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

            request.method == "PUT" && path == "/api/android/document-write" -> {
                handleDocumentWrite(requestUri, request, output)
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
                val relativePath = path.removePrefix("/")
                if (relativePath.contains("..")) {
                    respondJson(
                        output,
                        HTTP_BAD_REQUEST,
                        JSONObject()
                            .put("ok", false)
                            .put("error", "Invalid asset path"),
                    )
                    return
                }
                "www/$relativePath"
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
                    .put("mimeType", document.mimeType)
                    .put("sizeBytes", document.sizeBytes),
            )
        }

        respondJson(output, HTTP_OK, JSONObject().put("ok", true).put("documents", payload))
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
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = timeoutMs
            readTimeout = timeoutMs
            requestMethod = "POST"
            doInput = true
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("X-platform", platformName)
        }

        if (connection is HttpsURLConnection) {
            connection.sslSocketFactory = unsafeSslSocketFactory
            connection.hostnameVerifier = unsafeHostnameVerifier
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
                append("Connection: close\r\n")
                append("\r\n")
            }
        output.write(headerText.toByteArray(StandardCharsets.US_ASCII))
        output.write(body)
    }

    private fun guessContentType(path: String): String {
        return when {
            path.endsWith(".html") -> "text/html; charset=utf-8"
            path.endsWith(".js") -> "application/javascript; charset=utf-8"
            path.endsWith(".css") -> "text/css; charset=utf-8"
            path.endsWith(".json") -> "application/json; charset=utf-8"
            path.endsWith(".svg") -> "image/svg+xml"
            path.endsWith(".png") -> "image/png"
            path.endsWith(".jpg") || path.endsWith(".jpeg") -> "image/jpeg"
            else -> "application/octet-stream"
        }
    }

    private fun statusMessage(statusCode: Int): String {
        return when (statusCode) {
            HTTP_OK -> "OK"
            HTTP_BAD_REQUEST -> "Bad Request"
            HTTP_NOT_FOUND -> "Not Found"
            HTTP_BAD_GATEWAY -> "Bad Gateway"
            HTTP_GATEWAY_TIMEOUT -> "Gateway Timeout"
            HTTP_NOT_IMPLEMENTED -> "Not Implemented"
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
                    .put("reveal", false),
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
        private const val TAG = "FHPlayerMobile"
        private const val HOST = "127.0.0.1"
        private const val PORT = 8765
        private const val HTTP_OK = 200
        private const val HTTP_BAD_REQUEST = 400
        private const val HTTP_NOT_FOUND = 404
        private const val HTTP_INTERNAL_SERVER_ERROR = 500
        private const val HTTP_BAD_GATEWAY = 502
        private const val HTTP_GATEWAY_TIMEOUT = 504
        private const val HTTP_NOT_IMPLEMENTED = 501

        private val unsafeHostnameVerifier = HostnameVerifier { _, _ -> true }

        private val unsafeSslSocketFactory: SSLSocketFactory by lazy {
            val trustManager = object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<java.security.cert.X509Certificate>, authType: String) {}

                override fun checkServerTrusted(chain: Array<java.security.cert.X509Certificate>, authType: String) {}

                override fun getAcceptedIssuers(): Array<java.security.cert.X509Certificate> = emptyArray()
            }

            val context = SSLContext.getInstance("TLS")
            context.init(null, arrayOf<TrustManager>(trustManager), java.security.SecureRandom())
            context.socketFactory
        }

        fun baseUrl(): String = "http://$HOST:$PORT"
    }
}
