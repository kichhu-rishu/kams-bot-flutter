package com.kamsbot.kams_bot

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {

    companion object {
        init { System.loadLibrary("llama_jni") }
        private const val METHOD_CHANNEL = "com.kamsbot/llama"
        private const val TOKEN_CHANNEL  = "com.kamsbot/llama_tokens"
        private const val PROGRESS_CHANNEL = "com.kamsbot/download_progress"
    }

    // Native methods
    private external fun nativeInit(modelPath: String): Long
    private external fun nativeGenerate(ctx: Long, prompt: String, callback: TokenCallback): Unit
    private external fun nativeFree(ctx: Long)

    interface TokenCallback { fun onToken(token: String) }

    private var nativeCtx: Long = 0
    private val mainHandler = Handler(Looper.getMainLooper())

    private var tokenSink: EventChannel.EventSink? = null
    private var progressSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isLoaded"  -> result.success(nativeCtx != 0L)
                    "hasModel"  -> result.success(modelFile().exists())
                    "downloadModel" -> {
                        val url = call.argument<String>("url")!!
                        thread { downloadModel(url); result.success(null) }
                    }
                    "loadModel" -> thread {
                        nativeCtx = nativeInit(modelFile().absolutePath)
                        mainHandler.post { result.success(nativeCtx != 0L) }
                    }
                    "generate" -> {
                        val prompt = call.argument<String>("prompt")!!
                        thread {
                            nativeGenerate(nativeCtx, prompt, object : TokenCallback {
                                override fun onToken(token: String) {
                                    mainHandler.post { tokenSink?.success(token) }
                                }
                            })
                            mainHandler.post { tokenSink?.success("[DONE]") }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, TOKEN_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) { tokenSink = sink }
                override fun onCancel(args: Any?) { tokenSink = null }
            })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PROGRESS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) { progressSink = sink }
                override fun onCancel(args: Any?) { progressSink = null }
            })
    }

    private fun modelFile(): File =
        File(filesDir, "model.gguf").takeIf { it.exists() }
            ?: File(getExternalFilesDir(null), "model.gguf")

    private fun downloadModel(urlStr: String) {
        val dest = File(filesDir, "model.gguf.tmp")
        var conn = URL(urlStr).openConnection() as HttpURLConnection
        conn.instanceFollowRedirects = false
        // Follow redirects manually (HuggingFace uses multi-hop)
        var location = urlStr
        repeat(5) {
            conn = URL(location).openConnection() as HttpURLConnection
            conn.instanceFollowRedirects = false
            conn.connect()
            if (conn.responseCode in 300..399) {
                location = conn.getHeaderField("Location") ?: return
            }
        }
        val total = conn.contentLengthLong
        var downloaded = 0L
        conn.inputStream.use { input ->
            dest.outputStream().use { output ->
                val buf = ByteArray(8192)
                var n: Int
                while (input.read(buf).also { n = it } != -1) {
                    output.write(buf, 0, n)
                    downloaded += n
                    if (total > 0) {
                        mainHandler.post { progressSink?.success(downloaded.toDouble() / total) }
                    }
                }
            }
        }
        dest.renameTo(File(filesDir, "model.gguf"))
        mainHandler.post {
            progressSink?.success(1.0)
            nativeCtx = nativeInit(File(filesDir, "model.gguf").absolutePath)
        }
    }
}
