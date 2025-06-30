import Foundation
import SwiftData
import OSLog
import Kuzco

// MARK: - AI Manager for Local LLM Chat
@Observable
class AIManager {
    private let logger = Logger(subsystem: "com.lunarclass.tiffin", category: "AIManager")
    
    // Kuzco Client
    private var kuzco: Kuzco?
    
    // Chat state
    var chatMessages: [ChatMessage] = []
    var isProcessing = false
    var currentResponse = ""
    
    // Model configuration
    private let modelName = "phi-3-mini-4k-instruct-q4_0.gguf"
    private var isModelLoaded = false
    
    init() {
        setupLLM()
    }
    
    // MARK: - LLM Setup
    private func setupLLM() {
        Task {
            await loadModel()
        }
    }
    
    private func loadModel() async {
        logger.info("Loading LLM model: \(self.modelName)")
        
        // Get the path to the downloaded model
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let modelPath = homeDirectory
            .appendingPathComponent("Documents")
            .appendingPathComponent("Tiffin")
            .appendingPathComponent("models")
            .appendingPathComponent(modelName)
        
        // Check if model file exists
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            logger.error("Model file not found at: \(modelPath.path)")
            return
        }
        
        logger.info("Found model at: \(modelPath.path)")
        
        // Initialize Kuzco with the model
        self.kuzco = Kuzco.shared
        self.isModelLoaded = true
        self.logger.info("Kuzco initialized successfully with model: \(self.modelName)")
    }
    
    // MARK: - Chat Interface
    func sendMessage(_ message: String, context: ModelContext) async {
        guard !message.isEmpty && !isProcessing else { return }
        
        // Add user message
        let userMessage = ChatMessage(role: .user, content: message, timestamp: Date())
        await MainActor.run {
            chatMessages.append(userMessage)
            isProcessing = true
            currentResponse = ""
        }
        
        // Search for relevant transcripts
        let relevantTranscripts = await searchTranscripts(for: message, context: context)
        
        // Generate response
        await generateResponse(for: message, with: relevantTranscripts)
    }
    
    private func generateResponse(for userMessage: String, with transcripts: [TranscriptSegment]) async {
        // Build context with relevant transcripts
        let contextInfo = buildContextFromTranscripts(transcripts)
        
        let systemPrompt = """
        You are Tiffin AI, an assistant that helps users find information from their recorded audio transcriptions.
        You have access to the user's transcription history and can answer questions about what was discussed.
        
        Context from transcriptions:
        \(contextInfo)
        
        Guidelines:
        - Answer questions based on the provided transcription context
        - If you don't find relevant information in the transcripts, say so clearly
        - Be concise but helpful
        - Include approximate timestamps when relevant
        """
        
        // Use real Kuzco LLM
        guard let kuzco = self.kuzco else {
            await MainActor.run {
                currentResponse = "Model not loaded. Please try again."
                let assistantMessage = ChatMessage(role: .assistant, content: currentResponse, timestamp: Date())
                chatMessages.append(assistantMessage)
                isProcessing = false
                currentResponse = ""
            }
            return
        }
        
        let dialogue = [
            Turn(role: .system, text: systemPrompt),
            Turn(role: .user, text: userMessage)
        ]
        
        do {
            // Get the model path
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
            let modelPath = homeDirectory
                .appendingPathComponent("Documents")
                .appendingPathComponent("Tiffin")
                .appendingPathComponent("models")
                .appendingPathComponent(modelName)
            
            // Create model profile for Phi-3
            let modelProfile = ModelProfile(
                sourcePath: modelPath.path,
                architecture: .phiGeneric
            )
            
            // Start streaming prediction
            let stream = try await kuzco.predict(
                dialogue: dialogue,
                systemPrompt: systemPrompt,
                with: modelProfile,
                instanceSettings: .performanceFocused,
                predictionConfig: .creative
            )
            
            // Stream tokens as they arrive
            for try await token in stream {
                await MainActor.run {
                    currentResponse += token
                }
            }
            
        } catch {
            logger.error("Kuzco generation error: \(error)")
            await MainActor.run {
                currentResponse = "Sorry, I encountered an error processing your request: \(error.localizedDescription)"
            }
        }
        
        // Finalize response
        await MainActor.run {
            let assistantMessage = ChatMessage(role: .assistant, content: currentResponse, timestamp: Date())
            chatMessages.append(assistantMessage)
            isProcessing = false
            currentResponse = ""
        }
    }
    
    // MARK: - Transcript Search
    private func searchTranscripts(for query: String, context: ModelContext) async -> [TranscriptSegment] {
        let searchTerms = extractSearchTerms(from: query)
        
        var results: [TranscriptSegment] = []
        
        do {
            // Search through transcriptions
            let descriptor = FetchDescriptor<AudioRecording>(
                sortBy: [SortDescriptor(\.recordingDate, order: .reverse)]
            )
            let recordings = try context.fetch(descriptor)
            
            for recording in recordings {
                // Simple text search in transcripts
                if let transcriptPath = recording.transcriptPath,
                   let transcriptContent = loadTranscriptContent(from: transcriptPath) {
                    
                    let segments = searchInTranscript(transcriptContent, for: searchTerms, recording: recording)
                    results.append(contentsOf: segments)
                }
            }
        } catch {
            logger.error("Error searching transcripts: \(error)")
        }
        
        // Return top 10 most relevant results
        return Array(results.prefix(10))
    }
    
    private func extractSearchTerms(from query: String) -> [String] {
        // Extract meaningful keywords from the query
        let words = query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 2 }
            .filter { !["what", "when", "where", "how", "why", "did", "was", "were", "the", "and", "for", "with"].contains($0) }
        
        return Array(Set(words)) // Remove duplicates
    }
    
    private func loadTranscriptContent(from path: String) -> String? {
        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            logger.error("Failed to load transcript: \(error)")
            return nil
        }
    }
    
    private func searchInTranscript(_ content: String, for terms: [String], recording: AudioRecording) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let lowercaseLine = line.lowercased()
            let matchCount = terms.reduce(0) { count, term in
                count + (lowercaseLine.contains(term) ? 1 : 0)
            }
            
            if matchCount > 0 {
                // Get surrounding context (previous and next lines)
                let startIndex = max(0, index - 1)
                let endIndex = min(lines.count - 1, index + 1)
                let contextLines = Array(lines[startIndex...endIndex])
                
                // Create segment with estimated timing (since we don't have real timing data)
                let estimatedStartTime = TimeInterval(index * 3) // 3 seconds per line estimate
                let estimatedEndTime = estimatedStartTime + TimeInterval(contextLines.count * 3)
                let confidence = Double(matchCount) / Double(terms.count)
                
                let segment = TranscriptSegment(
                    startTime: estimatedStartTime,
                    endTime: estimatedEndTime,
                    text: contextLines.joined(separator: "\n"),
                    confidence: confidence
                )
                segments.append(segment)
            }
        }
        
        return segments.sorted { ($0.confidence ?? 0) > ($1.confidence ?? 0) }
    }
    
    private func buildContextFromTranscripts(_ transcripts: [TranscriptSegment]) -> String {
        guard !transcripts.isEmpty else {
            return "No relevant transcripts found."
        }
        
        let context = transcripts.enumerated().map { index, segment in
            return """
            [\(index + 1)] Time: \(segment.formattedTimeRange)
            \(segment.text)
            """
        }.joined(separator: "\n\n")
        
        return context
    }
    

    
    // MARK: - Utility Methods
    func clearChat() {
        chatMessages.removeAll()
    }
}

// MARK: - Data Models
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: ChatRole
    let content: String
    let timestamp: Date
}

enum ChatRole {
    case user
    case assistant
}

// Extension for AudioRecording to provide filename
extension AudioRecording {
    var filename: String? {
        // Try to get filename from processFileURL or microphoneFileURL
        if let processURL = processFileURL {
            return processURL.lastPathComponent
        }
        if let micURL = microphoneFileURL {
            return micURL.lastPathComponent
        }
        return title
    }
} 