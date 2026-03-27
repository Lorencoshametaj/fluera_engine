package com.flueraengine.fluera_engine

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.json.JSONObject
import org.pytorch.IValue
import org.pytorch.LiteModuleLoader
import org.pytorch.Module
import org.pytorch.Tensor
import java.io.File
import java.io.FileOutputStream

/**
 * 🧮 LatexRecognizerPlugin — Android native module for LaTeX recognition.
 *
 * Uses PyTorch Mobile to run pix2tex encoder+decoder on-device.
 *
 * Pipeline:
 * 1. Decode PNG → Bitmap
 * 2. Resize via resizer.ptl
 * 3. Encode via encoder.ptl → feature tensor
 * 4. Decode autoregressively via decoder.ptl → token IDs
 * 5. Convert token IDs → LaTeX string via vocab.json
 *
 * Channel: `fluera_engine/latex_recognition`
 */
class LatexRecognizerPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private var context: Context? = null

    // PyTorch Mobile modules
    private var encoderModule: Module? = null
    private var decoderModule: Module? = null
    private var resizerModule: Module? = null

    // Vocabulary: token ID → LaTeX string
    private var vocab: Map<Int, String> = emptyMap()
    private var bosToken: Int = 1
    private var eosToken: Int = 2
    private var maxSeqLen: Int = 512

    private var isInitialized = false

    companion object {
        private const val TAG = "LatexRecognizer"
        private const val CHANNEL_NAME = "fluera_engine/latex_recognition"
        private const val ENCODER_HEIGHT = 192
        private const val ENCODER_WIDTH = 672
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        context = binding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> handleInitialize(result)
            "recognize" -> {
                val imageBytes = call.argument<ByteArray>("imageBytes")
                if (imageBytes == null) {
                    result.error("INVALID_ARGS", "Missing imageBytes argument", null)
                    return
                }
                Thread { handleRecognize(imageBytes, result) }.start()
            }
            "dispose" -> handleDispose(result)
            else -> result.notImplemented()
        }
    }

    // ─── Initialize ───────────────────────────────────────────────────────

    private fun handleInitialize(result: Result) {
        if (isInitialized) {
            result.success(mapOf("available" to (encoderModule != null)))
            return
        }

        try {
            val ctx = context ?: throw IllegalStateException("Context is null")

            // Load PyTorch Lite models from Flutter assets
            encoderModule = loadModule(ctx, "encoder.ptl")
            decoderModule = loadModule(ctx, "decoder.ptl")
            resizerModule = loadModule(ctx, "resizer.ptl")

            // Load vocabulary
            loadVocab(ctx)

            isInitialized = true
            val available = encoderModule != null && decoderModule != null
            Log.i(TAG, "Initialized: encoder=${encoderModule != null}, " +
                    "decoder=${decoderModule != null}, " +
                    "resizer=${resizerModule != null}, vocab=${vocab.size} tokens")
            result.success(mapOf("available" to available))
        } catch (e: Exception) {
            Log.e(TAG, "Initialization failed", e)
            isInitialized = true
            result.success(mapOf("available" to false))
        }
    }

    // ─── Recognize ────────────────────────────────────────────────────────

    private fun handleRecognize(imageBytes: ByteArray, result: Result) {
        val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
        try {
            if (encoderModule == null || decoderModule == null) {
                mainHandler.post { result.error("NOT_AVAILABLE", "ML model not loaded", null) }
                return
            }

            val startTime = System.currentTimeMillis()
            Log.i(TAG, "⏱ Step 0: Starting inference (${imageBytes.size} bytes)")

            // 1. Decode PNG → grayscale float tensor
            val imageTensor = preprocessImage(imageBytes)
            Log.i(TAG, "⏱ Step 1: Preprocessed in ${System.currentTimeMillis() - startTime}ms")

            // 2. Encode → features
            val t2 = System.currentTimeMillis()
            val features = encoderModule!!.forward(IValue.from(imageTensor)).toTensor()
            Log.i(TAG, "⏱ Step 2: Encoder forward in ${System.currentTimeMillis() - t2}ms, " +
                    "features shape=${features.shape().contentToString()}")

            // 3. Autoregressive decode → token IDs
            // Early stopping heuristics for traced models (no KV-cache):
            //   - Max 128 tokens (practical limit for formulas)
            //   - Repetition detection: stop if same token 4+ times in a row
            //   - Timeout: 10 seconds max for decoding
            val tokenIds = mutableListOf(bosToken)
            val tokenConfidences = mutableListOf<Float>()
            val t3 = System.currentTimeMillis()
            val decoderTimeout = 10_000L // 10 seconds max
            val maxTokens = 128
            var consecutiveRepeat = 0
            var lastToken = -1

            for (step in 0 until maxTokens) {
                // Timeout check
                if (System.currentTimeMillis() - t3 > decoderTimeout) {
                    Log.w(TAG, "⏱ Decoder timeout at step $step (${decoderTimeout}ms)")
                    break
                }

                // Build token tensor: shape [1, seq_len]
                val tokenArray = tokenIds.map { it.toLong() }.toLongArray()
                val tokenTensor = Tensor.fromBlob(tokenArray, longArrayOf(1, tokenArray.size.toLong()))

                // Run decoder step: (tokens, features) → logits [1, vocab_size]
                val logits = decoderModule!!.forward(
                    IValue.from(tokenTensor),
                    IValue.from(features)
                ).toTensor()

                val logitsData = logits.dataAsFloatArray

                // Apply softmax and get best token
                val probs = softmax(logitsData)
                val nextToken = probs.indices.maxByOrNull { probs[it] } ?: eosToken
                val confidence = probs[nextToken]

                if (step < 5 || step % 10 == 0) {
                    Log.i(TAG, "⏱ Step 3.$step: token=$nextToken (${vocab[nextToken] ?: "?"}), " +
                            "conf=${String.format("%.3f", confidence)}, " +
                            "elapsed=${System.currentTimeMillis() - t3}ms")
                }

                if (nextToken == eosToken) {
                    Log.i(TAG, "⏱ Step 3: EOS at step $step, decode took ${System.currentTimeMillis() - t3}ms")
                    break
                }

                // Repetition detection: stop if same token repeats 4+ times
                if (nextToken == lastToken) {
                    consecutiveRepeat++
                    if (consecutiveRepeat >= 3) {
                        Log.w(TAG, "⏱ Repetition detected at step $step (token=$nextToken repeated ${consecutiveRepeat + 1}x), stopping")
                        // Remove the repeated tokens from output
                        while (tokenIds.size > 1 && tokenIds.last() == nextToken) {
                            tokenIds.removeAt(tokenIds.lastIndex)
                            if (tokenConfidences.isNotEmpty()) tokenConfidences.removeAt(tokenConfidences.lastIndex)
                        }
                        break
                    }
                } else {
                    consecutiveRepeat = 0
                }
                lastToken = nextToken

                tokenIds.add(nextToken)
                tokenConfidences.add(confidence)
            }

            // 4. Decode tokens → LaTeX string
            val latex = tokenIds
                .drop(1) // skip BOS
                .mapNotNull { vocab[it] }
                .joinToString("")

            // 5. Calculate overall confidence
            val overallConfidence = if (tokenConfidences.isEmpty()) 0.0
                else tokenConfidences.map { it.toDouble() }.average()

            val inferenceTime = System.currentTimeMillis() - startTime
            Log.i(TAG, "✅ Inference completed in ${inferenceTime}ms: $latex (conf=${String.format("%.3f", overallConfidence)})")

            // Return result on main thread
            mainHandler.post {
                result.success(mapOf(
                    "latex" to latex,
                    "confidence" to overallConfidence,
                    "alternatives" to emptyList<Map<String, Any>>(),
                    "inferenceTimeMs" to inferenceTime
                ))
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Recognition failed: ${e.message}", e)
            mainHandler.post {
                result.error("INFERENCE_ERROR", "Inference failed: ${e.message}", null)
            }
        }
    }

    // ─── Dispose ──────────────────────────────────────────────────────────

    private fun handleDispose(result: Result) {
        encoderModule?.destroy()
        decoderModule?.destroy()
        resizerModule?.destroy()
        encoderModule = null
        decoderModule = null
        resizerModule = null
        vocab = emptyMap()
        isInitialized = false
        Log.i(TAG, "Disposed")
        result.success(null)
    }

    // ─── Helpers ──────────────────────────────────────────────────────────

    /**
     * Load a PyTorch Lite module from Flutter assets.
     * Copies the asset to the app's files directory first (required by PyTorch).
     */
    private fun loadModule(ctx: Context, filename: String): Module? {
        return try {
            // Flutter plugin assets are under packages/<package_name>/ prefix
            val assetPaths = listOf(
                "flutter_assets/packages/fluera_engine/assets/models/pix2tex/$filename",
                "flutter_assets/assets/models/pix2tex/$filename"
            )
            
            val destFile = File(ctx.filesDir, "pix2tex_$filename")

            // Copy asset to file system if not already done
            if (!destFile.exists()) {
                var loaded = false
                for (path in assetPaths) {
                    try {
                        ctx.assets.open(path).use { input ->
                            FileOutputStream(destFile).use { output ->
                                input.copyTo(output)
                            }
                        }
                        loaded = true
                        Log.i(TAG, "Loaded asset from: $path")
                        break
                    } catch (e2: Exception) {
                        // Try next path
                    }
                }
                if (!loaded) {
                    Log.w(TAG, "Asset not found at any path: $filename")
                    return null
                }
            }

            LiteModuleLoader.load(destFile.absolutePath)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load module $filename: ${e.message}")
            null
        }
    }

    /**
     * Load vocabulary (id → token) from Flutter assets.
     */
    private fun loadVocab(ctx: Context) {
        try {
            val vocabPaths = listOf(
                "flutter_assets/packages/fluera_engine/assets/models/pix2tex/vocab.json",
                "flutter_assets/assets/models/pix2tex/vocab.json"
            )
            var jsonStr: String? = null
            for (path in vocabPaths) {
                try {
                    jsonStr = ctx.assets.open(path).bufferedReader().readText()
                    break
                } catch (e2: Exception) { }
            }
            if (jsonStr != null) {
                val jsonObj = JSONObject(jsonStr)
                val map = mutableMapOf<Int, String>()
                jsonObj.keys().forEach { key ->
                    map[key.toInt()] = jsonObj.getString(key)
                }
                vocab = map
            }

            // Load config
            val configPaths = listOf(
                "flutter_assets/packages/fluera_engine/assets/models/pix2tex/config.json",
                "flutter_assets/assets/models/pix2tex/config.json"
            )
            for (path in configPaths) {
                try {
                    val configStr = ctx.assets.open(path).bufferedReader().readText()
                    val config = JSONObject(configStr)
                    bosToken = config.optInt("bos_token", 1)
                    eosToken = config.optInt("eos_token", 2)
                    maxSeqLen = config.optInt("max_seq_len", 512)
                    break
                } catch (e2: Exception) { }
            }

            Log.i(TAG, "Vocab loaded: ${vocab.size} tokens, BOS=$bosToken, EOS=$eosToken")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load vocab: ${e.message}")
        }
    }

    /**
     * Preprocess a PNG image into a grayscale float tensor [1, 1, H, W].
     */
    private fun preprocessImage(pngBytes: ByteArray): Tensor {
        // Decode PNG
        val bitmap = BitmapFactory.decodeByteArray(pngBytes, 0, pngBytes.size)
            ?: throw IllegalArgumentException("Could not decode image")

        // Resize to encoder input dimensions
        val resized = Bitmap.createScaledBitmap(bitmap, ENCODER_WIDTH, ENCODER_HEIGHT, true)

        // Convert to grayscale float array [0, 1]
        val pixels = IntArray(ENCODER_WIDTH * ENCODER_HEIGHT)
        resized.getPixels(pixels, 0, ENCODER_WIDTH, 0, 0, ENCODER_WIDTH, ENCODER_HEIGHT)

        val floatArray = FloatArray(ENCODER_WIDTH * ENCODER_HEIGHT)
        for (i in pixels.indices) {
            val pixel = pixels[i]
            val r = (pixel shr 16) and 0xFF
            val g = (pixel shr 8) and 0xFF
            val b = pixel and 0xFF
            // Convert to grayscale and normalize to [0, 1]
            floatArray[i] = (0.299f * r + 0.587f * g + 0.114f * b) / 255f
        }

        // Clean up
        if (resized != bitmap) resized.recycle()
        bitmap.recycle()

        return Tensor.fromBlob(
            floatArray,
            longArrayOf(1, 1, ENCODER_HEIGHT.toLong(), ENCODER_WIDTH.toLong())
        )
    }

    /**
     * Compute softmax over logits.
     */
    private fun softmax(logits: FloatArray): FloatArray {
        val maxVal = logits.maxOrNull() ?: 0f
        val exps = FloatArray(logits.size) { Math.exp((logits[it] - maxVal).toDouble()).toFloat() }
        val sum = exps.sum()
        return FloatArray(exps.size) { exps[it] / sum }
    }
}
