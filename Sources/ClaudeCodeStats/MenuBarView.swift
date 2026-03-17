import SwiftUI

/// The menu bar icon view - displays compact usage bars like the Stats app
struct MenuBarView: View {
    let usage: ClaudeUsage

    var body: some View {
        HStack(spacing: 2) {
            // Mini bars showing usage levels (like Stats app CPU bars)
            UsageMiniBar(
                percent: usage.sessionPercentLeft,
                color: barColor(for: usage.sessionPercentLeft),
                label: "S"
            )

            if usage.weeklyPercentLeft != nil {
                UsageMiniBar(
                    percent: usage.weeklyPercentLeft,
                    color: barColor(for: usage.weeklyPercentLeft),
                    label: "W"
                )
            }

            if usage.opusPercentLeft != nil {
                UsageMiniBar(
                    percent: usage.opusPercentLeft,
                    color: barColor(for: usage.opusPercentLeft),
                    label: "O"
                )
            }
        }
        .frame(height: 18)
    }

    private func barColor(for percent: Int?) -> Color {
        guard let pct = percent else { return .gray }
        switch pct {
        case 0..<15: return .red
        case 15..<30: return .orange
        case 30..<60: return .yellow
        default: return .green
        }
    }
}

/// A single mini vertical bar for the menu bar (like Stats app style)
struct UsageMiniBar: View {
    let percent: Int?
    let color: Color
    let label: String

    var body: some View {
        VStack(spacing: 0) {
            // Vertical bar showing remaining percentage
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: geo.size.height * (1.0 - fillFraction))

                    Rectangle()
                        .fill(color)
                        .frame(height: geo.size.height * fillFraction)
                }
            }
            .frame(width: 6)
            .clipShape(RoundedRectangle(cornerRadius: 1))
        }
    }

    private var fillFraction: CGFloat {
        guard let pct = percent else { return 0 }
        return CGFloat(max(0, min(100, pct))) / 100.0
    }
}

/// The dropdown menu content
struct MenuContentView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "brain")
                Text("Claude Code Stats")
                    .font(.headline)
                Spacer()
                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.bottom, 4)

            Divider()

            if !store.isClaudeInstalled {
                Label("Claude CLI not found", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                Text("Install Claude Code CLI to see usage stats")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let error = store.error {
                Label("Error", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            } else if store.usage.hasData {
                usageRows
            } else {
                Text("No usage data yet")
                    .foregroundColor(.secondary)
                Text("Waiting for first refresh...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Account info
            if let plan = store.usage.plan {
                HStack {
                    Text("Plan:")
                        .foregroundColor(.secondary)
                    Text(plan)
                }
                .font(.caption)
            }

            if let email = store.usage.accountEmail {
                HStack {
                    Text("Account:")
                        .foregroundColor(.secondary)
                    Text(email)
                }
                .font(.caption)
            }

            if let lastRefresh = store.lastRefresh {
                HStack {
                    Text("Updated:")
                        .foregroundColor(.secondary)
                    Text(lastRefresh, style: .relative)
                    Text("ago")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Divider()

            // Actions
            HStack {
                Button("Refresh Now") {
                    Task { await store.refresh() }
                }

                Spacer()

                Menu("Interval: \(intervalLabel)") {
                    Button("30 seconds") { store.refreshInterval = 30 }
                    Button("1 minute") { store.refreshInterval = 60 }
                    Button("2 minutes") { store.refreshInterval = 120 }
                    Button("5 minutes") { store.refreshInterval = 300 }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private var intervalLabel: String {
        switch store.refreshInterval {
        case ..<60: return "\(Int(store.refreshInterval))s"
        case 60: return "1m"
        case 120: return "2m"
        case 300: return "5m"
        default: return "\(Int(store.refreshInterval / 60))m"
        }
    }

    @ViewBuilder
    private var usageRows: some View {
        UsageRow(
            title: "Session",
            percentLeft: store.usage.sessionPercentLeft,
            resetDescription: store.usage.sessionResetDescription,
            icon: "clock"
        )

        if store.usage.weeklyPercentLeft != nil {
            UsageRow(
                title: "Weekly (All Models)",
                percentLeft: store.usage.weeklyPercentLeft,
                resetDescription: store.usage.weeklyResetDescription,
                icon: "calendar"
            )
        }

        if store.usage.opusPercentLeft != nil {
            UsageRow(
                title: "Weekly (Opus/Sonnet)",
                percentLeft: store.usage.opusPercentLeft,
                resetDescription: store.usage.opusResetDescription,
                icon: "star"
            )
        }
    }
}

/// A single usage row with progress bar
struct UsageRow: View {
    let title: String
    let percentLeft: Int?
    let resetDescription: String?
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(percentText)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(percentColor)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(percentColor)
                        .frame(width: geo.size.width * fillFraction, height: 6)
                }
            }
            .frame(height: 6)

            if let reset = resetDescription {
                Text(reset)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var percentText: String {
        guard let pct = percentLeft else { return "--%" }
        return "\(pct)% left"
    }

    private var percentColor: Color {
        guard let pct = percentLeft else { return .gray }
        switch pct {
        case 0..<15: return .red
        case 15..<30: return .orange
        case 30..<60: return .yellow
        default: return .green
        }
    }

    private var fillFraction: CGFloat {
        guard let pct = percentLeft else { return 0 }
        return CGFloat(max(0, min(100, pct))) / 100.0
    }
}
