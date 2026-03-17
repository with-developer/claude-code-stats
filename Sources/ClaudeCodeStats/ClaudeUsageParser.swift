import Foundation

/// Parsed Claude Code usage data
struct ClaudeUsage: Sendable {
    var sessionPercentLeft: Int?
    var weeklyPercentLeft: Int?
    var opusPercentLeft: Int?
    var sonnetPercentLeft: Int?
    var sessionResetDescription: String?
    var weeklyResetDescription: String?
    var opusResetDescription: String?
    var sonnetResetDescription: String?
    var accountEmail: String?
    var plan: String?
    var rawOutput: String = ""
    var dataSource: String = ""

    var hasData: Bool {
        sessionPercentLeft != nil
    }
}

/// Fetches and parses Claude Code usage data via multiple strategies
actor ClaudeUsageFetcher {
    private var lastUsage: ClaudeUsage?
    private var isFetching = false

    func fetch() async -> ClaudeUsage {
        guard !isFetching else { return lastUsage ?? ClaudeUsage() }
        isFetching = true
        defer { isFetching = false }

        // Strategy 1: OAuth API (preferred, like codexbar)
        if let usage = await fetchViaOAuth() {
            lastUsage = usage
            return usage
        }

        // Strategy 2: CLI
        if let usage = await fetchViaCLI() {
            lastUsage = usage
            return usage
        }

        var usage = ClaudeUsage()
        usage.rawOutput = "Failed to fetch usage data"
        return usage
    }

    // MARK: - OAuth API Strategy

    private func fetchViaOAuth() async -> ClaudeUsage? {
        guard let token = readOAuthToken() else { return nil }

        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code-stats/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            return Self.parseOAuthResponse(data)
        } catch {
            return nil
        }
    }

    /// Read OAuth token from macOS Keychain (same approach as codexbar)
    private func readOAuthToken() -> String? {
        // Check environment variable first
        if let token = ProcessInfo.processInfo.environment["CLAUDE_OAUTH_TOKEN"], !token.isEmpty {
            return token
        }

        // Try macOS Keychain via security command
        let keychainServices = [
            "Claude Code-credentials",
            "claude-code-credentials",
            "com.anthropic.claude-code",
        ]

        for service in keychainServices {
            if let token = readKeychainItem(service: service) {
                return token
            }
        }

        // Try reading from credential files
        let home = FileManager.default.homeDirectoryForCurrentUser
        let credentialPaths = [
            home.appendingPathComponent(".claude/credentials.json"),
            home.appendingPathComponent(".claude/.credentials.json"),
        ]

        for path in credentialPaths {
            if let data = try? Data(contentsOf: path),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let token = json["accessToken"] as? String { return token }
                if let token = json["access_token"] as? String { return token }
                if let token = json["oauthToken"] as? String { return token }
                if let claudeAI = json["claude.ai"] as? [String: Any],
                   let token = claudeAI["accessToken"] as? String { return token }
            }
        }

        return nil
    }

    private func readKeychainItem(service: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let raw, !raw.isEmpty else { return nil }

            // The keychain value might be JSON containing the token
            if let jsonData = raw.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                // Check nested claudeAiOauth structure (actual Claude Code format)
                if let oauth = json["claudeAiOauth"] as? [String: Any],
                   let token = oauth["accessToken"] as? String { return token }
                if let token = json["accessToken"] as? String { return token }
                if let token = json["access_token"] as? String { return token }
            }

            // Or it might be the token directly
            if raw.hasPrefix("eyJ") || raw.contains("ant-") {
                return raw
            }

            return nil
        } catch {
            return nil
        }
    }

    /// Parse OAuth API response
    static func parseOAuthResponse(_ data: Data) -> ClaudeUsage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var usage = ClaudeUsage()
        usage.dataSource = "oauth"
        usage.rawOutput = String(data: data, encoding: .utf8) ?? ""

        // Parse windows: five_hour (session), seven_day (weekly), seven_day_opus, seven_day_sonnet
        // utilization comes as percentage (e.g. 17.0 = 17% used)
        func percentLeft(from utilization: Double) -> Int {
            let used = utilization > 1.0 ? utilization : utilization * 100
            return max(0, min(100, Int((100.0 - used).rounded())))
        }

        if let fiveHour = json["five_hour"] as? [String: Any] {
            if let utilization = fiveHour["utilization"] as? Double {
                usage.sessionPercentLeft = percentLeft(from: utilization)
            }
            if let resetsAt = fiveHour["resets_at"] as? String {
                usage.sessionResetDescription = formatResetTime(resetsAt)
            }
        }

        if let sevenDay = json["seven_day"] as? [String: Any] {
            if let utilization = sevenDay["utilization"] as? Double {
                usage.weeklyPercentLeft = percentLeft(from: utilization)
            }
            if let resetsAt = sevenDay["resets_at"] as? String {
                usage.weeklyResetDescription = formatResetTime(resetsAt)
            }
        }

        if let opus = json["seven_day_opus"] as? [String: Any] {
            if let utilization = opus["utilization"] as? Double {
                usage.opusPercentLeft = percentLeft(from: utilization)
            }
            if let resetsAt = opus["resets_at"] as? String {
                usage.opusResetDescription = formatResetTime(resetsAt)
            }
        }

        if let sonnet = json["seven_day_sonnet"] as? [String: Any] {
            if let utilization = sonnet["utilization"] as? Double {
                usage.sonnetPercentLeft = percentLeft(from: utilization)
            }
            if let resetsAt = sonnet["resets_at"] as? String {
                usage.sonnetResetDescription = formatResetTime(resetsAt)
            }
        }

        return usage.hasData ? usage : nil
    }

    /// Format ISO 8601 reset time to human-readable relative string
    private static func formatResetTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Try with fractional seconds first, then without
        let date: Date? = formatter.date(from: isoString) ?? {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: isoString)
        }()

        guard let date else {
            return "Resets: \(isoString)"
        }

        let now = Date()
        let interval = date.timeIntervalSince(now)

        if interval <= 0 {
            return "Reset time passed"
        }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 24 {
            let days = hours / 24
            let remainHours = hours % 24
            return "Resets in \(days)d \(remainHours)h"
        } else if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }

    // MARK: - CLI Strategy

    private func fetchViaCLI() async -> ClaudeUsage? {
        guard let binaryPath = Self.findClaudeBinary() else { return nil }

        do {
            let output = try await runClaudeCLI(binaryPath: binaryPath)
            var usage = Self.parseCLIOutput(output: output)
            if usage.hasData {
                usage.dataSource = "cli"
                return usage
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Run claude CLI to get usage info
    private func runClaudeCLI(binaryPath: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["-p", "/usage", "--output-format", "text"]

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        // Remove CLAUDECODE env var to avoid nested session detection
        env.removeValue(forKey: "CLAUDECODE")
        process.environment = env

        try process.run()

        // Wait with timeout
        let deadline = Date().addingTimeInterval(15)
        while process.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        if process.isRunning {
            process.terminate()
            throw ClaudeError.timeout
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func findClaudeBinary() -> String? {
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

    // MARK: - CLI Output Parsing

    static func parseCLIOutput(output: String) -> ClaudeUsage {
        var usage = ClaudeUsage()
        usage.rawOutput = output

        let clean = stripANSI(output)
        let lines = clean.components(separatedBy: .newlines)

        // Try JSON parsing first
        if let jsonUsage = parseJSON(output) {
            return jsonUsage
        }

        // Parse text output line-by-line
        usage.sessionPercentLeft = extractPercent(
            labels: ["Current session", "5-hour", "five hour", "session"],
            lines: lines
        )

        usage.weeklyPercentLeft = extractPercent(
            labels: ["Current week (all models)", "weekly (all", "7-day", "seven day"],
            lines: lines
        )

        usage.opusPercentLeft = extractPercent(
            labels: ["Current week (Opus)", "weekly (Opus)", "opus"],
            lines: lines
        )

        usage.sonnetPercentLeft = extractPercent(
            labels: ["Current week (Sonnet)", "weekly (Sonnet)", "sonnet only"],
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
        usage.sessionResetDescription = extractReset(labels: ["Current session", "session"], lines: lines)
        usage.weeklyResetDescription = extractReset(labels: ["Current week", "weekly"], lines: lines)
        usage.opusResetDescription = extractReset(labels: ["Opus"], lines: lines)
        usage.sonnetResetDescription = extractReset(labels: ["Sonnet"], lines: lines)

        // Extract account info
        usage.accountEmail = extractField(patterns: [
            #"Account:\s+(\S+@\S+)"#,
            #"Email:\s+(\S+@\S+)"#,
        ], text: clean)

        usage.plan = extractField(patterns: [
            #"(?i)(Claude\s+(?:Max|Pro|Team|Enterprise|Ultra))"#,
            #"(?i)Plan:\s*(Max|Pro|Team|Enterprise|Ultra)"#,
        ], text: clean)

        return usage
    }

    private static func parseJSON(_ text: String) -> ClaudeUsage? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var usage = ClaudeUsage()
        usage.rawOutput = text
        usage.dataSource = "json"

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
            of: #"\x1B\[[0-?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        ).replacingOccurrences(
            of: #"\x1B\][^\x07]*\x07"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func extractPercent(labels: [String], lines: [String]) -> Int? {
        let normalizedLabels = labels.map { normalizeForSearch($0) }

        for (idx, line) in lines.enumerated() {
            let normalizedLine = normalizeForSearch(line)
            guard normalizedLabels.contains(where: { normalizedLine.contains($0) }) else { continue }

            let window = lines[idx..<min(idx + 12, lines.count)]
            for candidate in window {
                if let pct = percentFromLine(candidate) {
                    return pct
                }
            }
        }
        return nil
    }

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
        // Ambiguous - assume "left"
        return Int(clamped.rounded())
    }

    private static func allPercents(_ lines: [String]) -> [Int] {
        lines.compactMap { percentFromLine($0) }
    }

    private static func extractReset(labels: [String], lines: [String]) -> String? {
        let normalizedLabels = labels.map { normalizeForSearch($0) }

        for (idx, line) in lines.enumerated() {
            let normalizedLine = normalizeForSearch(line)
            guard normalizedLabels.contains(where: { normalizedLine.contains($0) }) else { continue }

            let window = lines[idx..<min(idx + 14, lines.count)]
            for candidate in window {
                let lower = candidate.lowercased()
                if lower.contains("reset") {
                    return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                // Also match date patterns like "Dec 23 at 4:00PM"
                if let regex = try? NSRegularExpression(
                    pattern: #"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}"#,
                    options: .caseInsensitive
                ) {
                    let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
                    if regex.firstMatch(in: candidate, range: range) != nil {
                        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            return "Resets: \(trimmed)"
                        }
                    }
                }
            }
        }
        return nil
    }

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
