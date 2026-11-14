import CoreGraphics
import Darwin
import Foundation

struct VirtualHiDPISession: Hashable {
    let displayID: UInt32
    let virtualDisplayID: UInt32
    let target: DisplayResolutionTarget
    let originalMode: DisplayMode
    /// Actual mirror-source rate reported by CoreGraphics, not a requested rate.
    let refreshRate: Double
}

@MainActor
final class VirtualHiDPIService {
    private(set) var session: VirtualHiDPISession?
    var isRunning: Bool { process?.isRunning == true }

    private struct Snapshot {
        let displayID: UInt32
        let modeID: UInt32
        let origin: CGPoint
        let helperURL: URL
    }

    private struct HelperMessage: Decodable {
        let event: String
        let message: String?
        let displayID: UInt32?
        let virtualDisplayID: UInt32?
        let width: Int?
        let height: Int?
        let pixelWidth: Int?
        let pixelHeight: Int?
        let refreshRate: Double?
    }

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var snapshot: Snapshot?
    private var received = Data()
    private var readBuffer = [UInt8](repeating: 0, count: 4096)
    private let decoder = JSONDecoder()

    func start(display: DisplayDevice, target: DisplayResolutionTarget) async throws {
        try Task.checkCancellation()
        if process != nil || snapshot != nil { try stop() }
        guard display.isOnline, !display.isBuiltin, abs(display.rotation) < 0.01,
              CGDisplayIsOnline(display.id) != 0, CGDisplayIsBuiltin(display.id) == 0,
              CGDisplayIsInMirrorSet(display.id) == 0, abs(CGDisplayRotation(display.id)) < 0.01 else {
            throw LocalizedServiceError(key: "virtual.error.unsupportedDisplay")
        }
        guard target.width > 0, target.height > 0, target.width <= 4096, target.height <= 4096 else {
            throw LocalizedServiceError(key: "virtual.error.dimensions")
        }
        guard let previous = CGDisplayCopyDisplayMode(display.id), let originalMode = display.currentMode else {
            throw LocalizedServiceError(key: "virtual.error.captureMode")
        }
        let helperURL = try locateHelper()
        let saved = Snapshot(displayID: display.id, modeID: UInt32(bitPattern: previous.ioDisplayModeID),
                             origin: CGDisplayBounds(display.id).origin, helperURL: helperURL)
        let currentRate = previous.refreshRate
        let nativeRate = display.nativeMode?.refreshRate ?? currentRate
        let refreshRate = currentRate >= 24 ? currentRate : nativeRate
        guard refreshRate.isFinite, refreshRate >= 24, refreshRate <= 240 else {
            throw LocalizedServiceError(key: "virtual.error.refreshRate")
        }
        let child = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        child.executableURL = helperURL
        child.arguments = [String(display.id), String(target.width), String(target.height), String(refreshRate)]
        child.standardInput = stdinPipe
        child.standardOutput = stdoutPipe
        child.standardError = FileHandle.standardError
        let lease = stdinPipe.fileHandleForWriting
        let reader = stdoutPipe.fileHandleForReading
        guard fcntl(reader.fileDescriptor, F_SETFL, O_NONBLOCK) != -1 else {
            throw LocalizedServiceError(key: "virtual.error.pipe")
        }
        try child.run()
        // Parent must not retain its own copy of the child's stdin read end;
        // closing this write end is the app-crash/normal-exit lifetime lease.
        stdinPipe.fileHandleForReading.closeFile()
        stdoutPipe.fileHandleForWriting.closeFile()
        process = child
        input = lease
        output = reader
        snapshot = saved
        received.removeAll(keepingCapacity: true)
        do {
            let deadline = ContinuousClock.now.advanced(by: .seconds(24))
            while ContinuousClock.now < deadline {
                try Task.checkCancellation()
                // stop() may have run while the prepare task was suspended.
                guard process === child else { throw CancellationError() }
                for message in try drainMessages(reader) {
                    if message.event == "error" {
                        throw LocalizedServiceError(key: "virtual.error.helper", detail: message.message)
                    }
                    guard message.event == "ready" else { continue }
                    guard message.displayID == display.id, let virtualID = message.virtualDisplayID, virtualID != 0,
                          message.width == target.width, message.height == target.height,
                          message.pixelWidth == target.width * 2, message.pixelHeight == target.height * 2,
                          let actualRate = message.refreshRate, actualRate.isFinite, actualRate > 0,
                          CGDisplayMirrorsDisplay(display.id) == virtualID else {
                        throw LocalizedServiceError(key: "virtual.error.mismatch")
                    }
                    try Task.checkCancellation()
                    session = VirtualHiDPISession(displayID: display.id, virtualDisplayID: virtualID,
                                                 target: target, originalMode: originalMode, refreshRate: actualRate)
                    return
                }
                guard child.isRunning else {
                    throw LocalizedServiceError(key: "virtual.error.exitedEarly", arguments: [String(child.terminationStatus)])
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw LocalizedServiceError(key: "virtual.error.activationTimeout")
        } catch {
            // Never tear down a newer start that replaced this suspended task.
            if process === child {
                do { try stop() } catch let restorationError {
                    throw LocalizedServiceError(key: "virtual.error.cleanup",
                                                arguments: [error.localizedDescription, restorationError.localizedDescription])
                }
            }
            throw error
        }
    }

    /// EOF requests a targeted session-only restore and releases CGVirtualDisplay.
    /// CG transactions can stall during disconnect; both subprocess waits are
    /// bounded and a stuck process is killed, never waited on indefinitely.
    func stop() throws {
        guard let saved = snapshot else { session = nil; return }
        var needsRestore = true
        var cleanupFailure: Error?
        input?.closeFile()
        input = nil
        if let child = process {
            let exited = waitForExit(child, seconds: 1.5)
            if !exited {
                kill(child.processIdentifier, SIGKILL)
                _ = waitForExit(child, seconds: 0.25)
            }
            var messages: [HelperMessage] = []
            if let output {
                do { messages = try drainMessages(output) }
                catch { cleanupFailure = error }
                output.closeFile()
            }
            needsRestore = !exited || child.terminationStatus != 0 || !messages.contains(where: { $0.event == "stopped" })
            if cleanupFailure == nil, let message = messages.last(where: { $0.event == "error" })?.message {
                cleanupFailure = LocalizedServiceError(key: "virtual.error.helper", detail: message)
            }
            if cleanupFailure == nil, needsRestore, session != nil {
                cleanupFailure = LocalizedServiceError(key: exited ? "virtual.error.exitedUnexpectedly" : "virtual.error.shutdownTimeout")
            }
        }
        process = nil
        output = nil
        received.removeAll(keepingCapacity: true)
        // Keep the original snapshot/session if fallback fails, so another
        // explicit stop can retry restoration instead of losing the only copy.
        if needsRestore { try restore(saved) }
        session = nil
        snapshot = nil
        if let cleanupFailure { throw cleanupFailure }
    }

    private func locateHelper() throws -> URL {
        let name = "PixelFitVirtualDisplayHelper"
        var candidates: [URL] = []
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent(name))
        }
        // SwiftPM's standalone executable may not have a bundle executableURL.
        candidates.append(URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            .deletingLastPathComponent().appendingPathComponent(name))
        if let result = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return result
        }
        throw LocalizedServiceError(key: "virtual.error.missingHelper", arguments: [name])
    }

    private func drainMessages(_ reader: FileHandle) throws -> [HelperMessage] {
        while true {
            let count = readBuffer.withUnsafeMutableBytes { bytes in
                Darwin.read(reader.fileDescriptor, bytes.baseAddress, bytes.count)
            }
            if count > 0 { received.append(contentsOf: readBuffer.prefix(count)); continue }
            if count == 0 || errno == EAGAIN || errno == EWOULDBLOCK { break }
            if errno == EINTR { continue }
            throw LocalizedServiceError(key: "virtual.error.read", arguments: [String(errno)])
        }
        var messages: [HelperMessage] = []
        while let newline = received.firstIndex(of: 10) {
            let line = received[..<newline]
            if !line.isEmpty { messages.append(try decoder.decode(HelperMessage.self, from: line)) }
            received.removeSubrange(...newline)
        }
        return messages
    }

    private func waitForExit(_ child: Process, seconds: Double) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while child.isRunning, ProcessInfo.processInfo.systemUptime < deadline { usleep(10_000) }
        return !child.isRunning
    }

    private func restore(_ saved: Snapshot) throws {
        guard CGDisplayIsOnline(saved.displayID) != 0 else { return }
        let child = Process()
        let pipe = Pipe()
        child.executableURL = saved.helperURL
        child.arguments = ["--restore", String(saved.displayID), String(saved.modeID),
                           String(Int32(saved.origin.x)), String(Int32(saved.origin.y))]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = pipe
        child.standardError = FileHandle.standardError
        let reader = pipe.fileHandleForReading
        guard fcntl(reader.fileDescriptor, F_SETFL, O_NONBLOCK) != -1 else {
            throw LocalizedServiceError(key: "virtual.error.pipe")
        }
        try child.run()
        pipe.fileHandleForWriting.closeFile()
        defer { reader.closeFile(); received.removeAll(keepingCapacity: true) }
        guard waitForExit(child, seconds: 1.5) else {
            kill(child.processIdentifier, SIGKILL)
            _ = waitForExit(child, seconds: 0.25)
            throw LocalizedServiceError(key: "virtual.error.restoreTimeout")
        }
        let messages = try drainMessages(reader)
        guard child.terminationStatus == 0, messages.contains(where: { $0.event == "stopped" }) else {
            throw LocalizedServiceError(key: "virtual.error.restoreFailed",
                                        detail: messages.last(where: { $0.event == "error" })?.message)
        }
    }
}
