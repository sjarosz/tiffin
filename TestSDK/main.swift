import Foundation
import audiosdk
import OSLog
import transcribe
import Speech

let logger = Logger(subsystem: "com.lunarclass.tiffin.testsdk", category: "main")

// --- Discovery and Setup ---
logger.log("🔍 Searching for audio-capable processes...")
let audioCapableProcesses = AudioRecorder.listAudioCapableProcesses()

if audioCapableProcesses.isEmpty {
    logger.warning("⚠️ No audio-capable processes found. This may indicate no applications are currently using audio.")
} else {
    logger.log("✅ Found \(audioCapableProcesses.count) audio-capable processes:")
    for (index, process) in audioCapableProcesses.enumerated() {
        logger.log("  \(index + 1). PID: \(process.pid), Name: \(process.name)")
    }
}

// Look for QuickTime Player specifically
let processNameToFind = "QuickTime Player"
let targetPID: pid_t

if let targetProcess = audioCapableProcesses.first(where: { $0.name.contains(processNameToFind) }) {
    targetPID = targetProcess.pid
    logger.log("🎯 Found target process: PID \(targetPID), Name: \(targetProcess.name)")
} else {
    logger.warning("⚠️ Target process '\(processNameToFind)' not found. Available processes:")
    for process in audioCapableProcesses {
        logger.log("  - PID: \(process.pid), Name: \(process.name)")
    }
    
    if let firstProcess = audioCapableProcesses.first {
        targetPID = firstProcess.pid
        logger.log("🎯 Using first available process instead: PID \(targetPID), Name: \(firstProcess.name)")
    } else {
        logger.log("🎯 No audio processes found, using fallback (Finder)")
        targetPID = 1 // Fallback to a system process
    }
}

// --- Recording Setup ---
let recorder = AudioRecorder()
let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
let dateString = dateFormatter.string(from: Date())

// Create ~/Documents/recordings directory
let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let outputDir = documentsDir.appendingPathComponent("recordings")

do {
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
} catch {
    logger.error("❌ Failed to create recordings directory: \(error.localizedDescription)")
}

let outputFileURL = outputDir.appendingPathComponent("test-recording-\(dateString).wav")
let micFileURL = outputDir.appendingPathComponent("test-mic-\(dateString).wav")

logger.log("📁 Output directory: \(outputDir.path)")
logger.log("🎵 Process recording file: \(outputFileURL.lastPathComponent)")
logger.log("🎤 Microphone recording file: \(micFileURL.lastPathComponent)")

// --- Define async main function ---
@MainActor
func runMainProcess() async {
    do {
        logger.log("🎬 Starting recording session...")
        
        // Start recording using the correct API
        try recorder.startRecording(
            pid: targetPID,
            outputFile: outputFileURL,
            microphoneFile: micFileURL
        )
        
        logger.log("⏺️ Recording started successfully. Recording for 5 seconds...")
        try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        
        logger.log("⏹️ Stopping recording.")
        recorder.stopRecording()
        logger.log("✅ Recording session finished successfully.")
        
        // --- Transcribe the Recorded Audio Files ---
        logger.log("🎙️ Starting transcription of recorded audio files...")
        
        // Check for speech recognition permissions
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if authStatus != .authorized {
            logger.log("⚠️ Speech recognition not authorized (status: \(String(describing: authStatus)))")
            logger.log("🔄 Using whisper.cpp instead of Apple Speech Framework")
        } else {
            logger.log("✅ Speech recognition authorized, but using whisper.cpp for better performance")
        }
        
        // Transcribe process recording if it exists
        if FileManager.default.fileExists(atPath: outputFileURL.path) {
            logger.log("📝 Transcribing process recording: \(outputFileURL.lastPathComponent)")
            do {
                let processResult = try await TranscribeEngine.transcribe(
                    audioURL: outputFileURL, 
                    service: .whisperLocal  // Use whisper.cpp instead of Apple Speech Framework
                )
                logger.log("✅ Process transcription completed:")
                logger.log("   Language: \(processResult.language ?? "unknown")")
                logger.log("   Model: \(processResult.modelUsed)")
                logger.log("   Text: \(processResult.text)")
                
                // Save transcript to file
                let processTranscriptURL = outputDir.appendingPathComponent("process-transcript-\(dateString).txt")
                try processResult.text.write(to: processTranscriptURL, atomically: true, encoding: .utf8)
                logger.log("💾 Process transcript saved: \(processTranscriptURL.lastPathComponent)")
            } catch {
                logger.log("❌ Process transcription failed: \(error.localizedDescription)")
            }
        } else {
            logger.log("⚠️ Process recording file not found")
        }
        
        // Transcribe microphone recording if it exists
        if FileManager.default.fileExists(atPath: micFileURL.path) {
            logger.log("📝 Transcribing microphone recording: \(micFileURL.lastPathComponent)")
            do {
                let micResult = try await TranscribeEngine.transcribe(
                    audioURL: micFileURL, 
                    service: .whisperLocal  // Use whisper.cpp instead of Apple Speech Framework
                )
                logger.log("✅ Microphone transcription completed:")
                logger.log("   Language: \(micResult.language ?? "unknown")")
                logger.log("   Model: \(micResult.modelUsed)")
                logger.log("   Text: \(micResult.text)")
                
                // Save transcript to file
                let micTranscriptURL = outputDir.appendingPathComponent("mic-transcript-\(dateString).txt")
                try micResult.text.write(to: micTranscriptURL, atomically: true, encoding: .utf8)
                logger.log("💾 Microphone transcript saved: \(micTranscriptURL.lastPathComponent)")
            } catch {
                logger.log("❌ Microphone transcription failed: \(error.localizedDescription)")
            }
        } else {
            logger.log("⚠️ Microphone recording file not found")
        }
        
        logger.log("🎉 All tasks completed successfully!")
        
        // --- File Information ---
        if FileManager.default.fileExists(atPath: outputFileURL.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: outputFileURL.path)
            let fileSize = attributes[FileAttributeKey.size] as? Int64 ?? 0
            logger.log("📊 Process recording size: \(fileSize) bytes")
        }
        
        if FileManager.default.fileExists(atPath: micFileURL.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: micFileURL.path)
            let fileSize = attributes[FileAttributeKey.size] as? Int64 ?? 0
            logger.log("📊 Microphone recording size: \(fileSize) bytes")
        }
        
    } catch {
        logger.error("❌ An error occurred: \(error.localizedDescription)")
        logger.error("➡️ Details: \(error.localizedDescription)")
    }
}

// --- Start and Stop Recording ---
Task {
    await runMainProcess()
    exit(0)
}

// Keep main thread alive
RunLoop.main.run()
