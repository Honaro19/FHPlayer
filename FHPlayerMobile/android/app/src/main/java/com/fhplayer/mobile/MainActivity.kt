package com.fhplayer.mobile

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
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
import android.widget.FrameLayout
import android.widget.Toast
import java.io.IOException

class MainActivity : Activity() {
    private lateinit var rootContainer: FrameLayout
    private lateinit var webView: WebView
    private lateinit var localHttpServer: LocalHttpServer
    private var fileChooserCallback: ValueCallback<Array<Uri>>? = null
    private var pendingFileChooserKind: String = "files"
    private var fullscreenView: View? = null
    private var fullscreenCallback: CustomViewCallback? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        localHttpServer = LocalHttpServer(applicationContext)
        localHttpServer.ensureLibraryDirectories()
        try {
            localHttpServer.start()
        } catch (exception: IOException) {
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
                Log.e(
                    TAG,
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
                    startActivityForResult(chooserIntent, REQUEST_FILE_CHOOSER)
                    true
                } catch (_: ActivityNotFoundException) {
                    this@MainActivity.fileChooserCallback = null
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
                Toast.makeText(this, "Could not restart the embedded FHPlayer server.", Toast.LENGTH_LONG).show()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_FILE_CHOOSER) {
            return
        }

        persistReadPermissions(data)
        val selectedUris = extractSelectedUris(resultCode, data)
        if (::localHttpServer.isInitialized) {
            localHttpServer.recordDocumentSelection(pendingFileChooserKind, selectedUris.orEmpty())
        }
        val resultCallback = fileChooserCallback
        fileChooserCallback = null
        pendingFileChooserKind = "files"
        resultCallback?.onReceiveValue(selectedUris)
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
            } else {
                // Android providers usually do not understand ".funscript" as a filterable MIME type.
                // Using */* keeps those files selectable in Files / Downloads.
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
    }

    private fun hideFullscreenView() {
        val customView = fullscreenView ?: return
        rootContainer.removeView(customView)
        fullscreenView = null
        webView.visibility = View.VISIBLE
        window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        fullscreenCallback?.onCustomViewHidden()
        fullscreenCallback = null
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (fullscreenView != null) {
            hideFullscreenView()
            return
        }
        if (::webView.isInitialized && webView.canGoBack()) {
            webView.goBack()
            return
        }
        super.onBackPressed()
    }

    override fun onDestroy() {
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

    companion object {
        private const val TAG = "FHPlayerMobile"
        private const val REQUEST_FILE_CHOOSER = 4101
    }
}
