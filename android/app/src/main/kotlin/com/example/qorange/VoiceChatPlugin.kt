package com.example.qorange

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import kotlin.concurrent.thread

class VoiceChatPlugin : FlutterPlugin, MethodCallHandler {

    companion object {
        private const val TAG = "VoiceChatPlugin"
        private const val CHANNEL_METHODS = "com.sesame.voicechat/methods"
        private const val CHANNEL_EVENTS = "com.sesame.voicechat/recordStream"
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel

    private var sesameWebSocket: SesameWebSocket? = null
    private var audioRecordManager: AudioManager? = null
    private var audioPlayer: AudioPlayer? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    private var isProcessingAudio = false

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_METHODS)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, CHANNEL_EVENTS)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "connect" -> {
                val idToken = call.argument<String>("idToken")
                val character = call.argument<String>("character") ?: "Miles"
                if (idToken != null) {
                    val success = connectSession(idToken, character)
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

    private fun connectSession(idToken: String, character: String): Boolean {
        Log.i(TAG, "Starting new session with $character...")

        sesameWebSocket = SesameWebSocket(idToken, character).apply {
            onConnectCallback = {
                Log.i(TAG, "WebSocket Connected! Starting Audio Engine...")
                startAudioEngine(this.serverSampleRate)
                notifyFlutter("status", "connected")
            }
            onDisconnectCallback = {
                Log.i(TAG, "WebSocket Disconnected")
                stopAudioEngine()
                notifyFlutter("status", "disconnected")
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
            eventSink?.success(mapOf("type" to type, "value" to message))
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        disconnectSession()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }
}