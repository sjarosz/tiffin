//
//  ContentView.swift
//  tiffin
//
//  Created by Steven Jarosz (Ping) on 6/26/25.
//

import SwiftUI
import SwiftData
import audiosdk
import OSLog
import AppKit
import CoreAudio
import transcribe

// MARK: - Audio Device Model
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let isDefault: Bool
    
    init(deviceInfo: AudioDeviceInfo, isDefault: Bool = false) {
        self.id = deviceInfo.id
        self.name = deviceInfo.name
        self.isDefault = isDefault
    }
}

// MARK: - Process Info Model
struct ProcessInfo: Identifiable, Hashable {
    let id = UUID()
    let pid: pid_t
    let name: String
    let displayName: String
    let iconName: String
    
    init(pid: pid_t, name: String, whitelistedProcess: WhitelistedProcess) {
        self.pid = pid
        self.name = name
        self.displayName = whitelistedProcess.displayName
        self.iconName = whitelistedProcess.iconName ?? "app.fill"
    }
}

// MARK: - Whitelisted Process Model
struct WhitelistedProcess: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var displayName: String
    var iconName: String?
    
    init(name: String, displayName: String? = nil, iconName: String? = nil) {
        self.name = name
        self.displayName = displayName ?? name
        self.iconName = iconName
    }
    
    static func == (lhs: WhitelistedProcess, rhs: WhitelistedProcess) -> Bool {
        return lhs.name == rhs.name && lhs.displayName == rhs.displayName
    }
    
    enum CodingKeys: String, CodingKey {
        case name, displayName, iconName
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decode(String.self, forKey: .displayName)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        id = UUID()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(iconName, forKey: .iconName)
    }
}

// MARK: - Process Settings
class ProcessSettings: ObservableObject {
    @Published var whitelistedProcesses: [WhitelistedProcess] = []
    
    private let userDefaults = UserDefaults.standard
    private let whitelistKey = "ProcessWhitelist"
    
    init() {
        loadFromUserDefaults()
        if whitelistedProcesses.isEmpty {
            setupDefaultProcesses()
        }
    }
    
    private func setupDefaultProcesses() {
        whitelistedProcesses = [
            WhitelistedProcess(name: "zoom.us", displayName: "Zoom", iconName: "video.fill"),
            WhitelistedProcess(name: "Google Chrome", displayName: "Chrome", iconName: "globe"),
            WhitelistedProcess(name: "Safari", displayName: "Safari", iconName: "safari.fill"),
            WhitelistedProcess(name: "Microsoft Teams", displayName: "Teams", iconName: "person.3.fill"),
            WhitelistedProcess(name: "Cisco Webex Meetings", displayName: "Webex", iconName: "video.fill"),
            WhitelistedProcess(name: "Discord", displayName: "Discord", iconName: "message.fill"),
            WhitelistedProcess(name: "Slack", displayName: "Slack", iconName: "bubble.left.and.bubble.right.fill"),
            WhitelistedProcess(name: "Skype", displayName: "Skype", iconName: "phone.fill"),
            WhitelistedProcess(name: "VLC media player", displayName: "VLC", iconName: "play.fill"),
            WhitelistedProcess(name: "QuickTime Player", displayName: "QuickTime", iconName: "play.rectangle.fill")
        ]
        saveToUserDefaults()
    }
    
    private func saveToUserDefaults() {
        if let encoded = try? JSONEncoder().encode(whitelistedProcesses) {
            userDefaults.set(encoded, forKey: whitelistKey)
        }
    }
    
    private func loadFromUserDefaults() {
        if let data = userDefaults.data(forKey: whitelistKey),
           let decoded = try? JSONDecoder().decode([WhitelistedProcess].self, from: data) {
            whitelistedProcesses = decoded
        }
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var recordingManager = AudioRecordingManager()
    @StateObject private var processSettings = ProcessSettings()
    
    // Audio devices
    @State private var inputDevices: [AudioDevice] = []
    @State private var selectedInputDevice: AudioDevice?
    
    // Process selection
    @State private var availableProcesses: [ProcessInfo] = []
    @State private var selectedProcess: ProcessInfo?
    
    // UI state
    @State private var showingSettings = false
    @State private var lastScanTime: String = "Never"
    @State private var isTranscribing = false
    @State private var transcriptionCountdown = 0
    
    // Auto-refresh timer
    @State private var refreshTimer: Timer?
    @State private var transcriptionTimer: Timer?
    
    private let logger = Logger(subsystem: "com.lunarclass.tiffin", category: "ContentView")
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            Divider()
            
            // Main Content - Just the control panel now
            controlPanel
        }
        .onAppear {
            refreshDevicesAndProcesses()
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
        .sheet(isPresented: $showingSettings) {
            ProcessSettingsView(processSettings: processSettings)
        }
        .onChange(of: processSettings.whitelistedProcesses) { _, _ in
            refreshProcesses()
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            Text("Tiffin")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            // Folder access button
            Button(action: openRecordingsFolder) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                    Text("Recordings")
                }
            }
            .buttonStyle(.bordered)
            .help("Open recordings folder in Finder")
            
            Button("Settings") {
                showingSettings = true
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Control Panel
    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Microphone Selection
            microphoneSection
            
            Divider()
            
            // Process Selection
            processSection
            
            Divider()
            
            // Recording Controls
            recordingControlsSection
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(.blue)
                Text("Microphone")
                    .font(.headline)
            }
            
            if inputDevices.isEmpty {
                Text("No microphones found")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                Picker("Select Microphone", selection: $selectedInputDevice) {
                    ForEach(inputDevices, id: \.id) { device in
                        HStack {
                            Text(device.name)
                            if device.isDefault {
                                Text("(Default)")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        .tag(device as AudioDevice?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private var processSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "app.fill")
                    .foregroundColor(.green)
                Text("Audio Process")
                    .font(.headline)
                
                Spacer()
                
                Button(action: refreshProcesses) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh processes")
            }
            
            if availableProcesses.isEmpty {
                VStack(spacing: 8) {
                    Text("No audio processes running")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Text("Last scan: \(lastScanTime)")
                        .foregroundColor(.secondary)
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(availableProcesses) { process in
                        ProcessCard(
                            process: process,
                            isSelected: selectedProcess?.pid == process.pid,
                            action: { selectedProcess = process }
                        )
                    }
                }
            }
        }
    }
    
    private var recordingControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "record.circle.fill")
                    .foregroundColor(.red)
                Text("Recording")
                    .font(.headline)
            }
            
            // Record/Stop Button
            if recordingManager.isRecording {
                VStack(spacing: 8) {
                    Button("Stop Recording") {
                        stopRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.red)
                    .frame(maxWidth: .infinity)
                    
                    Text("Duration: \(recordingManager.formattedDuration)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                }
            } else if isTranscribing {
                VStack(spacing: 8) {
                    Button("Transcribing...") {
                        // No action - disabled during transcription
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.orange)
                    .frame(maxWidth: .infinity)
                    .disabled(true)
                    
                    if transcriptionCountdown > 0 {
                        Text("Waiting: \(transcriptionCountdown)s")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Processing transcription...")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                Button("Start Recording") {
                    startRecording()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(selectedProcess == nil || selectedInputDevice == nil)
            }
        }
    }
    
    // MARK: - Helper Methods
    private func refreshDevicesAndProcesses() {
        refreshInputDevices()
        refreshProcesses()
    }
    
    private func refreshInputDevices() {
        let devices = AudioRecorder.listInputAudioDevices()
        
        // Get the default input device ID (this should be implemented in the SDK)
        // For now, we'll just mark the first device as default
        inputDevices = devices.enumerated().map { index, deviceInfo in
            AudioDevice(deviceInfo: deviceInfo, isDefault: index == 0)
        }
        
        // Select default device if none selected
        if selectedInputDevice == nil {
            selectedInputDevice = inputDevices.first { $0.isDefault } ?? inputDevices.first
        }
    }
    
    private func refreshProcesses() {
        let processes = AudioRecorder.listAudioCapableProcesses()
        availableProcesses = []
        
        for process in processes {
            if let whitelisted = processSettings.whitelistedProcesses.first(where: { whitelistedProcess in
                process.name.lowercased().contains(whitelistedProcess.name.lowercased()) ||
                whitelistedProcess.name.lowercased().contains(process.name.lowercased())
            }) {
                let processInfo = ProcessInfo(pid: process.pid, name: process.name, whitelistedProcess: whitelisted)
                availableProcesses.append(processInfo)
            }
        }
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        lastScanTime = formatter.string(from: Date())
        
        logger.info("Found \(availableProcesses.count) whitelisted processes out of \(processes.count) total")
    }
    
    private func startRecording() {
        guard let process = selectedProcess,
              let inputDevice = selectedInputDevice else { return }
        
        let title = "\(process.displayName) Recording"
        
        recordingManager.startRecording(
            pid: process.pid,
            processName: process.name,
            title: title,
            includeMicrophone: true,
            inputDeviceID: Int(inputDevice.id)
        ) { processFileURL, microphoneFileURL, duration in
            // Save to SwiftData
            let recording = AudioRecording(
                title: title,
                processName: process.displayName,
                pid: process.pid,
                recordingDate: Date(),
                duration: duration,
                processFileURL: processFileURL,
                microphoneFileURL: microphoneFileURL,
                fileSize: getFileSize(processFileURL) + getFileSize(microphoneFileURL),
                isProcessRecording: processFileURL != nil,
                isMicrophoneRecording: microphoneFileURL != nil
            )
            
            modelContext.insert(recording)
        }
    }
    
    private func stopRecording() {
        recordingManager.stopRecording()
        
        // Start transcription process after 5 second delay
        Task { @MainActor in
            isTranscribing = true
            transcriptionCountdown = 5
            
            // Start countdown timer
            transcriptionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                Task { @MainActor in
                    transcriptionCountdown -= 1
                    if transcriptionCountdown <= 0 {
                        timer.invalidate()
                        await performTranscription()
                    }
                }
            }
        }
    }
    
    private func performTranscription() async {
        logger.info("Starting transcription process")
        
        // Get the most recent recording files
        let recordingsDir = recordingManager.getRecordingsDirectory()
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: [.creationDateKey])
            
            // Get recently created audio files (within last 5 minutes)
            let recentFiles = contents.filter { url in
                url.pathExtension == "wav" &&
                (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate?.timeIntervalSinceNow ?? -3600 > -300
            }.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 > date2
            }
            
            logger.info("Found \(recentFiles.count) recent audio files to transcribe")
            
            // Transcribe each file
            for audioFileURL in recentFiles {
                await transcribeFile(audioFileURL)
            }
            
        } catch {
            logger.error("Failed to list recordings directory: \(error.localizedDescription)")
        }
        
        // Reset transcription state
        await MainActor.run {
            isTranscribing = false
            transcriptionCountdown = 0
            transcriptionTimer?.invalidate()
            transcriptionTimer = nil
        }
        
        logger.info("Transcription process completed")
    }
    
    private func transcribeFile(_ audioFileURL: URL) async {
        logger.info("Transcribing file: \(audioFileURL.lastPathComponent)")
        
        do {
            // Use local Whisper for transcription with GPU acceleration
            let result = try await TranscribeEngine.transcribe(
                audioURL: audioFileURL,
                service: .whisperLocal,
                language: "auto"
            )
            
            let performanceInfo = result.modelUsed.contains("GPU") ? " with GPU acceleration" : " with CPU"
            logger.info("Transcription completed\(performanceInfo) for \(audioFileURL.lastPathComponent)")
            logger.info("Text length: \(result.text.count), Segments: \(result.segments.count)")
            
            // Save transcript to file in the same directory
            let transcriptFileName = audioFileURL.deletingPathExtension().appendingPathExtension("txt")
            let transcriptTimestampURL = audioFileURL.deletingPathExtension().appendingPathExtension("json")
            
            // Save plain text transcript
            try result.text.write(to: transcriptFileName, atomically: true, encoding: .utf8)
            logger.info("Saved transcript to: \(transcriptFileName.lastPathComponent)")
            
            // Save timestamped transcript if available
            if !result.segments.isEmpty {
                let segments = result.segments.map { segment in
                    TranscriptSegment(
                        startTime: segment.startTime,
                        endTime: segment.endTime,
                        text: segment.text,
                        confidence: segment.confidence != nil ? Double(segment.confidence!) : nil
                    )
                }
                
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let segmentsData = try encoder.encode(segments)
                try segmentsData.write(to: transcriptTimestampURL)
                logger.info("Saved timestamped transcript to: \(transcriptTimestampURL.lastPathComponent)")
            }
            
        } catch {
            logger.error("Failed to transcribe \(audioFileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }
    
    private func getFileSize(_ url: URL?) -> Int64 {
        guard let url = url else { return 0 }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? Int64 ?? 0
    }
    
    private func openRecordingsFolder() {
        let folderURL = recordingManager.getRecordingsDirectory()
        NSWorkspace.shared.open(folderURL)
    }
    
    private func startAutoRefresh() {
        // Refresh processes every 10 seconds to detect newly launched apps
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            refreshProcesses()
        }
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        transcriptionTimer?.invalidate()
        transcriptionTimer = nil
    }
}

// MARK: - Process Card View
struct ProcessCard: View {
    let process: ProcessInfo
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: process.iconName)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .blue)
                
                Text(process.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                Text("PID: \(process.pid)")
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Process Settings View
struct ProcessSettingsView: View {
    @ObservedObject var processSettings: ProcessSettings
    @Environment(\.dismiss) private var dismiss
    @State private var newProcessName = ""
    @State private var newDisplayName = ""
    @State private var showingAddProcess = false
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Manage the list of processes that will appear for recording selection.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                List {
                    ForEach(Array(processSettings.whitelistedProcesses.enumerated()), id: \.element.id) { index, process in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(process.displayName)
                                    .font(.headline)
                                Text(process.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button("Remove") {
                                processSettings.whitelistedProcesses.remove(at: index)
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.red)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Spacer()
                
                Button("Add New Process") {
                    showingAddProcess = true
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
            }
            .navigationTitle("Process Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Add Process", isPresented: $showingAddProcess) {
                TextField("Process name", text: $newProcessName)
                TextField("Display name", text: $newDisplayName)
                Button("Add") {
                    if !newProcessName.isEmpty {
                        let displayName = newDisplayName.isEmpty ? newProcessName : newDisplayName
                        processSettings.whitelistedProcesses.append(
                            WhitelistedProcess(name: newProcessName, displayName: displayName, iconName: "app.fill")
                        )
                        newProcessName = ""
                        newDisplayName = ""
                    }
                }
                Button("Cancel", role: .cancel) {
                    newProcessName = ""
                    newDisplayName = ""
                }
            } message: {
                Text("Enter the exact process name and an optional display name.")
            }
        }
        .frame(width: 500, height: 400)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: AudioRecording.self, inMemory: true)
}
