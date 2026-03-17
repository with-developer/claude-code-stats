import Foundation
import Combine

/// Observable store for Claude Code usage data
@MainActor
final class UsageStore: ObservableObject {
    @Published var usage = ClaudeUsage()
    @Published var isLoading = false
    @Published var lastRefresh: Date?
    @Published var error: String?
    @Published var refreshInterval: TimeInterval = 120 // 2 minutes default

    private let fetcher = ClaudeUsageFetcher()
    private var refreshTask: Task<Void, Never>?

    var isClaudeInstalled: Bool {
        ClaudeUsageFetcher.findClaudeBinary() != nil
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
        lastRefresh = Date()
        isLoading = false

        if !result.hasData && !result.rawOutput.isEmpty {
            error = result.rawOutput
        }
    }

    deinit {
        refreshTask?.cancel()
    }
}
