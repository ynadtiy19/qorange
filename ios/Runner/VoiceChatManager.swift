import Foundation
import AVFoundation
import Flutter

// MARK: - Character Mapper (对齐 Android SessionManager)
class CharacterMapper {
    static func getBackendCharacter(_ name: String) -> String {
        let cleanName = name.components(separatedBy: "-").first ?? name
        switch cleanName.lowercased() {
        case "kira", "hugo", "maya":
            return "Maya"
        case "miles":
            return "Miles"
        case "simone":
            return "Simone"
        case "charlie":
            return "Charlie"
        default:
            return cleanName
        }
    }
}

// MARK: - AudioPlayer (对齐 Android AudioPlayer.kt)
/// 负责 PCM 音频流式播放、Jitter Buffer 缓冲控制、Float32 渲染及时钟同步
class AudioPlayer {
    private let tag = "AudioPlayer"
    
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    private var sampleRate: Double
    // AVAudioEngine 混合器节点底层严格要求 32-bit Float 格式
    private var floatAudioFormat: AVAudioFormat
    
    private let queueLock = NSLock()
    private var audioQueue: [Data] = []
    
    // Jitter Buffer 参数（与 Android 一致）
    private var minBufferSize = 5       // 触发起播门限
    private var targetBufferSize = 10   // 理想缓冲数
    private var maxBufferSize = 20      // 丢弃旧分片上限（控延迟）
    private var chunkDurationMs: Double = 0
    
    private var isPlaying = false
    private var playbackStarted = false
    private var expectedPlaybackTime: Double = 0
    
    var onErrorCallback: ((String) -> Void)?
    
    init(sampleRate: Int = 24000) {
        self.sampleRate = Double(sampleRate)
        self.floatAudioFormat = AVAudioFormat(standardFormatWithSampleRate: self.sampleRate, channels: 1)!
        calculateTimingParameters()
    }
    
    private func calculateTimingParameters() {
        let chunkSamples = 1024.0
        self.chunkDurationMs = (chunkSamples * 1000.0) / self.sampleRate
        let targetLatencyMs = 200.0
        let chunksForLatency = Int(targetLatencyMs / self.chunkDurationMs)
        
        self.minBufferSize = max(3, chunksForLatency / 3)
        self.targetBufferSize = max(5, chunksForLatency / 2)
        self.maxBufferSize = max(10, chunksForLatency)
    }
    
    func startPlayback() -> Bool {
        do {
            if !audioEngine.isRunning {
                audioEngine.attach(playerNode)
                audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: floatAudioFormat)
                audioEngine.prepare()
                try audioEngine.start()
            }
            
            isPlaying = true
            playbackStarted = false
            expectedPlaybackTime = 0
            
            startPlaybackLoop()
            return true
        } catch {
            onErrorCallback?("Failed to start audio engine: \(error.localizedDescription)")
            return false
        }
    }
    
    func stopPlayback() {
        isPlaying = false
        playbackStarted = false
        playerNode.stop()
        audioEngine.stop()
        
        queueLock.lock()
        audioQueue.removeAll()
        queueLock.unlock()
    }
    
    func clearQueue() {
        queueLock.lock()
        audioQueue.removeAll()
        queueLock.unlock()
    }
    
    func queueAudioData(_ data: Data) {
        guard isPlaying else { return }
        
        queueLock.lock()
        // 1. 缓冲区防积压丢包：超过 maxBufferSize 抛弃最老帧
        if audioQueue.count >= maxBufferSize {
            audioQueue.removeFirst()
        }
        audioQueue.append(data)
        let currentSize = audioQueue.count
        
        // 2. 蓄满 minBufferSize 起播
        if !playbackStarted && currentSize >= minBufferSize {
            playerNode.play()
            playbackStarted = true
            expectedPlaybackTime = Date().timeIntervalSince1970 * 1000.0
        }
        queueLock.unlock()
    }
    
    private func startPlaybackLoop() {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
            while self.isPlaying {
                if !self.playbackStarted {
                    usleep(10_000)
                    continue
                }
                
                self.queueLock.lock()
                if self.audioQueue.isEmpty {
                    self.playerNode.pause()
                    self.playbackStarted = false
                    self.expectedPlaybackTime = 0
                    self.queueLock.unlock()
                    usleep(20_000)
                    continue
                }
                
                let chunkData = self.audioQueue.removeFirst()
                self.queueLock.unlock()
                
                let currentTime = Date().timeIntervalSince1970 * 1000.0
                if currentTime < self.expectedPlaybackTime {
                    let sleepMs = self.expectedPlaybackTime - currentTime
                    if sleepMs > 0 && sleepMs < 100 {
                        usleep(useconds_t(sleepMs * 1000))
                    }
                }
                
                // 核心关键：将 16-bit PCM 字节流转为 iOS 混合器原生支持的 Float32 PCMBuffer
                if let pcmBuffer = self.int16ToFloat32Buffer(chunkData) {
                    self.playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
                }
                
                self.expectedPlaybackTime += self.chunkDurationMs
                if currentTime > self.expectedPlaybackTime + 100 {
                    self.expectedPlaybackTime = currentTime
                }
            }
        }
    }
    
    /// 解决 iOS 模拟器/真机无声音的核心：Int16 线性归一化到 Float32
    private func int16ToFloat32Buffer(_ data: Data) -> AVAudioPCMBuffer? {
        let sampleCount = data.count / 2
        guard sampleCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: self.floatAudioFormat, frameCapacity: AVAudioFrameCount(sampleCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        guard let floatChannel = buffer.floatChannelData?[0] else { return nil }
        
        data.withUnsafeBytes { rawBuffer in
            let int16Ptr = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                // 将 [-32768, 32767] 转换为 [-1.0, 1.0]
                floatChannel[i] = Float(int16Ptr[i]) / 32768.0
            }
        }
        return buffer
    }
    
    func updateSampleRate(_ newRate: Int) {
        if Double(newRate) != self.sampleRate {
            let wasPlaying = self.isPlaying
            if wasPlaying { stopPlayback() }
            self.sampleRate = Double(newRate)
            self.floatAudioFormat = AVAudioFormat(standardFormatWithSampleRate: self.sampleRate, channels: 1)!
            calculateTimingParameters()
            if wasPlaying { _ = startPlayback() }
        }
    }
}

// MARK: - AudioManager (对齐 Android AudioManager.kt)
/// 负责麦克风音频采集、转换为 16kHz 16-bit PCM 以及 RMS VAD 语音检测
class AudioManager {
    private let tag = "AudioManager"
    private let targetSampleRate: Double = 16000.0
    
    private let audioEngine = AVAudioEngine()
    private var isRecording = false
    
    private var amplitudeThreshold: Double = 100.0
    private var silenceCounter = 0
    private let silenceLimit = 15
    
    var onAudioDataCallback: ((Data, Bool) -> Void)?
    var onErrorCallback: ((String) -> Void)?
    
    func startRecording() -> Bool {
        guard !isRecording else { return true }
        
        do {
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            
            // 目标格式：16000Hz 单声道 Float32
            guard let intermediateFormat = AVAudioFormat(standardFormatWithSampleRate: targetSampleRate, channels: 1) else {
                onErrorCallback?("Failed to create intermediate format")
                return false
            }
            
            guard let converter = AVAudioConverter(from: inputFormat, to: intermediateFormat) else {
                onErrorCallback?("Failed to create audio converter")
                return false
            }
            
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
                guard let self = self, self.isRecording else { return }
                
                let ratio = self.targetSampleRate / inputFormat.sampleRate
                let targetCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 10)
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: intermediateFormat, frameCapacity: targetCapacity) else { return }
                
                var error: NSError?
                var isDone = false
                converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                    if !isDone {
                        outStatus.pointee = .haveData
                        isDone = true
                        return buffer
                    } else {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                }
                
                if let error = error {
                    self.onErrorCallback?("Audio conversion error: \(error.localizedDescription)")
                    return
                }
                
                let frameCount = Int(convertedBuffer.frameLength)
                guard frameCount > 0, let floatData = convertedBuffer.floatChannelData?[0] else { return }
                
                // 将 Float32 转换为 16-bit PCM 二进制
                var int16Data = Data(count: frameCount * 2)
                int16Data.withUnsafeMutableBytes { rawOut in
                    let int16Ptr = rawOut.bindMemory(to: Int16.self)
                    for i in 0..<frameCount {
                        let clamped = max(-1.0, min(1.0, floatData[i]))
                        int16Ptr[i] = Int16(clamped * 32767.0)
                    }
                }
                
                let hasVoice = self.detectVoiceActivity(int16Data)
                self.onAudioDataCallback?(int16Data, hasVoice)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            silenceCounter = 0
            return true
        } catch {
            onErrorCallback?("Audio recording start failed: \(error.localizedDescription)")
            return false
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }
    
    private func detectVoiceActivity(_ data: Data) -> Bool {
        let sampleCount = data.count / 2
        guard sampleCount > 0 else { return false }
        
        var sum: Double = 0
        data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            let int16Ptr = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let sample = Double(int16Ptr[i])
                sum += sample * sample
            }
        }
        
        let rms = sqrt(sum / Double(sampleCount))
        if rms > amplitudeThreshold {
            silenceCounter = 0
            return true
        } else {
            silenceCounter += 1
            return silenceCounter < silenceLimit
        }
    }
}

// MARK: - SesameWebSocket (对齐 Android SesameWebSocket.kt 全套协议)
/// 负责与 Sesame AI 后端进行长连接、严格对齐所有握手与会话建立协议
class SesameWebSocket: NSObject, URLSessionWebSocketDelegate {
    private let tag = "SesameWebSocket"
    private let wsUrlString = "wss://sesameai.app/agent-service-0/v1/connect"
    
    private let idToken: String
    private let character: String
    private let clientName: String = "Consumer-Web-App"
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    
    var serverSampleRate: Int = 24000
    private var sessionId: String?
    private var callId: String?
    private var isConnectedState = false
    private var firstAudioReceived = false
    
    private let bufferLock = NSLock()
    private var audioBuffer: [Data] = []
    
    var onConnectCallback: (() -> Void)?
    var onDisconnectCallback: (() -> Void)?
    var onErrorCallback: ((String) -> Void)?
    
    init(idToken: String, character: String = "Maya") {
        self.idToken = idToken
        self.character = character
        super.init()
    }
    
    func connect() -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encodedToken = idToken.addingPercentEncoding(withAllowedCharacters: allowed) ?? idToken
        let encodedContext = "%7B%22timezone%22%3A%22Asia%2FShanghai%22%7D"
        let encodedCharacter = character.addingPercentEncoding(withAllowedCharacters: allowed) ?? character
        let encodedClientName = clientName.addingPercentEncoding(withAllowedCharacters: allowed) ?? clientName
        
        let fullUrlStr = "\(wsUrlString)?id_token=\(encodedToken)&client_name=\(encodedClientName)&usercontext=\(encodedContext)&character=\(encodedCharacter)"
        
        guard let url = URL(string: fullUrlStr) else {
            onErrorCallback?("Invalid WebSocket URL")
            return false
        }
        
        var request = URLRequest(url: url)
        request.setValue("https://sesameai.app", forHTTPHeaderField: "Origin")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        webSocketTask = session?.webSocketTask(with: request)
        webSocketTask?.resume()
        
        listenForMessages()
        return true
    }
    
    func disconnect() {
        if sessionId != nil && callId != nil {
            sendCallDisconnect()
        }
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnectedState = false
    }
    
    func isConnected() -> Bool {
        return isConnectedState
    }
    
    func sendAudioData(_ data: Data) -> Bool {
        guard sessionId != nil && callId != nil else { return false }
        let base64Str = data.base64EncodedString()
        return sendAudio(base64Str)
    }
    
    func getNextAudioChunk() -> Data? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        if audioBuffer.isEmpty { return nil }
        return audioBuffer.removeFirst()
    }
    
    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                self.isConnectedState = false
                self.onErrorCallback?(error.localizedDescription)
                self.onDisconnectCallback?()
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleJsonMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleJsonMessage(text)
                    }
                @unknown default:
                    break
                }
                if self.webSocketTask != nil {
                    self.listenForMessages()
                }
            }
        }
    }
    
    private func handleJsonMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageType = json["type"] as? String else { return }
        
        switch messageType {
        case "initialize":
            self.sessionId = json["session_id"] as? String
            sendClientLocationState()
            sendCallConnect()
            
        case "call_connect_response":
            self.sessionId = json["session_id"] as? String
            self.callId = json["call_id"] as? String
            if let content = json["content"] as? [String: Any] {
                self.serverSampleRate = content["sample_rate"] as? Int ?? 24000
            }
            self.isConnectedState = true
            self.onConnectCallback?()
            
        case "audio":
            if let content = json["content"] as? [String: Any],
               let audioStr = content["audio_data"] as? String,
               let audioBytes = Data(base64Encoded: audioStr) {
                
                bufferLock.lock()
                if audioBuffer.count > 100 { audioBuffer.removeFirst() }
                audioBuffer.append(audioBytes)
                bufferLock.unlock()
                
                // 核心对齐 Android：首次收到 AI 声音后发送 2 个包含 'A' 的初始化包
                if !firstAudioReceived {
                    firstAudioReceived = true
                    let chunkOfAs = String(repeating: "A", count: 1707) + "="
                    _ = sendAudio(chunkOfAs)
                    _ = sendAudio(chunkOfAs)
                }
            }
            
        case "call_disconnect_response":
            self.callId = nil
            self.isConnectedState = false
            self.onDisconnectCallback?()
            
        default:
            break
        }
    }
    
    private func sendClientLocationState() {
        guard let sid = sessionId else { return }
        let dict: [String: Any] = [
            "type": "client_location_state",
            "session_id": sid,
            "call_id": NSNull(),
            "content": [
                "latitude": 0,
                "longitude": 0,
                "address": "",
                "timezone": "Asia/Shanghai"
            ]
        ]
        sendJson(dict)
    }
    
    /// 核心对齐：完整的 call_connect 握手报文，解决后台无法建立会话的问题
    private func sendCallConnect() {
        guard let sid = sessionId else { return }
        
        let clientMetadata: [String: Any] = [
            "language": "zh-CN",
            "user_agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            "mobile_browser": true,
            "media_devices": getMediaDevicesJsonArray()
        ]
        
        let settings: [String: Any] = [
            "character": character
        ]
        
        let content: [String: Any] = [
            "sample_rate": 16000,
            "audio_codec": "none",
            "reconnect": false,
            "is_private": false,
            "client_name": clientName,
            "settings": settings,
            "client_metadata": clientMetadata
        ]
        
        let message: [String: Any] = [
            "type": "call_connect",
            "session_id": sid,
            "call_id": callId ?? NSNull(),
            "request_id": UUID().uuidString,
            "content": content
        ]
        
        sendJson(message)
    }
    
    private func sendCallDisconnect() {
        guard let sid = sessionId, let cid = callId else { return }
        let dict: [String: Any] = [
            "type": "call_disconnect",
            "session_id": sid,
            "call_id": cid,
            "request_id": UUID().uuidString,
            "content": ["reason": "user_request"]
        ]
        sendJson(dict)
    }
    
    private func sendAudio(_ base64Audio: String) -> Bool {
        guard let sid = sessionId, let cid = callId else { return false }
        let dict: [String: Any] = [
            "type": "audio",
            "session_id": sid,
            "call_id": cid,
            "content": ["audio_data": base64Audio]
        ]
        return sendJson(dict)
    }
    
    @discardableResult
    private func sendJson(_ dict: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return false }
        webSocketTask?.send(.string(str)) { _ in }
        return true
    }
    
    private func getMediaDevicesJsonArray() -> [[String: String]] {
        return [
            ["deviceId": "default", "kind": "audioinput", "label": "Default - Microphone", "groupId": "default"],
            ["deviceId": "default", "kind": "audiooutput", "label": "Default - Speaker", "groupId": "default"]
        ]
    }
}

// MARK: - VoiceChatPlugin (对齐 Android MainActivity / VoiceChatPlugin)
@objc public class VoiceChatPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private static let CHANNEL_CONTROL = "com.sesame.voicechat/control"
    private static let CHANNEL_EVENTS = "com.sesame.voicechat/events"
    
    private var eventSink: FlutterEventSink?
    
    private var sesameWebSocket: SesameWebSocket?
    private var audioPlayer: AudioPlayer?
    private var audioRecordManager: AudioManager?
    
    private var isConnected = false
    private var isProcessingAudio = false
    private var isMuted = false
    
    @objc public static func register(with registrar: FlutterPluginRegistrar) {
        let controlChannel = FlutterMethodChannel(name: CHANNEL_CONTROL, binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: CHANNEL_EVENTS, binaryMessenger: registrar.messenger())
        
        let instance = VoiceChatPlugin()
        registrar.addMethodCallDelegate(instance, channel: controlChannel)
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "connect":
            let args = call.arguments as? [String: Any]
            let token = args?["token"] as? String ?? ""
            let rawCharacter = args?["characterName"] as? String ?? "Kira"
            // 核心映射：将前端角色名映射为后端真实受支持的标识（如 Kira -> Maya）
            let backendCharacter = CharacterMapper.getBackendCharacter(rawCharacter)
            
            if token.isEmpty {
                result(FlutterError(code: "INVALID_TOKEN", message: "Token cannot be empty", details: nil))
                return
            }
            
            connect(character: backendCharacter, token: token)
            result(true)
            
        case "disconnect":
            disconnect()
            result(true)
            
        case "setMute", "toggleMute":
            let args = call.arguments as? [String: Any]
            if let muted = args?["isMuted"] as? Bool {
                isMuted = muted
            } else {
                isMuted = !isMuted
            }
            
            if isMuted {
                audioRecordManager?.stopRecording()
            } else {
                _ = audioRecordManager?.startRecording()
            }
            result(isMuted)
            
        case "setAudioRoute":
            let args = call.arguments as? [String: Any]
            let route = args?["route"] as? String ?? "AUTO"
            setAudioRoute(route)
            result(true)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
    
    private func connect(character: String, token: String) {
        if isConnected { return }
        
        sendEvent(type: "status", value: "Connecting...")
        setupAudioSession()
        
        sesameWebSocket = SesameWebSocket(idToken: token, character: character)
        sesameWebSocket?.onConnectCallback = { [weak self] in
            DispatchQueue.main.async {
                self?.onWebSocketConnected()
            }
        }
        sesameWebSocket?.onDisconnectCallback = { [weak self] in
            DispatchQueue.main.async {
                self?.disconnect()
            }
        }
        sesameWebSocket?.onErrorCallback = { [weak self] err in
            DispatchQueue.main.async {
                self?.sendEvent(type: "error", value: err)
            }
        }
        
        _ = sesameWebSocket?.connect()
    }
    
    private func onWebSocketConnected() {
        isConnected = true
        sendEvent(type: "init_progress", value: 100)
        sendEvent(type: "status", value: "Connected")
        setupAudio()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                    mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            // 解决模拟器和真机听筒无声：强制路由至扬声器播放
            try session.overrideOutputAudioPort(.speaker)
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)
        } catch {
            sendEvent(type: "error", value: "AudioSession setup error: \(error.localizedDescription)")
        }
    }
    
    private func setupAudio() {
        let sampleRate = sesameWebSocket?.serverSampleRate ?? 24000
        audioPlayer = AudioPlayer(sampleRate: sampleRate)
        _ = audioPlayer?.startPlayback()
        
        audioRecordManager = AudioManager()
        audioRecordManager?.onAudioDataCallback = { [weak self] (audioData, hasVoice) in
            guard let self = self else { return }
            
            if self.isConnected && !self.isMuted {
                if hasVoice {
                    _ = self.sesameWebSocket?.sendAudioData(audioData)
                } else {
                    let silent = Data(count: audioData.count)
                    _ = self.sesameWebSocket?.sendAudioData(silent)
                }
            }
            
            DispatchQueue.main.async {
                self.sendEvent(type: "voice_activity", value: [
                    "hasVoice": hasVoice,
                    "audio_data": [UInt8](audioData)
                ])
            }
        }
        
        _ = audioRecordManager?.startRecording()
        startAudioProcessing()
    }
    
    private func startAudioProcessing() {
        isProcessingAudio = true
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            while self.isProcessingAudio && self.sesameWebSocket?.isConnected() == true {
                if let audioChunk = self.sesameWebSocket?.getNextAudioChunk() {
                    self.audioPlayer?.queueAudioData(audioChunk)
                    
                    let resampled = self.resample24to16(input: audioChunk)
                    DispatchQueue.main.async {
                        self.sendEvent(type: "ai_audio_data", value: [UInt8](resampled))
                    }
                } else {
                    usleep(2000)
                }
            }
        }
    }
    
    private func disconnect() {
        sendEvent(type: "status", value: "Disconnecting...")
        isProcessingAudio = false
        audioRecordManager?.stopRecording()
        audioPlayer?.stopPlayback()
        sesameWebSocket?.disconnect()
        
        audioRecordManager = nil
        audioPlayer = nil
        sesameWebSocket = nil
        isConnected = false
        
        sendEvent(type: "status", value: "Disconnected")
    }
    
    private func setAudioRoute(_ route: String) {
        do {
            let session = AVAudioSession.sharedInstance()
            switch route.uppercased() {
            case "SPEAKER":
                try session.overrideOutputAudioPort(.speaker)
            case "EARPIECE":
                try session.overrideOutputAudioPort(.none)
            default:
                try session.overrideOutputAudioPort(.speaker)
            }
        } catch {
            sendEvent(type: "error", value: "Set route error: \(error.localizedDescription)")
        }
    }
    
    private func resample24to16(input: Data) -> Data {
        let inputSamples = input.count / 2
        let outputSamples = (inputSamples * 2) / 3
        var output = Data(count: outputSamples * 2)
        
        input.withUnsafeBytes { inBuf in
            output.withUnsafeMutableBytes { outBuf in
                let inPtr = inBuf.bindMemory(to: Int16.self)
                let outPtr = outBuf.bindMemory(to: Int16.self)
                
                for i in 0..<outputSamples {
                    let srcIdx = (i * 3) / 2
                    if srcIdx < inputSamples {
                        outPtr[i] = inPtr[srcIdx]
                    }
                }
            }
        }
        return output
    }
    
    private func sendEvent(type: String, value: Any) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(["type": type, "value": value])
        }
    }
}
