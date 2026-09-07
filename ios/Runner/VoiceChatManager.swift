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

// MARK: - Unified Audio Engine (统一单引擎全双工架构)
/// 彻底解决双引擎冲突、消除死锁卡顿与静默，硬件级无缝流式播放与录音
class VoiceAudioEngine {
    private let tag = "VoiceAudioEngine"
    
    // 整个 App 共用单例引擎，避免多个 AVAudioEngine 争抢硬件资源导致麦克风/扬声器死锁
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    private var outputSampleRate: Double = 24000.0
    private let inputTargetRate: Double = 16000.0
    
    private var floatOutputFormat: AVAudioFormat!
    
    // Jitter 缓冲：起播前平滑缓冲 3 帧（约 120ms），起播后直接顺畅喂入硬件队列
    private var prebufferQueue: [Data] = []
    private let queueLock = NSLock()
    private var isPlayingStarted = false
    private let prebufferThreshold = 3
    
    // 录音状态与 VAD
    private var isRecording = false
    private var amplitudeThreshold: Double = 100.0
    private var silenceCounter = 0
    private let silenceLimit = 15
    
    var onAudioRecorded: ((Data, Bool) -> Void)?
    var onError: ((String) -> Void)?
    
    init(serverSampleRate: Int = 24000) {
        self.outputSampleRate = Double(serverSampleRate)
        self.floatOutputFormat = AVAudioFormat(standardFormatWithSampleRate: self.outputSampleRate, channels: 1)!
    }
    
    func start() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                    mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.overrideOutputAudioPort(.speaker)
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)
            
            // 1. 配置播放节点
            if !engine.attachedNodes.contains(playerNode) {
                engine.attach(playerNode)
                engine.connect(playerNode, to: engine.mainMixerNode, format: floatOutputFormat)
            }
            
            // 2. 配置麦克风录音 Tap（通过同个引擎进行采集）
            setupMicrophoneTap()
            
            engine.prepare()
            try engine.start()
            
            playerNode.play()
            isPlayingStarted = false
            
            queueLock.lock()
            prebufferQueue.removeAll()
            queueLock.unlock()
            
            return true
        } catch {
            onError?("AudioEngine start failed: \(error.localizedDescription)")
            return false
        }
    }
    
    func stop() {
        queueLock.lock()
        prebufferQueue.removeAll()
        isPlayingStarted = false
        queueLock.unlock()
        
        playerNode.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
    }
    
    // 🌟 核心播放算法：流式缓冲入队，杜绝 pause() 造成的断续卡顿与永久静音
    func queueAudioPlayback(_ data: Data) {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        if !isPlayingStarted {
            prebufferQueue.append(data)
            // 预缓冲蓄水达到阈值（3 帧约 120ms）时，批量提交播放，保证开头绝对平滑
            if prebufferQueue.count >= prebufferThreshold {
                for chunk in prebufferQueue {
                    if let buffer = int16ToFloat32Buffer(chunk) {
                        playerNode.scheduleBuffer(buffer, completionHandler: nil)
                    }
                }
                prebufferQueue.removeAll()
                isPlayingStarted = true
            }
        } else {
            // 已在起播状态：收到分片直接喂给底层硬件队列，让 CoreAudio 硬件时钟自动做到样本级无缝衔接
            if let buffer = int16ToFloat32Buffer(data) {
                playerNode.scheduleBuffer(buffer, completionHandler: nil)
            }
        }
    }
    
    private func setupMicrophoneTap() {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        guard inputFormat.sampleRate > 0 else { return }
        
        guard let intermediateFormat = AVAudioFormat(standardFormatWithSampleRate: inputTargetRate, channels: 1),
              let converter = AVAudioConverter(from: inputFormat, to: intermediateFormat) else {
            return
        }
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            
            let ratio = self.inputTargetRate / inputFormat.sampleRate
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
            
            if error != nil { return }
            
            let frameCount = Int(convertedBuffer.frameLength)
            guard frameCount > 0, let floatData = convertedBuffer.floatChannelData?[0] else { return }
            
            var int16Data = Data(count: frameCount * 2)
            int16Data.withUnsafeMutableBytes { rawOut in
                let int16Ptr = rawOut.bindMemory(to: Int16.self)
                for i in 0..<frameCount {
                    let clamped = max(-1.0, min(1.0, floatData[i]))
                    int16Ptr[i] = Int16(clamped * 32767.0)
                }
            }
            
            let hasVoice = self.detectVoiceActivity(int16Data)
            self.onAudioRecorded?(int16Data, hasVoice)
        }
        isRecording = true
    }
    
    private func int16ToFloat32Buffer(_ data: Data) -> AVAudioPCMBuffer? {
        let sampleCount = data.count / 2
        guard sampleCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: self.floatOutputFormat, frameCapacity: AVAudioFrameCount(sampleCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        guard let floatChannel = buffer.floatChannelData?[0] else { return nil }
        
        data.withUnsafeBytes { rawBuffer in
            let int16Ptr = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                floatChannel[i] = Float(int16Ptr[i]) / 32768.0
            }
        }
        return buffer
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
    
    func setRoute(_ route: String) {
        do {
            let session = AVAudioSession.sharedInstance()
            if route.uppercased() == "EARPIECE" {
                try session.overrideOutputAudioPort(.none)
            } else {
                try session.overrideOutputAudioPort(.speaker)
            }
        } catch {}
    }
}

// MARK: - SesameWebSocket (心跳保活与完整协议栈)
class SesameWebSocket: NSObject, URLSessionWebSocketDelegate {
    private let wsUrlString = "wss://sesameai.app/agent-service-0/v1/connect"
    
    private let idToken: String
    private let character: String
    private let clientName: String = "Consumer-Web-App"
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTimer: Timer?
    
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
        startPingTimer()
        return true
    }
    
    func disconnect() {
        stopPingTimer()
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
    
    private func startPingTimer() {
        stopPingTimer()
        DispatchQueue.main.async { [weak self] in
            self?.pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.sendPing()
            }
        }
    }
    
    private func stopPingTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.pingTimer?.invalidate()
            self?.pingTimer = nil
        }
    }
    
    private func sendPing() {
        guard let sid = sessionId, let cid = callId else { return }
        let dict: [String: Any] = [
            "type": "ping",
            "session_id": sid,
            "call_id": cid,
            "request_id": UUID().uuidString,
            "content": "ping"
        ]
        sendJson(dict)
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
        
        let clientMetadata: [String: Any] = [
            "language": "zh-CN",
            "user_agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            "mobile_browser": true,
            "media_devices": [
                ["deviceId": "default", "kind": "audioinput", "label": "Default - Microphone", "groupId": "default"],
                ["deviceId": "default", "kind": "audiooutput", "label": "Default - Speaker", "groupId": "default"]
            ]
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
}

// MARK: - VoiceChatPlugin (对外接口与事件分发)
@objc public class VoiceChatPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private static let CHANNEL_CONTROL = "com.sesame.voicechat/control"
    private static let CHANNEL_EVENTS = "com.sesame.voicechat/events"
    
    private var eventSink: FlutterEventSink?
    
    private var sesameWebSocket: SesameWebSocket?
    private var unifiedEngine: VoiceAudioEngine?
    
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
            result(isMuted)
            
        case "setAudioRoute":
            let args = call.arguments as? [String: Any]
            let route = args?["route"] as? String ?? "AUTO"
            unifiedEngine?.setRoute(route)
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
    
    private func setupAudio() {
        let sampleRate = sesameWebSocket?.serverSampleRate ?? 24000
        unifiedEngine = VoiceAudioEngine(serverSampleRate: sampleRate)
        
        unifiedEngine?.onAudioRecorded = { [weak self] (audioData, hasVoice) in
            guard let self = self else { return }
            
            // 保持静默数据持续发送，这是 Sesame 维持对话长连接的关键！
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
        
        _ = unifiedEngine?.start()
        startAudioProcessing()
    }
    
    private func startAudioProcessing() {
        isProcessingAudio = true
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            while self.isProcessingAudio && self.sesameWebSocket?.isConnected() == true {
                if let audioChunk = self.sesameWebSocket?.getNextAudioChunk() {
                    // 送入统一引擎无缝流式播放
                    self.unifiedEngine?.queueAudioPlayback(audioChunk)
                    
                    // 24000Hz 3:2 线性抽取降频为 16000Hz，抛给 Flutter 进行同传翻译
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
        unifiedEngine?.stop()
        sesameWebSocket?.disconnect()
        
        unifiedEngine = nil
        sesameWebSocket = nil
        isConnected = false
        
        sendEvent(type: "status", value: "Disconnected")
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
