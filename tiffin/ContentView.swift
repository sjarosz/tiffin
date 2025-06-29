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

// MARK: - Process Settings Model
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
        return lhs.id == rhs.id && lhs.name == rhs.name && lhs.displayName == rhs.displayName
    }
    
    // Custom CodingKeys to handle the id property properly
    enum CodingKeys: String, CodingKey {
        case name, displayName, iconName
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decode(String.self, forKey: .displayName)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        id = UUID() // Generate new ID when decoding
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(iconName, forKey: .iconName)
        // Don't encode ID since it's regenerated on decode
    }
}

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
            WhitelistedProcess(name: "Cisco Webex Meetings", displayName: "Webex", iconName: "video.fill"),
            WhitelistedProcess(name: "Google Chrome", displayName: "Chrome (Meet)", iconName: "globe"),
            WhitelistedProcess(name: "Safari", displayName: "Safari (Meet)", iconName: "safari.fill"),
            WhitelistedProcess(name: "zoom.us", displayName: "Zoom", iconName: "video.fill"),
            WhitelistedProcess(name: "Microsoft Teams", displayName: "Teams", iconName: "person.3.fill"),
            WhitelistedProcess(name: "Skype", displayName: "Skype", iconName: "phone.fill"),
            WhitelistedProcess(name: "Discord", displayName: "Discord", iconName: "message.fill"),
            WhitelistedProcess(name: "Slack", displayName: "Slack", iconName: "bubble.left.and.bubble.right.fill"),
            WhitelistedProcess(name: "VLC media player", displayName: "VLC", iconName: "play.fill"),
            WhitelistedProcess(name: "QuickTime Player", displayName: "QuickTime", iconName: "play.rectangle.fill")
        ]
        saveToUserDefaults()
    }
    
    func addProcess(name: String, displayName: String? = nil) {
        let process = WhitelistedProcess(name: name, displayName: displayName, iconName: "app.fill")
        whitelistedProcesses.append(process)
        saveToUserDefaults()
    }
    
    func removeProcess(at index: Int) {
        whitelistedProcesses.remove(at: index)
        saveToUserDefaults()
    }
    
    func updateProcess(at index: Int, name: String, displayName: String) {
        whitelistedProcesses[index].name = name
        whitelistedProcesses[index].displayName = displayName
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

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var recordings: [AudioRecording]
    
    @StateObject private var recordingManager = AudioRecordingManager()
    @StateObject private var processSettings = ProcessSettings()
    @State private var selectedProcess: (pid: pid_t, name: String)?
    @State private var availableProcesses: [(pid: pid_t, name: String)] = []
    @State private var filteredProcesses: [(pid: pid_t, name: String, whitelisted: WhitelistedProcess)] = []
    @State private var showingSettings = false
    @State private var recordingTitle = ""
    @State private var includeMicrophone = true
    @State private var processDiscoveryStatus = "Not checked"
    
    private let logger = Logger(subsystem: "com.lunarclass.tiffin", category: "ContentView")
    
    var body: some View {
        NavigationSplitView {
            VStack {
                // Recording Controls Section
                recordingControlsSection
                
                Divider()
                
                // Recordings List Section
                recordingsListSection
            }
            .navigationTitle("Tiffin Audio Recorder")
            .navigationSplitViewColumnWidth(min: 300, ideal: 400)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings") {
                        showingSettings = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        } detail: {
            if let selectedRecording = recordings.first {
                AudioRecordingDetailView(recording: selectedRecording)
            } else {
                Text("Select a recording to view details")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            refreshAvailableProcesses()
        }
        .sheet(isPresented: $showingSettings) {
            ProcessSettingsView(processSettings: processSettings)
        }
        .onChange(of: processSettings.whitelistedProcesses) { _, _ in
            filterProcesses()
        }
    }
    
    private var recordingControlsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recording Controls")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                // Available Processes Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Available Processes:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text(processDiscoveryStatus)
                            .font(.caption)
                            .foregroundColor(filteredProcesses.isEmpty ? .orange : .secondary)
                    }
                    
                    if filteredProcesses.isEmpty {
                        VStack(spacing: 8) {
                            Text("No whitelisted processes are currently running")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Refresh") {
                                refreshAvailableProcesses()
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                            ForEach(filteredProcesses, id: \.pid) { processInfo in
                                ProcessButton(
                                    processInfo: processInfo,
                                    isSelected: selectedProcess?.pid == processInfo.pid,
                                    action: {
                                        selectedProcess = (processInfo.pid, processInfo.name)
                                    }
                                )
                            }
                        }
                    }
                }
                
                Divider()
                
                // Recording Title
                HStack {
                    Text("Title:")
                    TextField("Recording title", text: $recordingTitle)
                        .textFieldStyle(.roundedBorder)
                }
                
                // Microphone Toggle
                Toggle("Include Microphone", isOn: $includeMicrophone)
                
                // Recording Button
                HStack {
                    if recordingManager.isRecording {
                        Button("Stop Recording") {
                            stopRecording()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.red)
                    } else {
                        Button("Start Recording") {
                            startRecording()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(selectedProcess == nil)
                    }
                    
                    if recordingManager.isRecording {
                        Text("Recording: \(recordingManager.formattedDuration)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
    
    private var recordingsListSection: some View {
        VStack(alignment: .leading) {
            Text("Recordings")
                .font(.headline)
                .padding(.horizontal)
            
            List {
                ForEach(recordings) { recording in
                    AudioRecordingRow(recording: recording)
                        .onTapGesture {
                            // Selection handled by NavigationSplitView
                        }
                }
                .onDelete(perform: deleteRecordings)
            }
        }
    }
    
    private func refreshAvailableProcesses() {
        logger.info("Refreshing available processes...")
        processDiscoveryStatus = "Searching for audio-capable processes..."
        
        availableProcesses = AudioRecorder.listAudioCapableProcesses()
        logger.info("Found \(availableProcesses.count) audio-capable processes")
        
        if availableProcesses.isEmpty {
            processDiscoveryStatus = "No audio-capable processes found"
            logger.warning("No audio-capable processes found - this may indicate no apps are currently using audio")
        } else {
            processDiscoveryStatus = "Found \(availableProcesses.count) audio-capable processes"
        }
        
        filterProcesses()
    }
    
    private func filterProcesses() {
        filteredProcesses = []
        for process in availableProcesses {
            if let whitelisted = processSettings.whitelistedProcesses.first(where: { 
                $0.name.lowercased().contains(process.name.lowercased()) || 
                process.name.lowercased().contains($0.name.lowercased()) 
            }) {
                filteredProcesses.append((process.pid, process.name, whitelisted))
            }
        }
        logger.info("Filtered to \(filteredProcesses.count) whitelisted processes from \(availableProcesses.count) total")
    }
    
    private func startRecording() {
        guard let process = selectedProcess else { return }
        
        let title = recordingTitle.isEmpty ? "Recording from \(process.name)" : recordingTitle
        
        recordingManager.startRecording(
            pid: process.pid,
            processName: process.name,
            title: title,
            includeMicrophone: includeMicrophone
        ) { processFileURL, microphoneFileURL, duration in
            // Save to SwiftData
            let recording = AudioRecording(
                title: title,
                processName: process.name,
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
            
            // Clear the title for next recording
            recordingTitle = ""
        }
    }
    
    private func stopRecording() {
        recordingManager.stopRecording()
    }
    
    private func deleteRecordings(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let recording = recordings[index]
                
                // Delete actual files
                if let processURL = recording.processFileURL {
                    try? FileManager.default.removeItem(at: processURL)
                }
                if let micURL = recording.microphoneFileURL {
                    try? FileManager.default.removeItem(at: micURL)
                }
                
                modelContext.delete(recording)
            }
        }
    }
    
    private func getFileSize(_ url: URL?) -> Int64 {
        guard let url = url else { return 0 }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? Int64 ?? 0
    }
}

// MARK: - Supporting Views

struct AudioRecordingRow: View {
    let recording: AudioRecording
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.title)
                        .font(.headline)
                    
                    HStack {
                        Text(recording.processName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(recording.formattedDuration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            HStack {
                Text(recording.recordingTypeDescription)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
                
                Spacer()
                
                Text(recording.formattedFileSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ProcessButton: View {
    let processInfo: (pid: pid_t, name: String, whitelisted: WhitelistedProcess)
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Icon
                Image(systemName: processInfo.whitelisted.iconName ?? "app.fill")
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .blue)
                
                // Process name
                VStack(spacing: 2) {
                    Text(processInfo.whitelisted.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)
                    
                    Text("PID: \(processInfo.pid)")
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
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
                        ProcessSettingRow(
                            process: process,
                            onUpdate: { name, displayName in
                                processSettings.updateProcess(at: index, name: name, displayName: displayName)
                            },
                            onDelete: {
                                processSettings.removeProcess(at: index)
                            }
                        )
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
        }
        .sheet(isPresented: $showingAddProcess) {
            AddProcessView(
                processName: $newProcessName,
                displayName: $newDisplayName,
                onAdd: {
                    processSettings.addProcess(name: newProcessName, displayName: newDisplayName.isEmpty ? nil : newDisplayName)
                    newProcessName = ""
                    newDisplayName = ""
                    showingAddProcess = false
                },
                onCancel: {
                    newProcessName = ""
                    newDisplayName = ""
                    showingAddProcess = false
                }
            )
        }
    }
}

struct ProcessSettingRow: View {
    let process: WhitelistedProcess
    let onUpdate: (String, String) -> Void
    let onDelete: () -> Void
    
    @State private var isEditing = false
    @State private var editedName: String
    @State private var editedDisplayName: String
    
    init(process: WhitelistedProcess, onUpdate: @escaping (String, String) -> Void, onDelete: @escaping () -> Void) {
        self.process = process
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self._editedName = State(initialValue: process.name)
        self._editedDisplayName = State(initialValue: process.displayName)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: process.iconName ?? "app.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    if isEditing {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Process Name", text: $editedName)
                                .textFieldStyle(.roundedBorder)
                            TextField("Display Name", text: $editedDisplayName)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        Text(process.displayName)
                            .font(.headline)
                        Text(process.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if isEditing {
                    HStack {
                        Button("Save") {
                            onUpdate(editedName, editedDisplayName)
                            isEditing = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        
                        Button("Cancel") {
                            editedName = process.name
                            editedDisplayName = process.displayName
                            isEditing = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    Menu {
                        Button("Edit") {
                            isEditing = true
                        }
                        Button("Delete", role: .destructive) {
                            onDelete()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddProcessView: View {
    @Binding var processName: String
    @Binding var displayName: String
    let onAdd: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add a new process to the whitelist. Enter the exact process name as it appears in Activity Monitor.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Process Name (required)")
                        .font(.headline)
                    TextField("e.g., Google Chrome", text: $processName)
                        .textFieldStyle(.roundedBorder)
                    Text("This should match the exact process name.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display Name (optional)")
                        .font(.headline)
                    TextField("e.g., Chrome", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                    Text("A shorter, friendly name to display in the app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Add Process")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd()
                    }
                    .disabled(processName.isEmpty)
                }
            }
        }
    }
}

struct AudioRecordingDetailView: View {
    let recording: AudioRecording
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(recording.title)
                        .font(.largeTitle)
                        .bold()
                }
                
                // Recording details
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recording Details")
                        .font(.headline)
                    
                    DetailRow(label: "Process", value: recording.processName)
                    DetailRow(label: "PID", value: String(recording.pid))
                    DetailRow(label: "Duration", value: recording.formattedDuration)
                    DetailRow(label: "File Size", value: recording.formattedFileSize)
                    DetailRow(label: "Type", value: recording.recordingTypeDescription)
                    DetailRow(label: "Date", value: recording.recordingDate.formatted())
                }
                
                // File paths
                if let processURL = recording.processFileURL {
                    VStack(alignment: .leading) {
                        Text("Process Audio File:")
                            .font(.headline)
                        Text(processURL.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
                
                if let micURL = recording.microphoneFileURL {
                    VStack(alignment: .leading) {
                        Text("Microphone Audio File:")
                            .font(.headline)
                        Text(micURL.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
                
                Spacer()
            }
            .padding()
        }
    }
}



struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: AudioRecording.self, inMemory: true)
}
