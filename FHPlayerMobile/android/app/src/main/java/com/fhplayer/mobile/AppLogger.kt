package com.fhplayer.mobile

import android.content.Context
import android.util.Log
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.time.Instant
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

object AppLogger {
    private const val TAG = "FHPlayerMobile"
    private const val MAX_LOG_BYTES = 512_000L
    private const val MAX_LOG_BACKUPS = 3

    private val fileLock = ReentrantLock()

    fun configure(context: Context): File {
        val logDirectory = File(context.filesDir, "logs").apply { mkdirs() }
        return File(logDirectory, "fhplayer.log")
    }

    fun logDirectory(context: Context): File = configure(context).parentFile ?: context.filesDir

    fun logFile(context: Context): File = configure(context)

    fun recentLogText(context: Context, maxLines: Int = 120, maxChars: Int = 16_000): String {
        val logFile = logFile(context)
        if (!logFile.exists()) {
            return ""
        }

        val content =
            try {
                logFile.readText(Charsets.UTF_8)
            } catch (_: Exception) {
                return ""
            }

        val recent = content.lines().takeLast(maxLines).joinToString("\n")
        return if (recent.length > maxChars) recent.takeLast(maxChars) else recent
    }

    fun info(context: Context, message: String) {
        Log.i(TAG, message)
        append(context, "INFO", message, null)
    }

    fun warn(context: Context, message: String, throwable: Throwable? = null) {
        Log.w(TAG, message, throwable)
        append(context, "WARN", message, throwable)
    }

    fun error(context: Context, message: String, throwable: Throwable? = null) {
        Log.e(TAG, message, throwable)
        append(context, "ERROR", message, throwable)
    }

    private fun append(context: Context, level: String, message: String, throwable: Throwable?) {
        val logFile = logFile(context)
        fileLock.withLock {
            rotateIfNeeded(logFile)
            logFile.parentFile?.mkdirs()
            logFile.appendText(buildLogEntry(level, message, throwable), Charsets.UTF_8)
        }
    }

    private fun rotateIfNeeded(logFile: File) {
        if (!logFile.exists() || logFile.length() < MAX_LOG_BYTES) {
            return
        }

        for (index in MAX_LOG_BACKUPS downTo 1) {
            val source = if (index == 1) logFile else File(logFile.parentFile, "${logFile.name}.${index - 1}")
            val target = File(logFile.parentFile, "${logFile.name}.$index")
            if (!source.exists()) {
                continue
            }
            if (target.exists()) {
                target.delete()
            }
            source.renameTo(target)
        }
    }

    private fun buildLogEntry(level: String, message: String, throwable: Throwable?): String {
        val builder = StringBuilder()
        builder.append(Instant.now().toString())
        builder.append(' ')
        builder.append(level)
        builder.append(' ')
        builder.append(message.trim())
        builder.append('\n')

        if (throwable != null) {
            val trace = StringWriter()
            throwable.printStackTrace(PrintWriter(trace))
            builder.append(trace.toString().trimEnd())
            builder.append('\n')
        }

        return builder.toString()
    }
}
