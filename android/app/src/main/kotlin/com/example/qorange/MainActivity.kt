package com.example.qorange

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread
import com.example.qorange.AudioManager
import com.example.qorange.AudioPlayer
import com.example.qorange.SesameWebSocket

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL_CONTROL = "com.sesame.voicechat/control"
        private const val CHANNEL_EVENTS = "com.sesame.voicechat/events"
    }

    private var sesameWebSocket: SesameWebSocket? = null
    private var audioRecordManager: AudioManager? = null
    private var audioPlayer: AudioPlayer? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    private var isProcessingAudio = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_CONTROL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> {
                        // 🌟 核心修复：移除了不合法的 'final' 关键字，Kotlin 中直接使用 val 声明只读变量即可
                        val token = call.argument<String>("token")
                        val characterName = call.argument<String>("characterName") ?: "Miles"
                        val contactName = call.argument<String>("contactName") ?: "Miles-EN"

                        if (token != null) {
                            val success = connectSession(token, characterName, contactName)
                            result.success(success)
                        } else {
                            result.error("INVALID_TOKEN", "Token is null", null)
                        }
                    }
                    "disconnect" -> {
                        disconnectSession()
                        result.success(true)
                    }
                    "setMute" -> {
                        val isMuted = call.argument<Boolean>("isMuted") ?: false
                        if (isMuted) {
                            audioRecordManager?.stopRecording()
                        } else {
                            audioRecordManager?.startRecording()
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    private fun connectSession(token: String, characterName: String, contactName: String): Boolean {
        Log.i(TAG, "Starting new session with $characterName ($contactName)...")

        sesameWebSocket = SesameWebSocket(token, characterName).apply {
            onConnectCallback = {
                Log.i(TAG, "WebSocket Connected! Starting Audio Engine...")
                startAudioEngine(this.serverSampleRate)
                notifyFlutter("status", "Connected")
            }
            onDisconnectCallback = {
                Log.i(TAG, "WebSocket Disconnected")
                stopAudioEngine()
                notifyFlutter("status", "Disconnected")
            }
            onErrorCallback = { error ->
                Log.e(TAG, "WebSocket Error: $error")
                notifyFlutter("error", error)
            }
        }

        return sesameWebSocket?.connect() ?: false
    }

    private fun startAudioEngine(sampleRate: Int) {
        if (audioPlayer == null) {
            audioPlayer = AudioPlayer(sampleRate)
        } else {
            audioPlayer?.updateSampleRate(sampleRate)
        }
        audioPlayer?.startPlayback()

        if (audioRecordManager == null) {
            audioRecordManager = AudioManager()
            audioRecordManager?.onAudioDataCallback = { data, hasVoice ->
                sesameWebSocket?.sendAudioData(data)

                mainHandler.post {
                    eventSink?.success(mapOf("type" to "voice_activity", "value" to hasVoice))
                }
            }
        }
        audioRecordManager?.startRecording()

        isProcessingAudio = true
        thread {
            Log.d(TAG, "Audio processing thread started")
            while (isProcessingAudio && sesameWebSocket?.isConnected() == true) {
                try {
                    val chunk = sesameWebSocket?.getNextAudioChunk()
                    if (chunk != null) {
                        audioPlayer?.queueAudioData(chunk)
                    } else {
                        Thread.sleep(10)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Audio loop error", e)
                }
            }
        }
    }

    private fun stopAudioEngine() {
        isProcessingAudio = false
        audioRecordManager?.stopRecording()
        audioPlayer?.stopPlayback()
        audioPlayer?.clearQueue()
    }

    private fun disconnectSession() {
        sesameWebSocket?.disconnect()
        stopAudioEngine()
        sesameWebSocket = null
        audioRecordManager = null
        audioPlayer = null
    }

    private fun notifyFlutter(type: String, message: Any) {
        mainHandler.post {
            val data = mapOf("type" to type, "value" to message)
            eventSink?.success(data)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        disconnectSession()
    }
}