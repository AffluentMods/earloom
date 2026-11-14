// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

package com.affluentlabs.earloom

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Reads a folder the user picked with the system picker (a Storage Access
 * Framework tree), for the "Choose a folder" import. The app holds no storage
 * permission: the picker's grant on the tree is all it uses, and only while
 * the import runs.
 *
 * Methods (channel `com.affluentlabs.earloom/saf`):
 * - `list(treeUri)`: the folder's name and every document below it, as
 *   `{uri, segments, size}`, where `segments` is the path below the folder.
 * - `open(uri)` returns a handle, `read(handle, max)` up to `max` bytes
 *   (empty at the end), `skip(handle, count)`, `close(handle)`.
 *
 * All work runs off the main thread.
 */
class SafChannel(private val context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "com.affluentlabs.earloom/saf")
    private val io: ExecutorService = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private val streams = ConcurrentHashMap<Int, InputStream>()
    private val nextHandle = AtomicInteger(1)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        io.execute {
            try {
                val value: Any? = when (call.method) {
                    "list" -> list(Uri.parse(call.argument<String>("treeUri")!!))
                    "open" -> open(Uri.parse(call.argument<String>("uri")!!))
                    "read" -> read(call.argument<Int>("handle")!!, call.argument<Int>("max")!!)
                    "skip" -> skip(call.argument<Int>("handle")!!, call.argument<Number>("count")!!.toLong())
                    "close" -> close(call.argument<Int>("handle")!!)
                    else -> {
                        main.post { result.notImplemented() }
                        return@execute
                    }
                }
                main.post { result.success(value) }
            } catch (e: SecurityException) {
                main.post { result.error("unreadable", e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("unreadable", e.toString(), null) }
            }
        }
    }

    private fun list(treeUri: Uri): Map<String, Any?> {
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        val rootUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId)
        val files = ArrayList<Map<String, Any?>>()
        walk(treeUri, rootId, emptyList(), files, depth = 0)
        return mapOf("name" to displayName(rootUri), "files" to files)
    }

    private fun walk(
        treeUri: Uri,
        documentId: String,
        segments: List<String>,
        out: MutableList<Map<String, Any?>>,
        depth: Int,
    ) {
        if (depth > MAX_DEPTH || out.size >= MAX_FILES) return
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
        )
        val folders = ArrayList<Pair<String, String>>()
        context.contentResolver.query(children, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext() && out.size < MAX_FILES) {
                val id = cursor.getString(0) ?: continue
                val name = cursor.getString(1) ?: continue
                val mime = cursor.getString(2)
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    folders.add(id to name)
                } else {
                    val size = if (cursor.isNull(3)) 0L else cursor.getLong(3)
                    out.add(
                        mapOf(
                            "uri" to DocumentsContract.buildDocumentUriUsingTree(treeUri, id).toString(),
                            "segments" to segments + name,
                            "size" to size,
                        ),
                    )
                }
            }
        }
        for ((id, name) in folders) {
            walk(treeUri, id, segments + name, out, depth + 1)
        }
    }

    private fun displayName(uri: Uri): String {
        val projection = arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
        context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0) ?: ""
        }
        return ""
    }

    private fun open(uri: Uri): Int {
        val stream = context.contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("The document cannot be opened")
        val handle = nextHandle.getAndIncrement()
        streams[handle] = stream
        return handle
    }

    private fun read(handle: Int, max: Int): ByteArray {
        val stream = streams[handle] ?: throw IllegalStateException("Unknown handle")
        val buffer = ByteArray(max.coerceIn(1, MAX_CHUNK))
        var filled = 0
        while (filled < buffer.size) {
            val n = stream.read(buffer, filled, buffer.size - filled)
            if (n < 0) break
            filled += n
        }
        return if (filled == buffer.size) buffer else buffer.copyOf(filled)
    }

    private fun skip(handle: Int, count: Long): Any? {
        val stream = streams[handle] ?: throw IllegalStateException("Unknown handle")
        var left = count
        while (left > 0) {
            val skipped = stream.skip(left)
            if (skipped <= 0) {
                if (stream.read() < 0) break
                left -= 1
            } else {
                left -= skipped
            }
        }
        return null
    }

    private fun close(handle: Int): Any? {
        streams.remove(handle)?.close()
        return null
    }

    private companion object {
        const val MAX_DEPTH = 12
        const val MAX_FILES = 20000
        const val MAX_CHUNK = 4 * 1024 * 1024
    }
}
