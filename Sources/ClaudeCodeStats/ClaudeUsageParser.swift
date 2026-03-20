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

    var sessionResetShort: String? {
        Self.shortReset(from: sessionResetDescription)
    }

    var weeklyResetShort: String? {
        Self.shortReset(from: weeklyResetDescription)
    }

    private static func shortReset(from description: String?) -> String? {
        guard let desc = description else { return nil }
        if desc.contains("passed") { return nil }
        let cleaned = desc
            .replacingOccurrences(of: "Resets in ", with: "")
            .replacingOccurrences(of: "Resets: ", with: "")
            .replacingOccurrences(of: " ", with: "")
        return cleaned.isEmpty ? nil : cleaned
    }
}

/// Fetches usage data via OAuth API only. No subprocess calls.
actor ClaudeUsageFetcher {
    private var lastUsage: ClaudeUsage?
    private var isFetching = false
    private var lastOAuthError: String?
    private var rateLimitedUntil: Date?

    func fetch() async -> ClaudeUsage {
        guard !isFetching else { return lastUsage ?? ClaudeUsage() }
        isFetching = true
        defer { isFetching = false }

        if let usage = await fetchViaOAuth() {
            lastUsage = usage
            return usage
        }

        var usage = ClaudeUsage()
        if readOAuthToken() == nil {
            usage.rawOutput = "Claude CLI 로그인이 필요합니다. 터미널에서 claude를 실행하여 로그인해주세요."
        } else if let oauthError = lastOAuthError {
            usage.rawOutput = oauthError
        } else {
            usage.rawOutput = "사용량 데이터를 가져올 수 없습니다."
        }
        return usage
    }

    /// Check if OAuth token exists (no keychain UI)
    static var hasToken: Bool {
        readCachedToken() != nil || readCredentialsFile() != nil
    }

    // MARK: - Version detection (from package.json, no subprocess)

    private static var _cachedVersion: String?

    private static var claudeVersion: String {
        if let v = _cachedVersion { return v }

        let home = NSHomeDirectory()
        var packagePaths = [
            "/usr/local/lib/node_modules/@anthropic-ai/claude-code/package.json",
            "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/package.json",
            "\(home)/.npm-global/lib/node_modules/@anthropic-ai/claude-code/package.json",
        ]

        // Check NVM paths (just list directory, safe location)
        let nvmDir = "\(home)/.nvm/versions/node"
        if let nodes = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            for node in nodes.sorted().reversed() {
                packagePaths.append("\(nvmDir)/\(node)/lib/node_modules/@anthropic-ai/claude-code/package.json")
            }
        }

        for path in packagePaths {
            if let data = FileManager.default.contents(atPath: path),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let version = json["version"] as? String {
                _cachedVersion = version
                return version
            }
        }

        _cachedVersion = "2.1.0"
        return _cachedVersion!
    }

    // MARK: - OAuth API

    private func fetchViaOAuth() async -> ClaudeUsage? {
        guard let token = readOAuthToken() else { return nil }

        if let until = rateLimitedUntil, Date() < until {
            let remaining = Int(until.timeIntervalSinceNow)
            lastOAuthError = "Rate limited. \(Self.formatSeconds(remaining)) 후 재시도"
            if let last = lastUsage, last.hasData {
                var cached = last
                cached.dataSource = "cached"
                return cached
            }
            return nil
        }

        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/\(Self.claudeVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            switch httpResponse.statusCode {
            case 200:
                lastOAuthError = nil
                rateLimitedUntil = nil
                return Self.parseOAuthResponse(data)
            case 429:
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap { Int($0) } ?? 60
                rateLimitedUntil = Date().addingTimeInterval(Double(retryAfter))
                lastOAuthError = "Rate limited (429). \(Self.formatSeconds(retryAfter)) 후 재시도"
                if let last = lastUsage, last.hasData {
                    var cached = last
                    cached.dataSource = "oauth (cached)"
                    return cached
                }
                return nil
            case 401:
                lastOAuthError = "인증 만료. Claude CLI 재로그인 필요"
                if let last = lastUsage, last.hasData {
                    var cached = last
                    cached.dataSource = "oauth (cached)"
                    return cached
                }
                return nil
            case 403:
                lastOAuthError = "접근 제한 (403)"
                if let last = lastUsage, last.hasData {
                    var cached = last
                    cached.dataSource = "oauth (cached)"
                    return cached
                }
                return nil
            default:
                lastOAuthError = "API 오류 (\(httpResponse.statusCode))"
                return nil
            }
        } catch {
            lastOAuthError = "네트워크 오류: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Token reading (cached file > keychain)

    private static let tokenCachePath = NSHomeDirectory() + "/.claude/.stats-token-cache"

    private func readOAuthToken() -> String? {
        // 1. Environment variable
        if let token = ProcessInfo.processInfo.environment["CLAUDE_OAUTH_TOKEN"], !token.isEmpty {
            return token
        }

        // 2. Build-time cached token file
        if let token = Self.readCachedToken() {
            return token
        }

        // 3. ~/.claude/.credentials.json (like codexbar)
        if let token = Self.readCredentialsFile() {
            return token
        }

        return nil
    }

    private static func readCachedToken() -> String? {
        guard let data = FileManager.default.contents(atPath: tokenCachePath),
              let token = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    private static func cacheToken(_ token: String) {
        let data = Data(token.utf8)
        FileManager.default.createFile(atPath: tokenCachePath, contents: data,
                                        attributes: [.posixPermissions: 0o600])
    }

    /// Read from ~/.claude/.credentials.json (same as codexbar)
    private static func readCredentialsFile() -> String? {
        let path = NSHomeDirectory() + "/.claude/.credentials.json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return token
    }


    private static func formatSeconds(_ seconds: Int) -> String {
        if seconds >= 3600 {
            return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
        } else if seconds >= 60 {
            return "\(seconds / 60)m"
        }
        return "\(seconds)s"
    }

    // MARK: - OAuth Response Parsing

    static func parseOAuthResponse(_ data: Data) -> ClaudeUsage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var usage = ClaudeUsage()
        usage.dataSource = "oauth"
        usage.rawOutput = String(data: data, encoding: .utf8) ?? ""

        func percentLeft(from utilization: Double) -> Int {
            return max(0, min(100, Int((100.0 - utilization).rounded())))
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

    private static func formatResetTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let date: Date? = formatter.date(from: isoString) ?? {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: isoString)
        }()

        guard let date else {
            return "Resets: \(isoString)"
        }

        let interval = date.timeIntervalSince(Date())
        if interval <= 0 { return "Reset time passed" }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 24 {
            return "Resets in \(hours / 24)d \(hours % 24)h"
        } else if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }
}
