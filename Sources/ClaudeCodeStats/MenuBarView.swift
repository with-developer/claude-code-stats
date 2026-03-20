import SwiftUI

// MARK: - Adaptive theme colors

private struct Theme {
    let cardBg: Color
    let cardBorder: Color
    let labelPrimary: Color
    let labelSecondary: Color
    let labelTertiary: Color
    let barTrack: Color

    static func resolve(_ colorScheme: ColorScheme) -> Theme {
        if colorScheme == .dark {
            return Theme(
                cardBg: Color.white.opacity(0.04),
                cardBorder: Color.white.opacity(0.08),
                labelPrimary: .white,
                labelSecondary: Color.white.opacity(0.55),
                labelTertiary: Color.white.opacity(0.3),
                barTrack: Color.white.opacity(0.1)
            )
        } else {
            return Theme(
                cardBg: Color.black.opacity(0.04),
                cardBorder: Color.black.opacity(0.12),
                labelPrimary: Color(red: 0.1, green: 0.1, blue: 0.1),
                labelSecondary: Color(red: 0.25, green: 0.25, blue: 0.28),
                labelTertiary: Color(red: 0.4, green: 0.4, blue: 0.43),
                barTrack: Color.black.opacity(0.12)
            )
        }
    }

    static func percentColor(for pct: Int?, scheme: ColorScheme) -> Color {
        guard let pct else { return .gray }
        if scheme == .dark {
            switch pct {
            case 0..<15: return Color(red: 0.97, green: 0.44, blue: 0.44)
            case 15..<30: return Color(red: 0.98, green: 0.72, blue: 0.24)
            default: return Color(red: 0.29, green: 0.85, blue: 0.50)
            }
        } else {
            switch pct {
            case 0..<15: return Color(red: 0.78, green: 0.15, blue: 0.15)
            case 15..<30: return Color(red: 0.75, green: 0.48, blue: 0.0)
            default: return Color(red: 0.10, green: 0.50, blue: 0.25)
            }
        }
    }
}

// MARK: - Popover

struct MenuContentView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { Theme.resolve(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !store.isClaudeInstalled {
                notInstalledView
            } else if let error = store.error {
                errorView(error)
            } else if store.usage.hasData {
                bigStatCards
                subStats
            } else {
                emptyView
            }

            Divider()

            metaInfo

            footerActions
        }
        .padding(14)
        .frame(width: 290)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Claude Code Stats")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: { Task { await store.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(theme.labelSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Big stat cards

    private var bigStatCards: some View {
        HStack(spacing: 8) {
            StatCard(
                label: "SESSION",
                percent: store.usage.sessionPercentLeft,
                resetDescription: store.usage.sessionResetDescription,
                colorScheme: colorScheme
            )

            if store.usage.weeklyPercentLeft != nil {
                StatCard(
                    label: "WEEKLY",
                    percent: store.usage.weeklyPercentLeft,
                    resetDescription: store.usage.weeklyResetDescription,
                    colorScheme: colorScheme
                )
            }
        }
    }

    // MARK: - Sub stats

    @ViewBuilder
    private var subStats: some View {
        let hasSubStats = store.usage.opusPercentLeft != nil || store.usage.sonnetPercentLeft != nil
        if hasSubStats {
            VStack(spacing: 4) {
                if let opus = store.usage.opusPercentLeft {
                    SubStatRow(icon: "star", label: "Opus", percent: opus,
                               resetDescription: store.usage.opusResetDescription, colorScheme: colorScheme)
                }
                if let sonnet = store.usage.sonnetPercentLeft {
                    SubStatRow(icon: "wand.and.stars", label: "Sonnet", percent: sonnet,
                               resetDescription: store.usage.sonnetResetDescription, colorScheme: colorScheme)
                }
            }
        }
    }

    // MARK: - Meta info

    private var metaInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let email = store.usage.accountEmail {
                HStack(spacing: 4) {
                    Text(email)
                    if let plan = store.usage.plan {
                        Text("·")
                        Text(plan)
                    }
                }
                .font(.system(size: 9))
                .foregroundColor(theme.labelTertiary)
            }

            if let lastRefresh = store.lastRefresh {
                HStack(spacing: 4) {
                    Text("Updated")
                    Text(lastRefresh, style: .relative)
                    Text("ago")
                    if !store.usage.dataSource.isEmpty {
                        Text("· \(store.usage.dataSource)")
                    }
                }
                .font(.system(size: 9))
                .foregroundColor(theme.labelTertiary)
            }
        }
    }

    // MARK: - Footer

    private var footerActions: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(MenuBarStyle.allCases, id: \.rawValue) { style in
                    Button(style.displayName) { store.menuBarStyle = style }
                }
            } label: {
                Text("Style \u{25BE}")
                    .footerButtonStyle(theme)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(maxWidth: .infinity)

            Menu {
                Button("3m") { store.refreshInterval = 180 }
                Button("5m") { store.refreshInterval = 300 }
                Button("10m") { store.refreshInterval = 600 }
            } label: {
                Text("Interval \u{25BE}")
                    .footerButtonStyle(theme)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(maxWidth: .infinity)

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("Quit")
                    .footerButtonStyle(theme)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    private var intervalLabel: String {
        "\(Int(store.refreshInterval / 60))m"
    }

    // MARK: - State views

    private var notInstalledView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Claude CLI not found", systemImage: "exclamationmark.triangle")
                .foregroundColor(.orange)
                .font(.system(size: 12))
            Text("Install Claude Code CLI to see usage stats")
                .font(.system(size: 10))
                .foregroundColor(theme.labelSecondary)
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Error", systemImage: "exclamationmark.triangle")
                .foregroundColor(.red)
                .font(.system(size: 12))
            Text(error)
                .font(.system(size: 10))
                .foregroundColor(theme.labelSecondary)
                .lineLimit(3)
        }
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No usage data yet")
                .foregroundColor(theme.labelSecondary)
                .font(.system(size: 12))
            Text("Waiting for first refresh...")
                .font(.system(size: 10))
                .foregroundColor(theme.labelTertiary)
        }
    }
}

// MARK: - Footer button style

private extension Text {
    func footerButtonStyle(_ theme: Theme) -> some View {
        self
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(theme.labelSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(theme.cardBg))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.cardBorder, lineWidth: 1))
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let label: String
    let percent: Int?
    let resetDescription: String?
    let colorScheme: ColorScheme

    private var theme: Theme { Theme.resolve(colorScheme) }
    private var color: Color { Theme.percentColor(for: percent, scheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(theme.labelTertiary)
                .tracking(0.5)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(percent ?? 0)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                Text("%")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(color.opacity(0.6))
            }

            if let reset = resetDescription {
                Text(reset)
                    .font(.system(size: 9))
                    .foregroundColor(theme.labelTertiary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(theme.barTrack)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: geo.size.width * fillFraction, height: 3)
                }
            }
            .frame(height: 3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.cardBg))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.cardBorder, lineWidth: 1))
    }

    private var fillFraction: CGFloat {
        guard let pct = percent else { return 0 }
        return CGFloat(max(0, min(100, pct))) / 100.0
    }
}

// MARK: - Sub stat row

struct SubStatRow: View {
    let icon: String
    let label: String
    let percent: Int
    let resetDescription: String?
    let colorScheme: ColorScheme

    private var theme: Theme { Theme.resolve(colorScheme) }
    private var color: Color { Theme.percentColor(for: percent, scheme: colorScheme) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(theme.labelTertiary)
                .frame(width: 14)

            Text(label)
                .font(.system(size: 10))
                .foregroundColor(theme.labelSecondary)

            Spacer()

            Text("\(percent)%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(color)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(theme.barTrack)
                    .frame(width: 40, height: 3)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 40 * CGFloat(max(0, min(100, percent))) / 100.0, height: 3)
            }

            if let reset = resetDescription {
                let short = reset
                    .replacingOccurrences(of: "Resets in ", with: "")
                    .replacingOccurrences(of: "Resets: ", with: "")
                Text(short)
                    .font(.system(size: 8))
                    .foregroundColor(theme.labelTertiary)
                    .frame(minWidth: 30, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(theme.cardBg))
    }
}
