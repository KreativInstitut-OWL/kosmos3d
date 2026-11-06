package com.kosmos3d.kosmos3d

import android.content.ContentValues
import android.os.Build
import android.provider.MediaStore
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import android.media.MediaScannerConnection
import android.os.Environment
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val cameraWifi by lazy { CameraWifi(this) }
    override fun onDestroy() {
        cameraWifi.release()
        super.onDestroy()
    }
    private val CHANNEL = "com.kosmos3d.kosmos3d/system_settings"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "kosmos/gopro_preview", GoProPreviewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "joinCameraWifi" -> cameraWifi.join(call.argument<String>("ssid") ?: "", call.argument<String>("password") ?: "", result)
                "startCaptureService" -> {
                    try {
                        CaptureService.start(this, call.argument<String>("title") ?: "KOSMOS 3D")
                        result.success(true)
                    } catch (e: Exception) { result.error("CAPTURE_SERVICE", e.message, null) }
                }
                "stopCaptureService" -> { CaptureService.stop(this); result.success(true) }
                "keepScreenOn" -> {
                    if (call.argument<Boolean>("on") == true) {
                        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(true)
                }
                "releaseCameraWifi" -> { cameraWifi.release(); result.success(true) }
                "openWifiSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                        result.success(null)
                    } catch (e: Exception) { result.error("WIFI_SETTINGS", e.message, null) }
                }
                "saveToDownloads" -> {
                    val source = call.argument<String>("sourcePath")
                    val relative = call.argument<String>("relativePath")
                    Thread {
                        var pending: android.net.Uri? = null
                        try {
                            require(Build.VERSION.SDK_INT >= 29) { "Downloads export requires Android 10 or newer" }
                            require(source != null && relative != null) { "Missing file path" }
                            val parts = relative.split('/')
                            require(parts.all { it.isNotBlank() && it != "." && it != ".." && !it.contains('\\') }) { "Invalid export path" }
                            val input = File(source)
                            require(input.isFile) { "Source file is missing" }
                            val directory = "Download/KOSMOS3D/" + parts.dropLast(1).joinToString("/")
                            val mime = android.webkit.MimeTypeMap.getSingleton()
                                .getMimeTypeFromExtension(input.extension.lowercase()) ?: "application/octet-stream"
                            val values = ContentValues().apply {
                                put(MediaStore.MediaColumns.DISPLAY_NAME, parts.last())
                                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                                put(MediaStore.MediaColumns.RELATIVE_PATH, directory)
                                put(MediaStore.MediaColumns.IS_PENDING, 1)
                            }
                            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                                ?: throw IllegalStateException("Could not create export")
                            pending = uri
                            contentResolver.openOutputStream(uri)?.use { output ->
                                input.inputStream().use { it.copyTo(output) }
                            } ?: throw IllegalStateException("Could not write export")
                            values.clear()
                            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                            contentResolver.update(uri, values, null, null)
                            pending = null
                            runOnUiThread { result.success(uri.toString()) }
                        } catch (e: Exception) {
                            pending?.let { contentResolver.delete(it, null, null) }
                            runOnUiThread { result.error("EXPORT_FAILED", e.message, null) }
                        }
                    }.start()
                }
                "openTetheringSettings" -> {
                    try {
                        val intent = Intent()
                        intent.action = "android.settings.TETHER_SETTINGS"
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val fallbackIntent = Intent(Settings.ACTION_WIRELESS_SETTINGS)
                            fallbackIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(fallbackIntent)
                            result.success(true)
                        } catch (e2: Exception) {
                            try {
                                val settingsIntent = Intent(Settings.ACTION_SETTINGS)
                                settingsIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(settingsIntent)
                                result.success(true)
                            } catch (e3: Exception) {
                                result.error("UNAVAILABLE", "Cannot open tethering settings", null)
                            }
                        }
                    }
                }
                "scanFileToGallery" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        MediaScannerConnection.scanFile(
                            this,
                            arrayOf(filePath),
                            null
                        ) { path, uri ->
                            // Scanned successfully
                        }
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "filePath is required", null)
                    }
                }
                "saveToDeviceGallery" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val albumName = call.argument<String>("albumName") ?: "KOSMOS3D"
                    if (sourcePath != null) {
                        Thread {
                            var pendingUri: android.net.Uri? = null
                            try {
                                val srcFile = File(sourcePath)
                                require(srcFile.isFile) { "Source file does not exist" }
                                require(albumName.matches(Regex("[A-Za-z0-9_-]+"))) { "Invalid album" }
                                val mime = when (srcFile.extension.lowercase()) {
                                    "mp4" -> "video/mp4"
                                    "jpg", "jpeg" -> "image/jpeg"
                                    "gpr" -> "image/x-adobe-dng"
                                    else -> throw IllegalArgumentException("Unsupported gallery media type")
                                }
                                val saved: String
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                    val collection = if (mime.startsWith("video/")) MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                                        else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                                    val values = ContentValues().apply {
                                        put(MediaStore.MediaColumns.DISPLAY_NAME, srcFile.name)
                                        put(MediaStore.MediaColumns.MIME_TYPE, mime)
                                        put(MediaStore.MediaColumns.RELATIVE_PATH, "DCIM/$albumName")
                                        put(MediaStore.MediaColumns.IS_PENDING, 1)
                                    }
                                    val uri = contentResolver.insert(collection, values)
                                        ?: throw IllegalStateException("Could not create gallery entry")
                                    pendingUri = uri
                                    contentResolver.openOutputStream(uri)?.use { output ->
                                        srcFile.inputStream().use { input -> input.copyTo(output) }
                                    } ?: throw IllegalStateException("Could not open gallery entry")
                                    values.clear()
                                    values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                                    contentResolver.update(uri, values, null, null)
                                    saved = uri.toString()
                                    pendingUri = null
                                } else {
                                    val dcimDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM), albumName)
                                    if (!dcimDir.exists() && !dcimDir.mkdirs()) throw IllegalStateException("Could not create album")
                                    val destination = File(dcimDir, srcFile.name)
                                    srcFile.inputStream().use { input -> destination.outputStream().use { output -> input.copyTo(output) } }
                                    MediaScannerConnection.scanFile(this, arrayOf(destination.absolutePath), arrayOf(mime), null)
                                    saved = destination.absolutePath
                                }
                                runOnUiThread { result.success(saved) }
                            } catch (e: Exception) {
                                pendingUri?.let { contentResolver.delete(it, null, null) }
                                runOnUiThread { result.error("COPY_FAILED", e.message, null) }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "sourcePath is required", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
