//
//  AudioRecordingManager.swift
//  tiffin
//
//  Created by Steven Jarosz (Ping) on 6/26/25.
//

import Foundation
import Combine
import audiosdk
import OSLog

@MainActor
class AudioRecordingManager: ObservableObject {
    @Published var isRecording = false
    @Published var currentDuration: TimeInterval = 0
    
    private let audioRecorder = AudioRecorder()
    private let logger = Logger(subsystem: "com.lunarclass.tiffin", category: "AudioRecordingManager")
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var recordingCompletion: ((URL?, URL?, TimeInterval) -> Void)?
    
    // File management
    private let recordingsDirectory: URL
    
    init() {
        // Create recordings directory in Documents
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.recordingsDirectory = documentsPath.appendingPathComponent("TiffinRecordings")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        
        setupAudioRecorder()
    }
    
    var formattedDuration: String {
        let minutes = Int(currentDuration) / 60
        let seconds = Int(currentDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func setupAudioRecorder() {
        // Set up post-processing handlers
        audioRecorder.postProcessingHandler = { [weak self] url in
            self?.logger.info("Process recording finished: \(url.path)")
        }
        
        audioRecorder.microphonePostProcessingHandler = { [weak self] url in
            self?.logger.info("Microphone recording finished: \(url.path)")
        }
    }
    
    func startRecording(
        pid: pid_t,
        processName: String,
        title: String,
        includeMicrophone: Bool,
        inputDeviceID: Int? = nil,
        completion: @escaping (URL?, URL?, TimeInterval) -> Void
    ) {
        guard !isRecording else {
            logger.warning("Attempted to start recording while already recording")
            return
        }
        
        logger.info("Starting recording - PID: \(pid), Process: \(processName), Include Mic: \(includeMicrophone), Input Device: \(inputDeviceID ?? -1)")
        
        self.recordingCompletion = completion
        
        // Create unique file names
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        
        let processFileName = "process_\(processName.replacingOccurrences(of: " ", with: "_"))_\(dateString).wav"
        let micFileName = "mic_\(processName.replacingOccurrences(of: " ", with: "_"))_\(dateString).wav"
        
        let processFileURL = recordingsDirectory.appendingPathComponent(processFileName)
        let micFileURL = includeMicrophone ? recordingsDirectory.appendingPathComponent(micFileName) : nil
        
        do {
            try audioRecorder.startRecording(
                pid: pid,
                outputFile: processFileURL,
                microphoneFile: micFileURL,
                outputDeviceID: nil, // Use default output device
                inputDeviceID: inputDeviceID // Pass the selected input device
            )
            
            // Start recording state
            isRecording = true
            currentDuration = 0
            recordingStartTime = Date()
            
            // Start timer for duration updates
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updateDuration()
                }
            }
            
            logger.info("Recording started successfully")
            
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            // Could add error handling UI here
        }
    }
    
    func stopRecording() {
        guard isRecording else {
            logger.warning("Attempted to stop recording when not recording")
            return
        }
        
        logger.info("Stopping recording")
        
        let finalDuration = currentDuration
        
        // Stop the audio recorder
        audioRecorder.stopRecording()
        
        // Stop timer and reset state
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        recordingStartTime = nil
        
        // Call completion handler with final details
        if let completion = recordingCompletion {
            // Get the file URLs from the recorder if available
            let processFileURL = getLastProcessFileURL()
            let micFileURL = audioRecorder.currentMicrophoneFileURL
            
            completion(processFileURL, micFileURL, finalDuration)
            recordingCompletion = nil
        }
        
        currentDuration = 0
        logger.info("Recording stopped")
    }
    
    private func updateDuration() {
        guard let startTime = recordingStartTime else { return }
        currentDuration = Date().timeIntervalSince(startTime)
    }
    
    private func getLastProcessFileURL() -> URL? {
        // Since we can't directly get the process file URL from the recorder,
        // we'll construct it based on our naming convention
        // This is a limitation we could improve by enhancing the SDK
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        
        // Look for recently created files
        let contents = try? FileManager.default.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: [.creationDateKey])
        
        let recentProcessFiles = contents?.filter { url in
            url.lastPathComponent.starts(with: "process_") &&
            url.pathExtension == "wav"
        }.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return date1 > date2
        }
        
        return recentProcessFiles?.first
    }
    
    // MARK: - Utility Methods
    
    func getRecordingsDirectory() -> URL {
        return recordingsDirectory
    }
    
    func clearAllRecordings() {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: nil)
            for fileURL in contents {
                try FileManager.default.removeItem(at: fileURL)
            }
            logger.info("Cleared all recordings from directory")
        } catch {
            logger.error("Failed to clear recordings: \(error.localizedDescription)")
        }
    }
} 