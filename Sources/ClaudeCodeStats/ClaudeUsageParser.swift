import Foundation

/// Parsed Claude Code usage data
struct ClaudeUsage: Sendable {
    var sessionPercentLeft: Int?
    var weeklyPercentLeft: Int?
    var opusPercentLeft: Int?
    var sessionResetDescription: String?
    var weeklyResetDescription: String?
    var opusResetDescription: String?
    var accountEmail: String?
    var plan: String?
    var rawOutput: String = ""

    var hasData: Bool {
        sessionPercentLeft != nil
    }
}

/// Fetches and parses Claude Code CLI usage data
actor ClaudeUsageFetcher {
    private var lastUsage: ClaudeUsage?
    private var isFetching = false

    func fetch() async -> ClaudeUsage {
        guard !isFetching else { return lastUsage ?? ClaudeUsage() }
        isFetching = true
        defer { isFetching = false }

        do {
            let output = try await runClaudeCLI()
            let usage = Self.parse(output: output)
            lastUsage = usage
            return usage
        } catch {
            var usage = ClaudeUsage()
            usage.rawOutput = "Error: \(error.localizedDescription)"
            return usage
        }
    }

    /// Runs `claude` CLI in non-interactive mode to get usage info
    private func runClaudeCLI() async throws -> String {
        let binaryPath = Self.findClaudeBinary()
        guard let binaryPath else {
            throw ClaudeError.notInstalled
        }

        // Use `claude --usage` or fall back to parsing `/usage` output
        // First try the direct API approach
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        // claude -p "/usage" --output-format text runs a prompt that shows usage
        // But the best approach is to use the built-in /usage command
        // We'll use `script` to create a pseudo-terminal for the claude CLI
        let scriptProcess = Process()
        scriptProcess.executableURL = URL(fileURLWithPath: "/usr/bin/script")

        let pipe = Pipe()
        let errorPipe = Pipe()

        // Use script command to provide a PTY for claude
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude_usage_\(ProcessInfo.processInfo.processIdentifier).txt")

        scriptProcess.arguments = ["-q", tempFile.path, binaryPath, "--print-usage"]
        scriptProcess.standardOutput = pipe
        scriptProcess.standardError = errorPipe

        // Set environment to avoid interactive prompts
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        scriptProcess.environment = env

        // Try direct approach first: claude with print-usage flag
        let directProcess = Process()
        directProcess.executableURL = URL(fileURLWithPath: binaryPath)
        directProcess.arguments = ["--print-usage"]
        directProcess.standardOutput = pipe
        directProcess.standardError = errorPipe
        directProcess.environment = env

        try directProcess.run()

        // Wait with timeout
        let deadline = Date().addingTimeInterval(15)
        while directProcess.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        if directProcess.isRunning {
            directProcess.terminate()
            throw ClaudeError.timeout
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if output.isEmpty || directProcess.terminationStatus != 0 {
            // Fall back to reading from config/state files
            return try readFromStateFiles()
        }

        return output
    }

    /// Read usage from Claude's local state files as fallback
    private func readFromStateFiles() throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Claude Code stores state in ~/.claude/
        let stateDir = home.appendingPathComponent(".claude")

        // Try reading the settings/state file
        let possiblePaths = [
            stateDir.appendingPathComponent("state.json"),
            stateDir.appendingPathComponent("usage.json"),
            stateDir.appendingPathComponent("settings.json"),
        ]

        for path in possiblePaths {
            if let data = try? Data(contentsOf: path),
               let content = String(data: data, encoding: .utf8) {
                return content
            }
        }

        throw ClaudeError.noData
    }

    static func findClaudeBinary() -> String? {
        // Check common locations
        let paths = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(NSHomeDirectory())/.claude/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
            "\(NSHomeDirectory())/.npm-global/bin/claude",
        ]

        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try which
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {}

        return nil
    }

    // MARK: - Parsing

    static func parse(output: String) -> ClaudeUsage {
        var usage = ClaudeUsage()
        usage.rawOutput = output

        let clean = stripANSI(output)
        let lines = clean.components(separatedBy: .newlines)

        // Try JSON parsing first
        if let jsonUsage = parseJSON(output) {
            return jsonUsage
        }

        // Parse text output (from /usage command)
        usage.sessionPercentLeft = extractPercent(
            label: "Current session",
            lines: lines
        )

        usage.weeklyPercentLeft = extractPercent(
            label: "Current week (all models)",
            lines: lines
        )

        usage.opusPercentLeft = extractPercent(
            labels: ["Current week (Opus)", "Current week (Sonnet only)", "Current week (Sonnet)"],
            lines: lines
        )

        // Fallback: collect all percentages in order
        if usage.sessionPercentLeft == nil {
            let percents = allPercents(lines)
            if percents.count >= 1 { usage.sessionPercentLeft = percents[0] }
            if percents.count >= 2 { usage.weeklyPercentLeft = percents[1] }
            if percents.count >= 3 { usage.opusPercentLeft = percents[2] }
        }

        // Extract reset descriptions
        usage.sessionResetDescription = extractReset(label: "Current session", lines: lines)
        usage.weeklyResetDescription = extractReset(label: "Current week", lines: lines)
        usage.opusResetDescription = extractReset(labels: ["Opus", "Sonnet"], lines: lines)

        // Extract account info
        usage.accountEmail = extractField(patterns: [
            #"Account:\s+(\S+@\S+)"#,
            #"Email:\s+(\S+@\S+)"#,
        ], text: clean)

        usage.plan = extractField(patterns: [
            #"(?i)(Claude\s+(?:Max|Pro|Team|Enterprise|Ultra))"#,
        ], text: clean)

        return usage
    }

    /// Parse JSON format usage data
    private static func parseJSON(_ text: String) -> ClaudeUsage? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var usage = ClaudeUsage()
        usage.rawOutput = text

        if let session = json["sessionPercentLeft"] as? Int {
            usage.sessionPercentLeft = session
        }
        if let weekly = json["weeklyPercentLeft"] as? Int {
            usage.weeklyPercentLeft = weekly
        }
        if let opus = json["opusPercentLeft"] as? Int {
            usage.opusPercentLeft = opus
        }
        if let email = json["accountEmail"] as? String {
            usage.accountEmail = email
        }

        return usage.hasData ? usage : nil
    }

    /// Strip ANSI escape codes
    static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\x1B\[[0-9;]*[a-zA-Z]"#,
            with: "",
            options: .regularExpression
        ).replacingOccurrences(
            of: #"\x1B\][^\x07]*\x07"#,
            with: "",
            options: .regularExpression
        )
    }

    /// Extract percentage near a label
    private static func extractPercent(label: String, lines: [String]) -> Int? {
        extractPercent(labels: [label], lines: lines)
    }

    private static func extractPercent(labels: [String], lines: [String]) -> Int? {
        let normalizedLabels = labels.map { normalizeForSearch($0) }

        for (idx, line) in lines.enumerated() {
            let normalizedLine = normalizeForSearch(line)
            guard normalizedLabels.contains(where: { normalizedLine.contains($0) }) else { continue }

            // Search in a window of lines after the label
            let window = lines[idx..<min(idx + 12, lines.count)]
            for candidate in window {
                if let pct = percentFromLine(candidate) {
                    return pct
                }
            }
        }
        return nil
    }

    /// Extract a percentage from a single line
    private static func percentFromLine(_ line: String) -> Int? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(\d{1,3}(?:\.\d+)?)\s*%"#
        ) else { return nil }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges >= 2,
              let valRange = Range(match.range(at: 1), in: line),
              let rawVal = Double(line[valRange]) else { return nil }

        let clamped = max(0, min(100, rawVal))
        let lower = line.lowercased()

        if ["used", "spent", "consumed"].contains(where: lower.contains) {
            return Int((100 - clamped).rounded())
        }
        if ["left", "remaining", "available"].contains(where: lower.contains) {
            return Int(clamped.rounded())
        }
        return nil
    }

    /// Collect all percentages from lines
    private static func allPercents(_ lines: [String]) -> [Int] {
        lines.compactMap { percentFromLine($0) }
    }

    /// Extract reset time description
    private static func extractReset(label: String, lines: [String]) -> String? {
        extractReset(labels: [label], lines: lines)
    }

    private static func extractReset(labels: [String], lines: [String]) -> String? {
        let normalizedLabels = labels.map { normalizeForSearch($0) }

        for (idx, line) in lines.enumerated() {
            let normalizedLine = normalizeForSearch(line)
            guard normalizedLabels.contains(where: { normalizedLine.contains($0) }) else { continue }

            let window = lines[idx..<min(idx + 14, lines.count)]
            for candidate in window {
                if candidate.lowercased().contains("reset") {
                    let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed
                }
            }
        }
        return nil
    }

    /// Extract a field value using regex patterns
    private static func extractField(patterns: [String], text: String) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: range),
               match.numberOfRanges >= 2,
               let valRange = Range(match.range(at: 1), in: text) {
                return String(text[valRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func normalizeForSearch(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

enum ClaudeError: LocalizedError {
    case notInstalled
    case timeout
    case noData
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: "Claude CLI is not installed or not found in PATH"
        case .timeout: "Claude CLI timed out"
        case .noData: "No usage data available"
        case .parseFailed(let msg): "Parse failed: \(msg)"
        }
    }
}
