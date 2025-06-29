//
import Foundation
import AVFoundation
import Speech
import OSLog

// MARK: - Public Interface

/// Main transcription library interface
public class TranscribeEngine: @unchecked Sendable {
    
    /// Transcribes an audio file and returns the result
    /// - Parameters:
    ///   - audioURL: URL to the audio file to transcribe
    ///   - service: Which transcription service to use (default: Apple local)
    ///   - language: Language code (default: "auto" for auto-detect)
    ///   - apiKey: API key if using external service (optional)
    /// - Returns: TranscriptionResult containing the text and metadata
    public static func transcribe(
        audioURL: URL,
        service: TranscriptionService = .appleFramework,
        language: String = "auto",
        apiKey: String? = nil
    ) async throws -> TranscriptionResult {
        
        let engine = TranscribeEngine()
        return try await engine.performTranscription(
            audioURL: audioURL,
            service: service,
            language: language,
            apiKey: apiKey
        )
    }
    
    private let logger = Logger(subsystem: "com.lunarclass.transcribe", category: "TranscribeEngine")
    
    private init() {
        // Simple init - permission handling moved to transcription method
    }
    
    private func performTranscription(
        audioURL: URL,
        service: TranscriptionService,
        language: String,
        apiKey: String?
    ) async throws -> TranscriptionResult {
        
        logger.info("Starting transcription for: \(audioURL.lastPathComponent)")
        
        switch service {
        case .appleFramework:
            return try await transcribeWithAppleFramework(audioURL: audioURL, language: language)
        case .openAI:
            guard let apiKey = apiKey else {
                throw TranscriptionError.missingAPIKey
            }
            return try await transcribeWithOpenAI(audioURL: audioURL, language: language, apiKey: apiKey)
        case .whisperLocal:
            return try await transcribeWithLocalWhisper(audioURL: audioURL, language: language)
        }
    }
}

// MARK: - Public Types

public enum TranscriptionService: String, CaseIterable, Sendable {
    case appleFramework = "apple_framework"
    case openAI = "openai"
    case whisperLocal = "whisper_local"
    
    public var displayName: String {
        switch self {
        case .appleFramework: return "Apple Speech Framework (Local)"
        case .openAI: return "OpenAI Whisper API"
        case .whisperLocal: return "Local Whisper.cpp"
        }
    }
    
    public var requiresAPIKey: Bool {
        return self == .openAI
    }
    
    public var supportsTimestamps: Bool {
        return self != .appleFramework
    }
}

public struct TranscriptionResult: Sendable {
    public let text: String
    public let segments: [TranscriptSegment]
    public let language: String?
    public let modelUsed: String
    
    public init(text: String, segments: [TranscriptSegment], language: String?, modelUsed: String) {
        self.text = text
        self.segments = segments
        self.language = language
        self.modelUsed = modelUsed
    }
}

public struct TranscriptSegment: Sendable {
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let text: String
    public let confidence: Float?
    
    public init(startTime: TimeInterval, endTime: TimeInterval, text: String, confidence: Float?) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.confidence = confidence
    }
    
    public var formattedTimeRange: String {
        let start = formatTime(startTime)
        let end = formatTime(endTime)
        return "\(start) - \(end)"
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
}

public enum TranscriptionError: LocalizedError, Sendable {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case serviceNotAvailable(String)
    case audioConversionFailed
    case speechRecognitionNotAuthorized
    case speechRecognitionNotAvailable(String)
    case speechRecognitionFailed(String)
    case fileNotFound
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is required"
        case .invalidResponse:
            return "Invalid response from transcription service"
        case .apiError(let message):
            return "API Error: \(message)"
        case .serviceNotAvailable(let message):
            return "Service not available: \(message)"
        case .audioConversionFailed:
            return "Failed to convert audio file"
        case .speechRecognitionNotAuthorized:
            return "Speech recognition permission not granted. Please enable in System Settings > Privacy & Security > Speech Recognition."
        case .speechRecognitionNotAvailable(let message):
            return "Speech recognition not available: \(message)"
        case .speechRecognitionFailed(let message):
            return "Speech recognition failed: \(message)"
        case .fileNotFound:
            return "Audio file not found"
        case .timeout:
            return "Transcription timed out"
        }
    }
}

// MARK: - Private Implementation

private extension TranscribeEngine {
    
    func requestSpeechRecognitionPermission() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized:
                    self.logger.info("Speech recognition authorized")
                    continuation.resume()
                case .denied:
                    self.logger.warning("Speech recognition denied")
                    continuation.resume(throwing: TranscriptionError.speechRecognitionNotAuthorized)
                case .restricted:
                    self.logger.warning("Speech recognition restricted")
                    continuation.resume(throwing: TranscriptionError.speechRecognitionNotAuthorized)
                case .notDetermined:
                    self.logger.warning("Speech recognition not determined")
                    continuation.resume(throwing: TranscriptionError.speechRecognitionNotAuthorized)
                @unknown default:
                    self.logger.warning("Unknown speech recognition status")
                    continuation.resume(throwing: TranscriptionError.speechRecognitionNotAuthorized)
                }
            }
        }
    }
    
    func transcribeWithAppleFramework(audioURL: URL, language: String) async throws -> TranscriptionResult {
        // Check if file exists
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            logger.error("Audio file not found: \(audioURL.path)")
            throw TranscriptionError.fileNotFound
        }
        
        logger.info("Audio file exists, size: \(try! FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as! Int) bytes")
        
        // Request permission if not already granted
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            logger.info("Requesting speech recognition permission...")
            try await requestSpeechRecognitionPermission()
        }
        
        // Create speech recognizer for the specified language
        let locale: Locale
        if language == "auto" {
            locale = Locale.current
        } else {
            locale = Locale(identifier: language)
        }
        
        logger.info("Using locale: \(locale.identifier)")
        
        guard let speechRecognizer = SFSpeechRecognizer(locale: locale) else {
            logger.error("Speech recognizer not available for locale: \(locale.identifier)")
            throw TranscriptionError.speechRecognitionNotAvailable("Speech recognizer not available for locale: \(locale.identifier)")
        }
        
        guard speechRecognizer.isAvailable else {
            logger.error("Speech recognizer is not available")
            throw TranscriptionError.speechRecognitionNotAvailable("Speech recognizer is not available")
        }
        
        logger.info("Speech recognizer is available, starting transcription...")
        
        // Create recognition request
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = false // Allow cloud processing to avoid hanging
        
        // Simplify the implementation to avoid concurrency issues
        logger.info("Recognition task created and started")
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<TranscriptionResult, Error>) in
            var hasResumed = false
            var recognitionTask: SFSpeechRecognitionTask?
            
            // Create timeout timer
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            timer.schedule(deadline: .now() + 30.0) // 30 seconds timeout
            timer.setEventHandler {
                if !hasResumed {
                    hasResumed = true
                    recognitionTask?.cancel()
                    continuation.resume(throwing: TranscriptionError.timeout)
                }
                timer.cancel()
            }
            timer.resume()
            
            recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
                if hasResumed { return }
                
                if let error = error {
                    self.logger.error("Speech recognition error: \(error.localizedDescription)")
                    hasResumed = true
                    timer.cancel()
                    continuation.resume(throwing: TranscriptionError.speechRecognitionFailed(error.localizedDescription))
                    return
                }
                
                guard let result = result else {
                    self.logger.error("No recognition result")
                    hasResumed = true
                    timer.cancel()
                    continuation.resume(throwing: TranscriptionError.speechRecognitionFailed("No recognition result"))
                    return
                }
                
                if result.isFinal {
                    self.logger.info("Transcription completed: '\(result.bestTranscription.formattedString)'")
                    hasResumed = true
                    timer.cancel()
                    let transcriptionResult = TranscriptionResult(
                        text: result.bestTranscription.formattedString,
                        segments: [], // Apple Speech Framework doesn't provide detailed segments
                        language: locale.identifier,
                        modelUsed: "Apple Speech Framework"
                    )
                    continuation.resume(returning: transcriptionResult)
                }
            }
        }
    }
    
    func transcribeWithOpenAI(audioURL: URL, language: String, apiKey: String) async throws -> TranscriptionResult {
        // Check if file exists
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.fileNotFound
        }
        
        // Convert audio to format supported by OpenAI (MP3, M4A, etc.)
        let convertedURL = try await convertAudioForAPI(audioURL)
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Add language parameter if not auto
        if language != "auto" {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language)\r\n".data(using: .utf8)!)
        }
        
        // Add response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json\r\n".data(using: .utf8)!)
        
        // Add file
        let audioData = try Data(contentsOf: convertedURL)
        let filename = convertedURL.lastPathComponent
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mpeg\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("OpenAI API error: \(httpResponse.statusCode) - \(errorMessage)")
            throw TranscriptionError.apiError(errorMessage)
        }
        
        // Clean up converted file
        try? FileManager.default.removeItem(at: convertedURL)
        
        return try parseOpenAIResponse(data)
    }
    
    func transcribeWithLocalWhisper(audioURL: URL, language: String) async throws -> TranscriptionResult {
        logger.info("Starting whisper.cpp transcription for: \(audioURL.lastPathComponent)")
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            logger.error("Audio file not found: \(audioURL.path)")
            throw TranscriptionError.fileNotFound
        }
        
        // Get model path - try different model files in order of preference
        let projectDir = "/Users/jarosz/projects/tiffin"
        let modelPaths = [
            Bundle.main.path(forResource: "ggml-base", ofType: "bin"),
            Bundle.main.path(forResource: "ggml-small", ofType: "bin"), 
            Bundle.main.path(forResource: "ggml-tiny", ofType: "bin"),
            // Fallback to project directory for testing
            "\(projectDir)/ggml-base.bin",
            "\(projectDir)/ggml-small.bin",
            "\(projectDir)/ggml-large-v1.bin"
        ]
        
        // Find the first model file that actually exists
        guard let modelPath = modelPaths.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            logger.error("No whisper model found in app bundle")
            throw TranscriptionError.serviceNotAvailable("No whisper model found in app bundle. Please add ggml-base.bin, ggml-small.bin, or ggml-tiny.bin to your project.")
        }
        
        logger.info("Using model: \(URL(fileURLWithPath: modelPath).lastPathComponent)")
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Initialize WhisperCore with default configuration (GPU preferred with CPU fallback)
                    guard let whisperCore = WhisperCore(modelPath: modelPath) else {
                        self.logger.error("Failed to initialize WhisperCore")
                        continuation.resume(throwing: TranscriptionError.serviceNotAvailable("Failed to initialize whisper"))
                        return
                    }
                    
                    let deviceType = whisperCore.isUsingGPU ? "GPU" : "CPU"
                    self.logger.info("WhisperCore initialized successfully using \(deviceType). Model info: \(whisperCore.modelInfo)")
                    
                    // Transcribe the audio file
                    guard let result = whisperCore.transcribeAudioFile(audioURL) else {
                        self.logger.error("Whisper transcription failed")
                        continuation.resume(throwing: TranscriptionError.speechRecognitionFailed("Whisper transcription failed"))
                        return
                    }
                    
                    let performanceInfo = result.usedGPU ? " (GPU-accelerated)" : " (CPU-only)"
                    self.logger.info("Whisper transcription completed\(performanceInfo). Text length: \(result.text.count), Segments: \(result.segments.count)")
                    
                    // Convert WhisperCore result to TranscriptionResult
                    let segments = result.segments.map { segment in
                        TranscriptSegment(
                            startTime: segment.startTime,
                            endTime: segment.endTime,
                            text: segment.text,
                            confidence: segment.confidence > 0 ? segment.confidence : nil
                        )
                    }
                    
                    let transcriptionResult = TranscriptionResult(
                        text: result.text,
                        segments: segments,
                        language: result.language,
                        modelUsed: result.modelUsed
                    )
                    
                    continuation.resume(returning: transcriptionResult)
                    
                } catch {
                    self.logger.error("Whisper transcription error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func convertAudioForAPI(_ audioURL: URL) async throws -> URL {
        // For now, assume the audio is already in a supported format
        // TODO: Add audio conversion logic if needed
        return audioURL
    }
    
    func parseOpenAIResponse(_ data: Data) throws -> TranscriptionResult {
        let response = try JSONDecoder().decode(OpenAIVerboseResponse.self, from: data)
        let segments = response.segments.map { segment in
            TranscriptSegment(
                startTime: segment.start,
                endTime: segment.end,
                text: segment.text.trimmingCharacters(in: .whitespaces),
                confidence: nil
            )
        }
        return TranscriptionResult(
            text: response.text,
            segments: segments,
            language: response.language,
            modelUsed: "whisper-1"
        )
    }
}

// MARK: - OpenAI Response Types

private struct OpenAIVerboseResponse: Codable, Sendable {
    let text: String
    let language: String
    let segments: [OpenAISegment]
}

private struct OpenAISegment: Codable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}