package com.loksewasolutionnp.hub

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/// Hosts the tiny "loksewa_solution/media" channel used by
/// [ScreenshotPicker.pickImage] (report-a-problem screenshot attach).
///
/// No `image_picker` plugin is used on purpose (dependency-free build), so
/// this wires the system document picker directly: ACTION_OPEN_DOCUMENT with
/// `image/*`, then the picked image is downscaled to ≤1600px and returned to
/// Dart as JPEG bytes (or null when the user cancels).
class MainActivity : FlutterActivity() {

    private var pendingPickResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "loksewa_solution/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImage" -> {
                        if (pendingPickResult != null) {
                            result.error("BUSY", "Another pick is already in progress", null)
                        } else {
                            pendingPickResult = result
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                type = "image/*"
                                addCategory(Intent.CATEGORY_OPENABLE)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivityForResult(intent, PICK_IMAGE_REQUEST)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Kept for the framework-Activity picker flow")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_IMAGE_REQUEST) return
        val result = pendingPickResult
        pendingPickResult = null
        val uri: Uri? = if (resultCode == RESULT_OK) data?.data else null
        if (uri == null) {
            result?.success(null)
            return
        }
        result?.success(readDownscaledJpeg(uri))
    }

    private fun readDownscaledJpeg(uri: Uri): ByteArray? {
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, bounds)
            }
            var sample = 1
            while (bounds.outWidth / sample > MAX_DIM || bounds.outHeight / sample > MAX_DIM) {
                sample *= 2
            }
            val opts = BitmapFactory.Options().apply { inSampleSize = sample }
            val bmp = contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, opts)
            } ?: return null
            val out = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
            out.toByteArray()
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        private const val PICK_IMAGE_REQUEST = 0x10C4
        private const val MAX_DIM = 1600
        private const val JPEG_QUALITY = 85
    }
}
