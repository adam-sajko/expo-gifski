package expo.modules.gifski

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import uniffi.expo_gifski.GifskiException
import uniffi.expo_gifski.GifskiOptions
import uniffi.expo_gifski.GifskiProgress
import uniffi.expo_gifski.GifskiProgressCallback as UniffiProgressCallback
import uniffi.expo_gifski.encodeGif as uniffiEncodeGif
import uniffi.expo_gifski.getModuleVersion as uniffiGetModuleVersion
import uniffi.expo_gifski.getGifskiVersion as uniffiGetGifskiVersion
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class ExpoGifskiModule : Module() {

  private val mainHandler = Handler(Looper.getMainLooper())

  override fun definition() = ModuleDefinition {
    Name("ExpoGifski")

    Events("onProgress")

    AsyncFunction("encodeGifFromVideo") { videoUri: String, outputPath: String, options: Map<String, Any?> ->
      encodeGifFromVideo(videoUri, outputPath, options)
    }

    Function("getModuleVersion") {
      uniffiGetModuleVersion()
    }

    Function("getGifskiVersion") {
      uniffiGetGifskiVersion()
    }
  }

  private fun makeProgressCallback(): UniffiProgressCallback {
    return object : UniffiProgressCallback {
      override fun onProgress(progress: GifskiProgress) {
        mainHandler.post {
          sendEvent("onProgress", mapOf(
            "framesProcessed" to progress.framesProcessed.toInt(),
            "totalFrames" to progress.totalFrames.toInt(),
            "progress" to progress.progress
          ))
        }
      }
    }
  }

  private fun makeGifskiOptions(options: Map<String, Any?>, width: Int, height: Int): GifskiOptions {
    val quality = ((options["quality"] as? Number)?.toInt() ?: 90).coerceIn(1, 100)
    val repeat = (options["repeat"] as? Number)?.toInt() ?: -1
    return GifskiOptions(
      width = width.coerceAtLeast(0).toUInt(),
      height = height.coerceAtLeast(0).toUInt(),
      quality = quality.toUByte(),
      repeat = repeat,
      fast = options["fast"] as? Boolean ?: false,
      fps = ((options["fps"] as? Number)?.toDouble() ?: 10.0).toFloat()
    )
  }

  private fun resolveFilePath(uriOrPath: String): String {
    if (uriOrPath.startsWith("file://")) {
      return Uri.parse(uriOrPath).path ?: uriOrPath
    }
    return uriOrPath
  }

  private fun resizeBitmapAspectFill(bitmap: Bitmap, targetWidth: Int, targetHeight: Int): Bitmap {
    if (bitmap.width == targetWidth && bitmap.height == targetHeight) {
      return bitmap
    }

    val widthRatio = targetWidth.toFloat() / bitmap.width
    val heightRatio = targetHeight.toFloat() / bitmap.height
    val scale = max(widthRatio, heightRatio)

    val scaledWidth = (bitmap.width * scale).roundToInt()
    val scaledHeight = (bitmap.height * scale).roundToInt()

    val result = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(result)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

    val offsetX = (targetWidth - scaledWidth) / 2f
    val offsetY = (targetHeight - scaledHeight) / 2f

    val matrix = Matrix()
    matrix.postScale(scale, scale)
    matrix.postTranslate(offsetX, offsetY)

    canvas.drawBitmap(bitmap, matrix, paint)
    return result
  }

  private fun encodeGifFromVideo(
    videoUri: String,
    outputPath: String,
    options: Map<String, Any?>
  ): String {
    val context = appContext.reactContext ?: throw IllegalStateException("React context is not available")
    val resolvedOutput = resolveFilePath(outputPath)

    val fps = (options["fps"] as? Number)?.toDouble() ?: 10.0
    val startTime = (options["startTime"] as? Number)?.toDouble() ?: 0.0
    val requestedDuration = (options["duration"] as? Number)?.toDouble()
    val userWidth = (options["width"] as? Number)?.toInt() ?: 0
    val userHeight = (options["height"] as? Number)?.toInt() ?: 0

    val retriever = MediaMetadataRetriever()
    val tempPngPaths = mutableListOf<String>()

    try {
      val resolvedVideo = resolveFilePath(videoUri)
      if (resolvedVideo.startsWith("/")) {
        retriever.setDataSource(resolvedVideo)
      } else {
        retriever.setDataSource(context, Uri.parse(videoUri))
      }

      val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
        ?.toLongOrNull() ?: throw IllegalArgumentException("Could not determine video duration")
      val videoDurationSec = durationMs / 1000.0

      val duration = minOf(
        requestedDuration ?: (videoDurationSec - startTime),
        videoDurationSec - startTime
      )

      if (duration <= 0) {
        throw IllegalArgumentException("Invalid time range: startTime=$startTime exceeds video duration=$videoDurationSec")
      }

      Log.i("ExpoGifski", "Video: duration=${videoDurationSec}s, extracting from ${startTime}s for ${duration}s at ${fps} fps")

      val targetWidth: Int
      val targetHeight: Int
      if (userWidth > 0 && userHeight > 0) {
        targetWidth = userWidth
        targetHeight = userHeight
      } else {
        val videoWidth = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
          ?.toIntOrNull() ?: 480
        val videoHeight = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
          ?.toIntOrNull() ?: 360
        val maxDim = 800
        if (videoWidth > maxDim || videoHeight > maxDim) {
          val scale = minOf(maxDim.toDouble() / videoWidth, maxDim.toDouble() / videoHeight)
          targetWidth = (videoWidth * scale).roundToInt()
          targetHeight = (videoHeight * scale).roundToInt()
        } else {
          targetWidth = videoWidth
          targetHeight = videoHeight
        }
      }

      Log.i("ExpoGifski", "Target frame size: ${targetWidth}x${targetHeight}")

      val frameInterval = 1.0 / fps
      val frameCount = ((duration / frameInterval).toInt())

      Log.i("ExpoGifski", "Extracting $frameCount frames from video")

      val tmpDir = context.cacheDir
      for (index in 0 until frameCount) {
        val timestamp = startTime + index.toDouble() * frameInterval
        val timeUs = (timestamp * 1_000_000).toLong()
        val bitmap = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
        if (bitmap == null) {
          Log.w("ExpoGifski", "Frame $index (t=${timestamp}s): failed to extract")
          continue
        }

        val scaledBitmap = resizeBitmapAspectFill(bitmap, targetWidth, targetHeight)
        if (scaledBitmap !== bitmap) bitmap.recycle()

        val tmpFile = File(tmpDir, "expo_gifski_${UUID.randomUUID()}.png")
        try {
          FileOutputStream(tmpFile).use { out ->
            scaledBitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
          }
          tempPngPaths.add(tmpFile.absolutePath)
        } catch (e: Exception) {
          Log.w("ExpoGifski", "Frame $index: failed to write temp PNG - ${e.message}")
        } finally {
          scaledBitmap.recycle()
        }
      }

      if (tempPngPaths.isEmpty()) {
        throw IllegalArgumentException("Failed to extract any frames from video")
      }

      Log.i("ExpoGifski", "Extracted ${tempPngPaths.size} frames, encoding GIF...")

      val gifskiOptions = makeGifskiOptions(options, targetWidth, targetHeight)
      try {
        uniffiEncodeGif(
          inputPaths = tempPngPaths,
          outputPath = resolvedOutput,
          options = gifskiOptions,
          progressCallback = makeProgressCallback()
        )
      } catch (e: GifskiException) {
        throw Exception("Failed to encode GIF from video: $e")
      } catch (e: Exception) {
        throw Exception("Unexpected error during GIF encoding: ${e.message}")
      }

      return resolvedOutput
    } finally {
      retriever.release()
      for (path in tempPngPaths) {
        try { File(path).delete() } catch (_: Exception) {}
      }
    }
  }
}
