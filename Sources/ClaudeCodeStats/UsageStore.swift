import Foundation
import Combine

/// Menu bar display style
enum MenuBarStyle: Int, CaseIterable {
    case percentAndReset = 2      // Compact: percentage + reset time (2 rows)
    case inlineCompact = 4        // Inline: 83%48m 89%2d

    var displayName: String {
        switch self {
        case .percentAndReset: return "Compact"
        case .inlineCompact: return "Inline"
        }
    }
}

/// Observable store for Claude Code usage data
@MainActor
final class UsageStore: ObservableObject {
    @Published var usage = ClaudeUsage()
    @Published var isLoading = false
    @Published var lastRefresh: Date?
    @Published var error: String?
    @Published var refreshInterval: TimeInterval = 300 // 5 minutes default
    @Published var menuBarStyle: MenuBarStyle {
        didSet { UserDefaults.standard.set(menuBarStyle.rawValue, forKey: "menuBarStyle") }
    }

    private let fetcher = ClaudeUsageFetcher()
    private var refreshTask: Task<Void, Never>?

    init() {
        let saved = UserDefaults.standard.integer(forKey: "menuBarStyle")
        self.menuBarStyle = MenuBarStyle(rawValue: saved) ?? .percentAndReset
    }

    var isClaudeInstalled: Bool {
        ClaudeUsageFetcher.hasToken
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.refreshInterval else { break }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        let result = await fetcher.fetch()
        usage = result
        if result.hasData && result.dataSource == "oauth" {
            lastRefresh = Date()
        }
        isLoading = false

        if !result.hasData && !result.rawOutput.isEmpty {
            error = result.rawOutput
        }
    }

    deinit {
        refreshTask?.cancel()
    }
}
