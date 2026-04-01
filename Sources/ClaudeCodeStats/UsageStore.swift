import Foundation
import Combine
import AppKit

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
    private var wakeObserver: NSObjectProtocol?

    init() {
        let saved = UserDefaults.standard.integer(forKey: "menuBarStyle")
        self.menuBarStyle = MenuBarStyle(rawValue: saved) ?? .percentAndReset
    }

    var isClaudeInstalled: Bool {
        ClaudeUsageFetcher.hasToken
    }

    func startAutoRefresh() {
        stopAutoRefresh()

        // Register wake observer once
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleWake()
                }
            }
        }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let self = self else { break }
                // If usage is exhausted, poll every 30 min instead
                let isExhausted = self.usage.sessionPercentLeft == 0 || self.usage.weeklyPercentLeft == 0
                let interval = isExhausted ? max(self.refreshInterval, 1800) : self.refreshInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func handleWake() {
        // Reset loading state in case it was stuck during sleep
        isLoading = false
        // Clear rate limit so we can fetch fresh data
        Task {
            await fetcher.clearRateLimit()
        }
        // Restart the refresh loop
        startAutoRefresh()
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil

        let result = await fetcher.fetch()
        usage = result
        if result.hasData && result.dataSource == "oauth" {
            lastRefresh = Date()
        }

        if !result.hasData && !result.rawOutput.isEmpty {
            error = result.rawOutput
        }
    }

    deinit {
        refreshTask?.cancel()
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
