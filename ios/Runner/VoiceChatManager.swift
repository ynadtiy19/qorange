import Foundation
import AVFoundation
import Flutter

// MARK: - AudioPlayer (对齐 Android AudioPlayer.kt)
/// 负责流式 PCM 音频播放、自适应 Jitter Buffer、时钟漂移同步与欠载恢复
class AudioPlayer {
    private let tag = "AudioPlayer"
    
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    private var sampleRate: Double
    private var audioFormat: AVAudioFormat
    
    private let queueLock = NSLock()
    private var audioQueue: [Data] = []
    
    // 自适应抗抖动缓冲算法参数（与 Android 完全对齐）
    private var minBufferSize = 5       // 触发起播的最小缓冲分片数
    private var targetBufferSize = 10   // 理想缓冲深度
    private var maxBufferSize = 20      // 溢出上限（丢弃最旧分片，防止延迟累积）
    private var chunkDurationMs: Double = 0
    
    private var isPlaying = false
    private var playbackStarted = false
    private var expectedPlaybackTime: Double = 0
    private var playbackThread: Thread?
    
    var onErrorCallback: ((String) -> Void)?
    
    init(sampleRate: Int = 24000) {
        self.sampleRate = Double(sampleRate)
        self.audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: self.sampleRate,
                                         channels: 1,
                                         interleaved: true)!
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
                audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioFormat)
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
    
    /// 将从 WebSocket 收到的 PCM 分片压入抖动缓冲区
    func queueAudioData(_ data: Data) {
        guard isPlaying else { return }
        
        queueLock.lock()
        // 1. 缓冲溢出管理：当积压超过最大阈值，主动剔除最老分片，将延迟压制在 200ms 内
        if audioQueue.count >= maxBufferSize {
            audioQueue.removeFirst()
        }
        audioQueue.append(data)
        let currentSize = audioQueue.count
        
        // 2. 蓄水达到 minBufferSize 时才真正启动播放节点
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
                    usleep(10_000) // 等待缓冲蓄水 (10ms)
                    continue
                }
                
                self.queueLock.lock()
                if self.audioQueue.isEmpty {
                    // 缓冲饥饿（Underrun）：暂停播放节点，重回预缓冲状态
                    self.playerNode.pause()
                    self.playbackStarted = false
                    self.expectedPlaybackTime = 0
                    self.queueLock.unlock()
                    usleep(20_000)
                    continue
                }
                
                let chunkData = self.audioQueue.removeFirst()
                self.queueLock.unlock()
                
                // 时钟同步平滑步调
                let currentTime = Date().timeIntervalSince1970 * 1000.0
                if currentTime < self.expectedPlaybackTime {
                    let sleepMs = self.expectedPlaybackTime - currentTime
                    if sleepMs > 0 && sleepMs < 100 {
                        usleep(useconds_t(sleepMs * 1000))
                    }
                }
                
                // 将 Data 转为 AVAudioPCMBuffer 提交播放
                if let pcmBuffer = self.dataToPCMBuffer(chunkData) {
                    self.playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
                }
                
                self.expectedPlaybackTime += self.chunkDurationMs
                
                // 消除时钟严重漂移
                if currentTime > self.expectedPlaybackTime + 100 {
                    self.expectedPlaybackTime = currentTime
                }
            }
        }
    }
    
    private func dataToPCMBuffer(_ data: Data) -> AVAudioPCMBuffer? {
        let frameCount = UInt32(data.count) / 2
        guard let buffer = AVAudioPCMBuffer(pcmFormat: self.audioFormat, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        data.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                memcpy(buffer.int16ChannelData![0], baseAddress, data.count)
            }
        }
        return buffer
    }
    
    func updateSampleRate(_ newRate: Int) {
        if Double(newRate) != self.sampleRate {
            let wasPlaying = self.isPlaying
            if wasPlaying { stopPlayback() }
            self.sampleRate = Double(newRate)
            self.audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                             sampleRate: self.sampleRate,
                                             channels: 1,
                                             interleaved: true)!
            calculateTimingParameters()
            if wasPlaying { _ = startPlayback() }
        }
    }
}

// MARK: - AudioManager (对齐 Android AudioManager.kt)
/// 负责麦克风录音采集、16kHz 16-bit PCM 转换与 RMS 能量 VAD 语音活动检测
class AudioManager {
    private let tag = "AudioManager"
    private let sampleRate: Double = 16000.0
    
    private let audioEngine = AVAudioEngine()
    private var isRecording = false
    
    // VAD 参数（与 Android 一致）
    private var amplitudeThreshold: Double = 100.0
    private var silenceCounter = 0
    private let silenceLimit = 15 // 平滑尾音，防断句吞字
    
    var onAudioDataCallback: ((Data, Bool) -> Void)?
    var onErrorCallback: ((String) -> Void)?
    
    func startRecording() -> Bool {
        guard !isRecording else { return true }
        
        do {
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            
            // 目标格式：16000Hz 单声道 16-bit PCM
            guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                                   sampleRate: sampleRate,
                                                   channels: 1,
                                                   interleaved: true) else {
                onErrorCallback?("Failed to create target audio format")
                return false
            }
            
            // 使用系统级 AVAudioConverter 进行高精度硬件重采样
            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                onErrorCallback?("Failed to create audio converter")
                return false
            }
            
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
                guard let self = self, self.isRecording else { return }
                
                // 计算目标分片采样帧数
                let ratio = self.sampleRate / inputFormat.sampleRate
                let targetCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 10)
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetCapacity) else { return }
                
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
                
                let frameLength = Int(convertedBuffer.frameLength)
                guard frameLength > 0, let channelData = convertedBuffer.int16ChannelData else { return }
                
                let byteCount = frameLength * 2
                let data = Data(bytes: channelData[0], count: byteCount)
                
                // 执行 RMS 能量 VAD 检测
                let hasVoice = self.detectVoiceActivity(data)
                self.onAudioDataCallback?(data, hasVoice)
            }
            
            try audioEngine.start()
            isRecording = true
            silenceCounter = 0
            return true
        } catch {
            onErrorCallback?("AudioRecord start failed: \(error.localizedDescription)")
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

// MARK: - SesameWebSocket (对齐 Android SesameWebSocket.kt)
/// 负责与 Sesame AI 后端进行长连接通信、身份鉴权与二进制音频 Base64 交互
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
    
    init(idToken: String, character: String = "Miles") {
        self.idToken = idToken
        self.character = character
        super.init()
    }
    
    func connect() -> Bool {
        // 对齐查询参数，将 '+' 替换为 '%20'
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
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
        
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
        webSocketTask = nullSafeTask()
        isConnectedState = false
    }
    
    private func nullSafeTask() -> URLSessionWebSocketTask? { return nil }
    
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
                if self.isConnectedState || self.webSocketTask != nil {
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
                
                if !firstAudioReceived {
                    firstAudioReceived = true
                    let chunkOfAs = String(repeating: "A", count: 1707) + "="
                    sendAudio(chunkOfAs)
                    sendAudio(chunkOfAs)
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
    
    private func sendCallConnect() {
        guard let sid = sessionId else { return }
        let dict: [String: Any] = [
            "type": "call_connect",
            "session_id": sid,
            "call_id": NSNull(),
            "content": [
                "character": character,
                "sample_rate": 16000
            ]
        ]
        sendJson(dict)
    }
    
    private func sendCallDisconnect() {
        guard let sid = sessionId, let cid = callId else { return }
        let dict: [String: Any] = [
            "type": "call_disconnect",
            "session_id": sid,
            "call_id": cid,
            "content": [:]
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
}

// MARK: - VoiceChatPlugin (对齐 Android MainActivity / VoiceChatPlugin)
/// Flutter 平台通道控制器，提供完整的双向音频调度与全双工 VoIP 管理
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
            let characterName = args?["characterName"] as? String ?? "Kira"
            
            if token.isEmpty {
                result(FlutterError(code: "INVALID_TOKEN", message: "Token cannot be empty", details: nil))
                return
            }
            
            connect(character: characterName, token: token)
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
            // 启用系统级硬件 AEC（回声抑制）和 VoiceChat 模式
            try session.setCategory(.playAndRecord,
                                    mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
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
            
            // 回传 VAD 状态与麦克风原始 PCM 字节流
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
                    // 1. 送入原生播放器
                    self.audioPlayer?.queueAudioData(audioChunk)
                    
                    // 2. 3:2 重采样为 16000Hz PCM 抛给 Flutter 实时同传翻译
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
    
    /// 将 24000Hz 原始 PCM 降频重采样为 16000Hz（3:2 线性抽取）
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
