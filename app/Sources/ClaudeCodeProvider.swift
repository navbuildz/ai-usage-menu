import Foundation
import Darwin

struct CommandOutput {
    var status: Int32
    var stdout: String
    var stderr: String
}

// Drain both pipes while the child runs, including when a verbose CLI fills stderr.
enum LocalCommand {
    enum Failure: Error { case timedOut, oversized }
    static func run(_ binary: URL, _ arguments: [String], in directory: URL, timeout: TimeInterval = 20) throws -> CommandOutput {
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        let handles = [output.fileHandleForReading, errors.fileHandleForReading]
        for handle in handles {
            let fd = handle.fileDescriptor
            guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0 else { throw POSIXError(.EIO) }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        try process.run()
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        var buffers = [Data(), Data()]
        var bytes = [UInt8](repeating: 0, count: 16384)
        var finished = [false,false]
        while process.isRunning || finished.contains(false) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure.timedOut }
            for index in handles.indices where !finished[index] {
                let count = Darwin.read(handles[index].fileDescriptor, &bytes, bytes.count)
                if count > 0 {
                    buffers[index].append(contentsOf: bytes.prefix(count))
                    if buffers[index].count > 4 * 1024 * 1024 { throw Failure.oversized }
                } else if count == 0 { finished[index] = true }
                else if errno != EWOULDBLOCK && errno != EINTR { throw POSIXError(.EIO) }
            }
            if process.isRunning || finished.contains(false) { Thread.sleep(forTimeInterval: 0.005) }
        }
        return .init(status: process.terminationStatus, stdout: String(decoding: buffers[0], as: UTF8.self), stderr: String(decoding: buffers[1], as: UTF8.self))
    }
}

actor ClaudeCodeProvider: Provider {
    let id = "claude", displayName = "Claude Code", glyph = "provider-claude-code"
    private var cached: URL?
    private var version: String?
    private var attemptedShell = false
    private var lastOverride: String?
    private let workdir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AI Usage Menu/claude-workdir")

    func resolve() -> URL? {
        let override = UserDefaults.standard.string(forKey: "claudePath")
        if override != lastOverride || cached.map({ !FileManager.default.isExecutableFile(atPath: $0.path) }) == true {
            cached = nil; version = nil; attemptedShell = false; lastOverride = override
        }
        if let cached { return cached }
        var paths = [override, "~/.local/bin/claude", "~/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"].compactMap { $0 }
        paths = paths.map { ($0 as NSString).expandingTildeInPath }
        if let found = paths.first(where: FileManager.default.isExecutableFile(atPath:)) {
            cached = URL(fileURLWithPath: found)
        } else if !attemptedShell {
            attemptedShell = true
            if let shell = try? LocalCommand.run(URL(fileURLWithPath: "/bin/zsh"), ["-lc","command -v claude"], in: URL(fileURLWithPath: "/")),
               let path = shell.stdout.split(separator: "\n").last.map(String.init), path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) { cached = URL(fileURLWithPath: path) }
        }
        return cached
    }

    func isAvailable() -> Bool { resolve() != nil }
    func read() -> ProviderSnapshot {
        guard let binary = resolve() else { return .init(asOf: Date(), state: .notInstalled) }
        do {
            try FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
            let output = try LocalCommand.run(binary, ["-p","/usage","--output-format","json","--no-session-persistence","--strict-mcp-config","--mcp-config",#"{"mcpServers":{}}"#,"--setting-sources","project,local"], in: workdir)
            struct Envelope: Decodable { let result: String }
            let body = (try? JSONDecoder().decode(Envelope.self, from: Data(output.stdout.utf8)))?.result ?? output.stdout
            var snapshot = ClaudeParser.parse(body.isEmpty ? output.stderr : body, now: Date())
            if output.status != 0, snapshot.state != .signedOut, !(snapshot.state == .nonSubscription && !body.isEmpty && output.stderr.isEmpty) {
                return .init(asOf: Date(), state: .failed(output.stderr.isEmpty ? body : output.stderr))
            }
            if version == nil, let result = try? LocalCommand.run(binary, ["--version"], in: workdir), result.status == 0 {
                version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let version { snapshot.details.append(.init(label: "Claude Code", value: version)) }
            return snapshot
        } catch LocalCommand.Failure.timedOut { return .init(asOf: Date(), state: .timedOut) }
        catch { return .init(asOf: Date(), state: .failed(error.localizedDescription)) }
    }
}
