//
//  ProcessDiscovery.swift
//  AudioSDK
//
//  Enumerates and looks up audio-capable processes.
//

import Foundation
import AudioToolbox
import Darwin
import OSLog

public struct ProcessDiscovery {
    private static let logger = Logger(subsystem: "com.lunarclass.audiosdk", category: "ProcessDiscovery")
    
    /// Returns a list of running processes that are audio-capable (i.e., have a valid CoreAudio object).
    public static func listAudioCapableProcesses() -> [(pid: pid_t, name: String)] {
        var result: [(pid_t, String)] = []
        var procCount = proc_listallpids(nil, 0)
        guard procCount > 0 else { 
            logger.warning("No processes found")
            return [] 
        }
        
        logger.info("Found \(procCount) total processes, checking for audio capability...")
        
        var pids = [pid_t](repeating: 0, count: Int(procCount))
        procCount = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        
        var checkedProcesses = 0
        var audioCapableCount = 0
        
        for pid in pids where pid > 0 {
            checkedProcesses += 1
            var nameBuf = [CChar](repeating: 0, count: 1024)
            let nameResult = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let procName = nameResult > 0 ? String(cString: nameBuf) : "(unknown)"
            
            do {
                _ = try AudioObjectID.translatePIDToProcessObjectID(pid: pid)
                result.append((pid, procName))
                audioCapableCount += 1
            } catch {
                // Log first few failures for debugging
                if checkedProcesses <= 10 {
                   // logger.debug("Process \(procName, privacy: .public) [PID: \(pid)] is not //audio-capable: \(error.localizedDescription, privacy: .public)")
                }
                continue
            }
        }
        return result
    }

    /// Returns the PID of the first audio-capable process matching the given name (case-insensitive).
    public static func pidForAudioCapableProcess(named name: String) -> pid_t? {
        let procs = listAudioCapableProcesses()
        return procs.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.pid
    }

    /// Returns a list of all running processes as a debugging/fallback option.
    ///
    /// This function enumerates all running processes on the system and returns their PID and name,
    /// regardless of whether they have CoreAudio capabilities. This is useful for debugging when
    /// no audio-capable processes are found.
    ///
    /// - Returns: An array of (pid, name) tuples for all running processes.
    /// - Note: This includes system processes and processes that may not be audio-capable.
    public static func listAllProcesses() -> [(pid: pid_t, name: String)] {
        var result: [(pid_t, String)] = []
        var procCount = proc_listallpids(nil, 0)
        guard procCount > 0 else {
            logger.warning("No processes found during full process enumeration")
            return result
        }
        
        var pids = Array<pid_t>(repeating: 0, count: Int(procCount))
        procCount = proc_listallpids(&pids, procCount * Int32(MemoryLayout<pid_t>.size))
        guard procCount > 0 else {
            logger.warning("Failed to retrieve process list during full enumeration")
            return result
        }
        
        let actualCount = Int(procCount)
        logger.debug("Found \(actualCount) total processes during full enumeration")
        
        for i in 0..<actualCount {
            let pid = pids[i]
            guard pid > 0 else { continue }
            
            // Get process name using the same method as listAudioCapableProcesses
            var nameBuf = [CChar](repeating: 0, count: 1024)
            let nameResult = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let procName = nameResult > 0 ? String(cString: nameBuf) : "(unknown)"
            
            result.append((pid, procName))
        }
        
        logger.info("Returning \(result.count) total processes")
        return result
    }
} 
