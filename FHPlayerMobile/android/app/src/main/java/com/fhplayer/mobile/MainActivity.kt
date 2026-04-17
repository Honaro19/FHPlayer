package com.fhplayer.mobile

import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.webkit.RenderProcessGoneDetail
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebChromeClient.CustomViewCallback
import android.webkit.WebView
import android.webkit.WebViewClient
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.view.WindowCompat
import android.widget.FrameLayout
import android.widget.Toast
import java.io.IOException

class MainActivity : ComponentActivity() {
    private lateinit var rootContainer: FrameLayout
    private lateinit var webView: WebView
    private lateinit var localHttpServer: LocalHttpServer
    private var fileChooserCallback: ValueCallback<Array<Uri>>? = null
    private var pendingFileChooserKind: String = "files"
    private var fullscreenView: View? = null
    private var fullscreenCallback: CustomViewCallback? = null
    private val fileChooserLauncher: ActivityResultLauncher<Intent> =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            handleFileChooserResult(result.resultCode, result.data)
        }
    private val backNavigationCallback =
        object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (handleBackNavigation()) {
                    return
                }

                isEnabled = false
                onBackPressedDispatcher.onBackPressed()
                isEnabled = true
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppLogger.configure(applicationContext)
        AppLogger.info(applicationContext, "FHPlayer Android activity created.")
        registerBackHandler()

        localHttpServer = LocalHttpServer(applicationContext)
        localHttpServer.ensureLibraryDirectories()
        try {
            localHttpServer.start()
        } catch (exception: IOException) {
            AppLogger.error(applicationContext, "Could not start the embedded FHPlayer server.", exception)
            Toast.makeText(this, "Could not start the embedded FHPlayer server.", Toast.LENGTH_LONG).show()
            finish()
            return
        }

        createAndAttachWebView()
        loadHome()
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebView() {
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = true
            mediaPlaybackRequiresUserGesture = false
            mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
        }

        webView.webViewClient = object : WebViewClient() {
            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                AppLogger.error(
                    applicationContext,
                    "WebView renderer exited. didCrash=${detail.didCrash()} priority=${detail.rendererPriorityAtExit()}",
                )
                Toast.makeText(
                    this@MainActivity,
                    "The app view was restarted after a WebView crash.",
                    Toast.LENGTH_LONG,
                ).show()
                recreateWebView()
                return true
            }
        }
        webView.webChromeClient = object : WebChromeClient() {
            override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                showFullscreenView(view, callback)
            }

            override fun onHideCustomView() {
                hideFullscreenView()
            }

            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>,
                fileChooserParams: FileChooserParams,
            ): Boolean {
                this@MainActivity.fileChooserCallback?.onReceiveValue(null)
                this@MainActivity.fileChooserCallback = filePathCallback
                pendingFileChooserKind = inferFileChooserKind(fileChooserParams)

                return try {
                    val chooserIntent = buildFilePickerIntent(fileChooserParams)
                    fileChooserLauncher.launch(chooserIntent)
                    true
                } catch (exception: ActivityNotFoundException) {
                    this@MainActivity.fileChooserCallback = null
                    AppLogger.warn(applicationContext, "No file picker is available on this device.", exception)
                    Toast.makeText(
                        this@MainActivity,
                        "No file picker is available on this device.",
                        Toast.LENGTH_LONG,
                    ).show()
                    false
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (::localHttpServer.isInitialized && !localHttpServer.isRunning()) {
            try {
                localHttpServer.start()
            } catch (exception: IOException) {
                AppLogger.error(applicationContext, "Could not restart the embedded FHPlayer server.", exception)
                Toast.makeText(this, "Could not restart the embedded FHPlayer server.", Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun handleFileChooserResult(resultCode: Int, data: Intent?) {
        persistReadPermissions(data)
        val selectedUris = extractSelectedUris(resultCode, data)
        val acceptedUris = filterSelectedUrisByKind(pendingFileChooserKind, selectedUris.orEmpty())
        if (selectedUris != null && acceptedUris.size != selectedUris.size) {
            val rejectedCount = selectedUris.size - acceptedUris.size
            AppLogger.warn(
                applicationContext,
                "Ignored $rejectedCount unsupported file(s) for $pendingFileChooserKind.",
            )
            Toast.makeText(
                this,
                "Ignored $rejectedCount unsupported file${if (rejectedCount == 1) "" else "s"} for $pendingFileChooserKind.",
                Toast.LENGTH_LONG,
            ).show()
        }
        if (::localHttpServer.isInitialized) {
            localHttpServer.recordDocumentSelection(pendingFileChooserKind, acceptedUris.toTypedArray())
        }
        val resultCallback = fileChooserCallback
        fileChooserCallback = null
        pendingFileChooserKind = "files"
        resultCallback?.onReceiveValue(
            when {
                resultCode != RESULT_OK -> null
                acceptedUris.isEmpty() -> emptyArray()
                else -> acceptedUris.toTypedArray()
            },
        )
    }

    private fun persistReadPermissions(data: Intent?) {
        val grantedFlags = data?.flags ?: 0
        val persistableFlags = grantedFlags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        if ((grantedFlags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) == 0 || persistableFlags == 0) {
            return
        }

        data?.data?.let { uri ->
            try {
                contentResolver.takePersistableUriPermission(uri, persistableFlags)
            } catch (_: SecurityException) {
            }
        }

        val clipData = data?.clipData ?: return
        for (index in 0 until clipData.itemCount) {
            val uri = clipData.getItemAt(index).uri ?: continue
            try {
                contentResolver.takePersistableUriPermission(uri, persistableFlags)
            } catch (_: SecurityException) {
            }
        }
    }

    private fun buildFilePickerIntent(fileChooserParams: WebChromeClient.FileChooserParams): Intent {
        val normalizedAcceptTypes =
            fileChooserParams.acceptTypes
                .map { it.trim().lowercase() }
                .filter { it.isNotBlank() }

        val wantsVideo = normalizedAcceptTypes.any { acceptType ->
            acceptType == "video/*" || acceptType.startsWith("video/")
        }
        val wantsJsonLike = normalizedAcceptTypes.any { acceptType ->
            acceptType.contains("json") || acceptType.contains("funscript")
        }

        return Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, fileChooserParams.mode == WebChromeClient.FileChooserParams.MODE_OPEN_MULTIPLE)

            if (wantsVideo && !wantsJsonLike) {
                type = "video/*"
            } else if (wantsJsonLike && !wantsVideo) {
                // Android providers often treat ".funscript" as a generic binary file,
                // so we advertise JSON plus a generic fallback and validate the result after selection.
                type = "*/*"
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf("application/json", "text/json", "application/octet-stream"),
                )
            } else {
                type = "*/*"
            }
        }
    }

    private fun inferFileChooserKind(fileChooserParams: WebChromeClient.FileChooserParams): String {
        val normalizedAcceptTypes =
            fileChooserParams.acceptTypes
                .map { it.trim().lowercase() }
                .filter { it.isNotBlank() }

        val wantsVideo = normalizedAcceptTypes.any { acceptType ->
            acceptType == "video/*" || acceptType.startsWith("video/")
        }
        val wantsJsonLike = normalizedAcceptTypes.any { acceptType ->
            acceptType.contains("json") || acceptType.contains("funscript")
        }

        return when {
            wantsVideo && !wantsJsonLike -> "videos"
            wantsJsonLike -> "funscripts"
            else -> "files"
        }
    }

    private fun extractSelectedUris(resultCode: Int, data: Intent?): Array<Uri>? {
        if (resultCode != RESULT_OK) {
            return null
        }

        val clipData = data?.clipData
        if (clipData != null && clipData.itemCount > 0) {
            return Array(clipData.itemCount) { index ->
                clipData.getItemAt(index).uri
            }
        }

        return data?.data?.let { arrayOf(it) }
    }

    private fun filterSelectedUrisByKind(kind: String, uris: Array<out Uri>): List<Uri> {
        val normalizedKind = kind.trim().lowercase()
        if (normalizedKind != "funscripts") {
            return uris.toList()
        }

        return uris.filter { uri -> isAcceptedFunscriptUri(uri) }
    }

    private fun isAcceptedFunscriptUri(uri: Uri): Boolean {
        val displayName = resolveUriDisplayName(uri).lowercase()
        if (displayName.endsWith(".funscript") || displayName.endsWith(".json")) {
            return true
        }

        val mimeType = contentResolver.getType(uri)?.trim()?.lowercase().orEmpty()
        return mimeType == "application/json" || mimeType == "text/json"
    }

    private fun resolveUriDisplayName(uri: Uri): String =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val columnIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (columnIndex >= 0) {
                    cursor.getString(columnIndex).orEmpty()
                } else {
                    ""
                }
            } else {
                ""
            }
        }.orEmpty()

    private fun createAndAttachWebView() {
        rootContainer = FrameLayout(this)
        webView = WebView(this)
        rootContainer.addView(
            webView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        setContentView(rootContainer)
        configureWebView()
    }

    private fun recreateWebView() {
        if (::webView.isInitialized) {
            webView.destroy()
        }
        createAndAttachWebView()
        loadHome()
    }

    private fun loadHome() {
        webView.loadUrl(LocalHttpServer.baseUrl())
    }

    private fun showFullscreenView(view: View, callback: CustomViewCallback) {
        hideFullscreenView()

        fullscreenView = view
        fullscreenCallback = callback
        webView.visibility = View.GONE
        rootContainer.addView(
            view,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        applyFullscreenMode(isFullscreen = true)
    }

    private fun hideFullscreenView() {
        val customView = fullscreenView ?: return
        rootContainer.removeView(customView)
        fullscreenView = null
        webView.visibility = View.VISIBLE
        applyFullscreenMode(isFullscreen = false)
        fullscreenCallback?.onCustomViewHidden()
        fullscreenCallback = null
    }

    private fun registerBackHandler() {
        onBackPressedDispatcher.addCallback(this, backNavigationCallback)
    }

    private fun handleBackNavigation(): Boolean {
        if (fullscreenView != null) {
            hideFullscreenView()
            return true
        }
        if (::webView.isInitialized && webView.canGoBack()) {
            webView.goBack()
            return true
        }
        return false
    }

    private fun applyFullscreenMode(isFullscreen: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val insetsController = window.insetsController
            if (isFullscreen) {
                WindowCompat.setDecorFitsSystemWindows(window, false)
                insetsController?.hide(WindowInsets.Type.systemBars())
                insetsController?.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            } else {
                insetsController?.show(WindowInsets.Type.systemBars())
                WindowCompat.setDecorFitsSystemWindows(window, true)
            }
            return
        }

        applyLegacyFullscreenMode(isFullscreen)
    }

    @Suppress("DEPRECATION")
    private fun applyLegacyFullscreenMode(isFullscreen: Boolean) {
        if (isFullscreen) {
            window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            window.decorView.systemUiVisibility =
                (
                    View.SYSTEM_UI_FLAG_FULLSCREEN or
                        View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                        View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                        View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                        View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                        View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    )
            return
        }

        window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && fullscreenView != null) {
            applyFullscreenMode(isFullscreen = true)
        }
    }

    override fun onDestroy() {
        AppLogger.info(applicationContext, "FHPlayer Android activity is shutting down.")
        fileChooserCallback?.onReceiveValue(null)
        fileChooserCallback = null
        hideFullscreenView()

        if (::webView.isInitialized) {
            webView.destroy()
        }

        if (::localHttpServer.isInitialized && isFinishing) {
            localHttpServer.stop()
        }
        super.onDestroy()
    }
}
