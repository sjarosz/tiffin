//
//  AudioRecording.swift
//  tiffin
//
//  Created by Steven Jarosz (Ping) on 6/26/25.
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

@Model
final class AudioRecording {
    var id: UUID
    var title: String
    var processName: String
    var pid: pid_t
    var recordingDate: Date
    var duration: TimeInterval
    var processFileURL: URL?
    var microphoneFileURL: URL?
    var fileSize: Int64
    var isProcessRecording: Bool
    var isMicrophoneRecording: Bool
    
    // Transcription properties - made optional for backward compatibility
    var transcriptText: String?
    var transcriptTimestamps: Data? // JSON-encoded timestamp data
    var _transcriptionStatus: String? // Internal storage
    var transcriptionDate: Date?
    var transcriptionLanguage: String?
    var transcriptionModelUsed: String?
    var transcriptionError: String?
    
    init(
        title: String,
        processName: String,
        pid: pid_t,
        recordingDate: Date = Date(),
        duration: TimeInterval = 0,
        processFileURL: URL? = nil,
        microphoneFileURL: URL? = nil,
        fileSize: Int64 = 0,
        isProcessRecording: Bool = false,
        isMicrophoneRecording: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.processName = processName
        self.pid = pid
        self.recordingDate = recordingDate
        self.duration = duration
        self.processFileURL = processFileURL
        self.microphoneFileURL = microphoneFileURL
        self.fileSize = fileSize
        self.isProcessRecording = isProcessRecording
        self.isMicrophoneRecording = isMicrophoneRecording
        
        // Initialize transcription properties
        self.transcriptText = nil
        self.transcriptTimestamps = nil
        self._transcriptionStatus = TranscriptionStatus.notStarted.rawValue
        self.transcriptionDate = nil
        self.transcriptionLanguage = nil
        self.transcriptionModelUsed = nil
        self.transcriptionError = nil
    }
    
    // Computed property for transcription status with safe default
    var transcriptionStatus: TranscriptionStatus {
        get {
            guard let statusString = _transcriptionStatus,
                  let status = TranscriptionStatus(rawValue: statusString) else {
                return .notStarted
            }
            return status
        }
        set {
            _transcriptionStatus = newValue.rawValue
        }
    }
}

// Convenience computed properties
extension AudioRecording {
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }
    
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    var recordingTypeDescription: String {
        switch (isProcessRecording, isMicrophoneRecording) {
        case (true, true):
            return "Process + Mic"
        case (true, false):
            return "Process Only"
        case (false, true):
            return "Microphone Only"
        case (false, false):
            return "No Audio"
        }
    }
    
    var hasTranscript: Bool {
        return transcriptText != nil && !transcriptText!.isEmpty
    }
    
    var transcriptionStatusDescription: String {
        switch transcriptionStatus {
        case .notStarted:
            return "Not transcribed"
        case .inProgress:
            return "Transcribing..."
        case .completed:
            return "Transcribed"
        case .failed:
            return "Failed"
        }
    }
    
    var primaryAudioFileURL: URL? {
        return processFileURL ?? microphoneFileURL
    }
}

enum TranscriptionStatus: String, Codable, CaseIterable {
    case notStarted = "not_started"
    case inProgress = "in_progress" 
    case completed = "completed"
    case failed = "failed"
    
    var displayName: String {
        switch self {
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
}

// Transcript segment for timestamped transcription
struct TranscriptSegment: Codable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let confidence: Double?
    
    var formattedTimeRange: String {
        let startFormatter = DateComponentsFormatter()
        startFormatter.allowedUnits = [.minute, .second]
        startFormatter.zeroFormattingBehavior = .pad
        
        let endFormatter = DateComponentsFormatter()
        endFormatter.allowedUnits = [.minute, .second]
        endFormatter.zeroFormattingBehavior = .pad
        
        let start = startFormatter.string(from: startTime) ?? "00:00"
        let end = endFormatter.string(from: endTime) ?? "00:00"
        
        return "\(start) - \(end)"
    }
}

extension AudioRecording {
    func getTranscriptSegments() -> [TranscriptSegment] {
        guard let timestampData = transcriptTimestamps,
              let segments = try? JSONDecoder().decode([TranscriptSegment].self, from: timestampData) else {
            return []
        }
        return segments
    }
    
    func setTranscriptSegments(_ segments: [TranscriptSegment]) {
        self.transcriptTimestamps = try? JSONEncoder().encode(segments)
    }
}
