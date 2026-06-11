package com.example.qorange

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager as AndroidAudioManager // 🌟 核心修复一：重命名系统音频类，防范同名冲突
import android.os.Bundle
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import kotlin.concurrent.thread
import com.example.qorange.SessionManager
import com.example.qorange.TokenManager
import com.example.qorange.SesameWebSocket
import com.example.qorange.AudioPlayer
import com.example.qorange.AudioManager as LocalAudioManager // 🌟 核心修复二：重命名本地采集类，对齐包名并防范同名冲突

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL_CONTROL = "com.sesame.voicechat/control"
        private const val CHANNEL_EVENTS = "com.sesame.voicechat/events"
    }

    // 核心组件
    private var sesameWebSocket: SesameWebSocket? = null
    private var audioRecordManager: LocalAudioManager? = null
    private var audioPlayer: AudioPlayer? = null
    private var systemAudioManager: AndroidAudioManager? = null // 使用系统音频别名
    private var tokenManager: TokenManager? = null
    private var sessionManager: SessionManager? = null

    // 状态
    private var isConnected = false
    private var isMuted = false
    private var currentSession: SessionManager.SessionState? = null
    private var audioProcessingThread: Thread? = null

    private val mainScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var eventSink: EventChannel.EventSink? = null

    enum class AudioRoute {
        AUTO, SPEAKER, EARPIECE, WIRED_HEADSET, BLUETOOTH
    }
    private var currentAudioRoute = AudioRoute.AUTO

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 🌟 使用系统音频服务并强转为别名类
        systemAudioManager = getSystemService(Context.AUDIO_SERVICE) as AndroidAudioManager
        setupManagers()

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_CONTROL).setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> {
                    val contactName = call.argument<String>("contactName") ?: "Kira-EN"
                    val characterName = call.argument<String>("characterName") ?: "Kira"
                    val token = call.argument<String>("token")

                    if (hasRequiredPermissions()) {
                        connect(contactName, characterName, token)
                        result.success(true)
                    } else {
                        result.error("PERMISSION_DENIED", "Microphone permission is required", null)
                    }
                }
                "disconnect" -> {
                    disconnect()
                    result.success(true)
                }
                "toggleMute" -> {
                    toggleMute()
                    result.success(isMuted)
                }
                "setAudioRoute" -> {
                    val routeName = call.argument<String>("route") ?: "AUTO"
                    setAudioRoute(routeName)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setupManagers() {
        tokenManager = TokenManager(context)
        if (tokenManager != null) {
            sessionManager = SessionManager.getInstance(applicationContext, "Kira-EN", 3)
            sessionManager?.initialize(tokenManager!!)
        }
    }

    private fun connect(contactName: String, characterName: String, token: String?) {
        if (isConnected) return

        sendEvent("status", "Connecting...")

        mainScope.launch {
            try {
                if (!token.isNullOrEmpty()) {
                    tokenManager?.storeTokens(token, "")
                }

                val mgr = SessionManager.getInstance(applicationContext, contactName, 3)
                if (tokenManager != null) mgr.initialize(tokenManager!!)

                // 等待会话建立
                var sessionState: SessionManager.SessionState? = null
                var attempts = 0
                val maxAttempts = 30

                while (attempts < maxAttempts) {
                    sessionState = mgr.getBestAvailableSession(contactName)
                    if (sessionState != null) break

                    delay(500)
                    attempts++
                }

                if (sessionState == null) {
                    sendEvent("error", "Timeout: Failed to connect.")
                    return@launch
                }

                currentSession = sessionState
                sessionManager = mgr
                sesameWebSocket = sessionState.webSocket

                sessionState.webSocket.apply {
                    onConnectCallback = {
                        mainScope.launch { onWebSocketConnected() }
                    }
                    onDisconnectCallback = {
                        mainScope.launch { onWebSocketDisconnected() }
                    }
                    onErrorCallback = { error ->
                        mainScope.launch {
                            Log.e(TAG, "WebSocket Error: $error")
                            sendEvent("error", error)
                        }
                    }
                }

                Log.i(TAG, "Session ready immediately (No Cooking). Starting audio...")

                // 立即触发连接成功事件并启动音频
                sendEvent("init_progress", 100)
                sendEvent("status", "Ready")
                onWebSocketConnected()

            } catch (e: Exception) {
                Log.e(TAG, "Connection error", e)
                sendEvent("error", "Connection failed: ${e.message}")
            }
        }
    }

    private fun onWebSocketConnected() {
        isConnected = true
        sendEvent("status", "Connected")
        if (audioRecordManager == null) {
            setupAudio(startPlaybackImmediately = true)
        }
    }

    private fun onWebSocketDisconnected() {
        if (isConnected) {
            disconnect()
        }
    }

    private fun disconnect() {
        sendEvent("status", "Disconnecting...")
        audioRecordManager?.stopRecording()
        audioPlayer?.stopPlayback()
        isConnected = false
        currentSession?.let { session ->
            sessionManager?.removeSession(session)
        }
        audioRecordManager = null
        audioPlayer = null
        sesameWebSocket = null
        currentSession = null
        resetAudioRouting()
        sendEvent("status", "Disconnected")
    }

    private fun setupAudio(startPlaybackImmediately: Boolean) {
        try {
            val isCarMode = isRunningInCar()
            applyAudioRouting()

            val sampleRate = sesameWebSocket?.serverSampleRate ?: 24000
            audioPlayer = AudioPlayer(sampleRate).apply {
                onErrorCallback = { error ->
                    mainScope.launch { sendEvent("error", "Playback: $error") }
                }
            }

            if (startPlaybackImmediately) {
                audioPlayer?.startPlayback()
            }

            audioRecordManager = LocalAudioManager().apply {
                adjustForCarMode(isCarMode)
                setDebugMode(false)
                onAudioDataCallback = { audioData, hasVoice ->
                    // 🌟 1. 如果已连接 Sesame AI 助手，正常进行网络发送 [2]
                    if (isConnected) {
                        if (hasVoice) {
                            sesameWebSocket?.sendAudioData(audioData)
                        } else {
                            val silentData = ByteArray(audioData.size) { 0 }
                            sesameWebSocket?.sendAudioData(silentData)
                        }
                    }

                    // 🌟 2. 核心联动：将 VAD 状态与麦克风原始 PCM 字节流打包，统一抛回给 Flutter EventChannel 订阅，
                    // 无论当前是否建立了 Sesame 通信，实时同传翻译流（TranslateStreamController）都能以此获取高频声波！ [2]
                    sendEvent("voice_activity", mapOf(
                        "hasVoice" to hasVoice,
                        "audio_data" to audioData
                    ))
                }
                onErrorCallback = { error ->
                    mainScope.launch { sendEvent("error", "Recording: $error") }
                }
            }

            if (audioRecordManager?.startRecording() == true) {
                startAudioProcessing()
            } else {
                sendEvent("error", "Failed to start microphone")
            }

        } catch (e: Exception) {
            Log.e(TAG, "Audio setup error", e)
            sendEvent("error", "Audio setup failed: ${e.message}")
        }
    }


    //uuu
    // 🌟 请在 MainActivity.kt 寻找 startAudioProcessing() 方法，将其 100% 完整替换为如下代码：
    private fun startAudioProcessing() {
        if (audioProcessingThread != null && audioProcessingThread!!.isAlive) return
        audioProcessingThread = thread {
            while (isConnected && sesameWebSocket?.isConnected() == true) {
                try {
                    val audioChunk = sesameWebSocket?.getNextAudioChunk()
                    if (audioChunk != null) {
                        // 1. 正常送入 AudioTrack 播放器播放声音
                        audioPlayer?.queueAudioData(audioChunk)

                        // 2. 🌟 核心：将 24000Hz 的 AI 声音重采样为 16000Hz 并通过事件通道实时抛给 Flutter 用于同传翻译！ [2]
                        val resampledAudio = resample24to16(audioChunk)
                        sendEvent("ai_audio_data", resampledAudio)
                    } else {
                        val delayMs = if (isRunningInCar()) 5L else 2L
                        Thread.sleep(delayMs)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Audio processing loop error", e)
                    break
                }
            }
        }
    }

    // 🌟 新增：将 AI 播放器的 24000Hz 原始 PCM 降频重采样为 16000Hz 规范数据（3:2 物理缩放） [2]
    private fun resample24to16(input: ByteArray): ByteArray {
        val inputSamples = input.size / 2
        val outputSamples = (inputSamples * 2) / 3
        val output = ByteArray(outputSamples * 2)

        var outIdx = 0
        for (i in 0 until outputSamples) {
            val srcIdx = (i * 3) / 2
            if (srcIdx * 2 + 1 < input.size && outIdx + 1 < output.size) {
                output[outIdx] = input[srcIdx * 2]
                output[outIdx + 1] = input[srcIdx * 2 + 1]
                outIdx += 2
            }
        }
        return output
    }

    private fun setCommunicationDeviceCompat(deviceType: Int): Boolean {
        val audioManager = systemAudioManager ?: return false
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            val devices = audioManager.availableCommunicationDevices
            for (device in devices) {
                if (device.type == deviceType) {
                    audioManager.clearCommunicationDevice()
                    return audioManager.setCommunicationDevice(device)
                }
            }
        }
        return false
    }

    private fun clearCommunicationDeviceCompat() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            systemAudioManager?.clearCommunicationDevice()
        }
    }

    private fun applyAudioRouting() {
        systemAudioManager?.let { audioManager ->
            // 🌟 核心别名调用：Android 原始系统 MODE 绑定
            audioManager.mode = AndroidAudioManager.MODE_IN_COMMUNICATION

            when (currentAudioRoute) {
                AudioRoute.SPEAKER -> {
                    val success = setCommunicationDeviceCompat(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
                    if (!success) {
                        @Suppress("DEPRECATION")
                        audioManager.isSpeakerphoneOn = true
                    }
                    audioManager.stopBluetoothSco()
                }
                AudioRoute.EARPIECE -> {
                    val success = setCommunicationDeviceCompat(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)
                    if (!success) {
                        @Suppress("DEPRECATION")
                        audioManager.isSpeakerphoneOn = false
                    }
                    audioManager.stopBluetoothSco()
                }
                AudioRoute.BLUETOOTH -> {
                    val success = setCommunicationDeviceCompat(AudioDeviceInfo.TYPE_BLUETOOTH_SCO)
                    if (!success) {
                        @Suppress("DEPRECATION")
                        audioManager.isSpeakerphoneOn = false
                        audioManager.startBluetoothSco()
                        @Suppress("DEPRECATION")
                        audioManager.isBluetoothScoOn = true
                    }
                }
                AudioRoute.WIRED_HEADSET -> {
                    val success = setCommunicationDeviceCompat(AudioDeviceInfo.TYPE_WIRED_HEADSET)
                    if (!success) {
                        @Suppress("DEPRECATION")
                        audioManager.isSpeakerphoneOn = false
                    }
                    audioManager.stopBluetoothSco()
                }
                AudioRoute.AUTO -> {
                    @Suppress("DEPRECATION")
                    if (audioManager.isBluetoothA2dpOn || audioManager.isBluetoothScoOn) {
                        val success = setCommunicationDeviceCompat(AudioDeviceInfo.TYPE_BLUETOOTH_SCO)
                        if (!success) {
                            audioManager.startBluetoothSco()
                            @Suppress("DEPRECATION")
                            audioManager.isBluetoothScoOn = true
                            audioManager.isSpeakerphoneOn = false
                        }
                    } else if (audioManager.isWiredHeadsetOn) {
                        val success = setCommunicationDeviceCompat(AudioDeviceInfo.TYPE_WIRED_HEADSET)
                        if (!success) {
                            audioManager.isSpeakerphoneOn = false
                        }
                    } else {
                        // 强制外放扬声器 [2]
                        val success = setCommunicationDeviceCompat(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
                        if (!success) {
                            @Suppress("DEPRECATION")
                            audioManager.isSpeakerphoneOn = true
                        }
                    }
                }
            }
        }
    }

    private fun setAudioRoute(routeName: String) {
        currentAudioRoute = try {
            AudioRoute.valueOf(routeName)
        } catch (e: Exception) {
            AudioRoute.AUTO
        }
        applyAudioRouting()
    }

    private fun resetAudioRouting() {
        systemAudioManager?.let { audioManager ->
            audioManager.mode = AndroidAudioManager.MODE_NORMAL
            clearCommunicationDeviceCompat()
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = false
            audioManager.stopBluetoothSco()
            @Suppress("DEPRECATION")
            audioManager.isBluetoothScoOn = false
        }
    }

    private fun toggleMute() {
        isMuted = !isMuted
    }

    private fun sendEvent(type: String, value: Any) {
        mainScope.launch {
            val data = mapOf("type" to type, "value" to value)
            eventSink?.success(data)
        }
    }

    private fun hasRequiredPermissions(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    }

    private fun isRunningInCar(): Boolean {
        return packageManager.hasSystemFeature(PackageManager.FEATURE_AUTOMOTIVE)
    }

    override fun onDestroy() {
        super.onDestroy()
        disconnect()
        sessionManager?.shutdown()
        mainScope.cancel()
    }
}