import Foundation
import SwiftUI

@Observable
class SettingsManager {
    static let shared = SettingsManager()
    
    // MARK: - Settings Keys
    private enum SettingsKeys {
        static let recordingsDirectory = "recordingsDirectory"
    }
    
    // MARK: - Default Values
    private let defaultRecordingsDirectoryName = "TiffinRecordings"
    
    // MARK: - Published Properties
    var recordingsDirectory: URL {
        get {
            if let savedPath = UserDefaults.standard.string(forKey: SettingsKeys.recordingsDirectory),
               !savedPath.isEmpty {
                return URL(fileURLWithPath: savedPath)
            } else {
                // Return default path in Documents
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                return documentsPath.appendingPathComponent(defaultRecordingsDirectoryName)
            }
        }
        set {
            UserDefaults.standard.set(newValue.path, forKey: SettingsKeys.recordingsDirectory)
            createDirectoryIfNeeded(at: newValue)
        }
    }
    
    // MARK: - Computed Properties
    var recordingsDirectoryPath: String {
        return recordingsDirectory.path
    }
    
    var recordingsDirectoryDisplayName: String {
        return recordingsDirectory.lastPathComponent
    }
    
    // MARK: - Initialization
    private init() {
        // Ensure the default directory exists on first launch
        createDirectoryIfNeeded(at: recordingsDirectory)
    }
    
    // MARK: - Directory Management
    private func createDirectoryIfNeeded(at url: URL) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create recordings directory: \(error)")
        }
    }
    
    func validateDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
    
    func setCustomRecordingsDirectory(_ url: URL) {
        guard validateDirectory(url) else {
            print("Invalid directory selected: \(url.path)")
            return
        }
        
        recordingsDirectory = url
    }
    
    // MARK: - Reset to Defaults
    func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: SettingsKeys.recordingsDirectory)
        createDirectoryIfNeeded(at: recordingsDirectory)
    }
} 