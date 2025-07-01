import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared
    @State private var showingDirectoryPicker = false
    @State private var showingResetAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Recordings Directory", systemImage: "folder")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button("Change") {
                                showingDirectoryPicker = true
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Location:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(settings.recordingsDirectoryPath)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                                .textSelection(.enabled)
                        }
                        
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                                .font(.caption)
                            
                            Text("All recordings and transcripts will be saved to this location")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Choose where Tiffin saves your audio recordings and transcripts. The AI chat feature will search for transcripts in this directory.")
                }
                
                Section {
                    Button("Reset to Default Location") {
                        showingResetAlert = true
                    }
                    .foregroundColor(.orange)
                } footer: {
                    Text("This will reset the recordings directory to ~/Documents/TiffinRecordings")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let selectedURL = urls.first {
                    // Start accessing security-scoped resource
                    _ = selectedURL.startAccessingSecurityScopedResource()
                    defer { selectedURL.stopAccessingSecurityScopedResource() }
                    
                    settings.setCustomRecordingsDirectory(selectedURL)
                }
            case .failure(let error):
                print("Directory selection failed: \(error)")
            }
        }
        .alert("Reset Directory", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
            }
        } message: {
            Text("This will reset the recordings directory to the default location. Your existing recordings will not be moved or deleted.")
        }
    }
}

#Preview {
    SettingsView()
} 