package com.loksewasolutionnp.hub

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

/// Hosts the tiny "loksewa_solution/media" channel used by
/// [ScreenshotPicker.pickImage] (report-a-problem screenshot attach),
/// [ScreenshotPicker.captureImage] (edit-profile photo capture) and the
/// profile tab's Rate Us popup.
///
/// No `image_picker`/`url_launcher` plugins are used on purpose
/// (dependency-free build), so this wires the system intents directly:
/// - "pickImage": ACTION_OPEN_DOCUMENT with `image/*`.
/// - "captureImage": ACTION_IMAGE_CAPTURE writing to a FileProvider URI in the
///   app cache (no CAMERA permission needed — the camera app writes to our
///   URI; the FileProvider is declared in AndroidManifest.xml).
/// - "openUrl": ACTION_VIEW with the `url` argument string.
/// Both pickers return the image downscaled to ≤1600px as JPEG bytes (or null
/// when the user cancels); openUrl answers true on success.
class MainActivity : FlutterActivity() {

    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingCaptureFile: File? = null

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
                    "captureImage" -> {
                        if (pendingPickResult != null) {
                            result.error("BUSY", "Another pick is already in progress", null)
                        } else {
                            val photoFile = try {
                                File.createTempFile("capture_", ".jpg", cacheDir)
                            } catch (_: Exception) {
                                result.error("NO_CACHE", "Could not create a temp file", null)
                                return@setMethodCallHandler
                            }
                            try {
                                val uri = FileProvider.getUriForFile(
                                    this, "$packageName.fileprovider", photoFile)
                                pendingCaptureFile = photoFile
                                pendingPickResult = result
                                val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                                    putExtra(MediaStore.EXTRA_OUTPUT, uri)
                                    addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                                }
                                startActivityForResult(intent, CAPTURE_IMAGE_REQUEST)
                            } catch (_: Exception) {
                                // No camera app, or the FileProvider is misconfigured.
                                pendingCaptureFile = null
                                pendingPickResult = null
                                photoFile.delete()
                                result.error("NO_CAMERA", "Could not launch the camera", null)
                            }
                        }
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("BAD_URL", "Missing url argument", null)
                        } else {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (_: Exception) {
                                result.error("NO_HANDLER", "No app can open this link", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Kept for the framework-Activity picker flow")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_IMAGE_REQUEST && requestCode != CAPTURE_IMAGE_REQUEST) return
        val result = pendingPickResult
        pendingPickResult = null
        if (requestCode == CAPTURE_IMAGE_REQUEST) {
            val file = pendingCaptureFile
            pendingCaptureFile = null
            if (resultCode == RESULT_OK && file != null && file.exists()) {
                result?.success(readDownscaledJpegFile(file))
            } else {
                result?.success(null)
            }
            file?.delete()
            return
        }
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
            val bmp = decodeDownscaled(bounds) { opts ->
                contentResolver.openInputStream(uri)?.use {
                    BitmapFactory.decodeStream(it, null, opts)
                }
            } ?: return null
            jpegBytes(bmp)
        } catch (_: Exception) {
            null
        }
    }

    private fun readDownscaledJpegFile(file: File): ByteArray? {
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.absolutePath, bounds)
            val bmp = decodeDownscaled(bounds) { opts ->
                BitmapFactory.decodeFile(file.absolutePath, opts)
            } ?: return null
            jpegBytes(bmp)
        } catch (_: Exception) {
            null
        }
    }

    private fun decodeDownscaled(
        bounds: BitmapFactory.Options,
        decode: (BitmapFactory.Options) -> Bitmap?,
    ): Bitmap? {
        var sample = 1
        while (bounds.outWidth / sample > MAX_DIM || bounds.outHeight / sample > MAX_DIM) {
            sample *= 2
        }
        return decode(BitmapFactory.Options().apply { inSampleSize = sample })
    }

    private fun jpegBytes(bmp: Bitmap): ByteArray {
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
        return out.toByteArray()
    }

    companion object {
        private const val PICK_IMAGE_REQUEST = 0x10C4
        private const val CAPTURE_IMAGE_REQUEST = 0x10C5
        private const val MAX_DIM = 1600
        private const val JPEG_QUALITY = 85
    }
}
