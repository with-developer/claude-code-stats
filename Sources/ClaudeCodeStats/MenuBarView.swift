import SwiftUI

/// The dropdown menu content (popover)
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

            // Account & data source info
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
                    if !store.usage.dataSource.isEmpty {
                        Text("(\(store.usage.dataSource))")
                    }
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
            title: "Session (5h)",
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
                title: "Weekly (Opus)",
                percentLeft: store.usage.opusPercentLeft,
                resetDescription: store.usage.opusResetDescription,
                icon: "star"
            )
        }

        if store.usage.sonnetPercentLeft != nil {
            UsageRow(
                title: "Weekly (Sonnet)",
                percentLeft: store.usage.sonnetPercentLeft,
                resetDescription: store.usage.sonnetResetDescription,
                icon: "wand.and.stars"
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
