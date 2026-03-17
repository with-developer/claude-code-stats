import AppKit
import Combine
import SwiftUI

/// App delegate that manages the menu bar status item
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = UsageStore()
    private var cancellables: Set<AnyCancellable> = []
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Set up the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 360)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(store: store)
        )

        // Configure the status bar button
        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            updateMenuBarIcon()
        }

        // Observe usage changes to update the icon
        store.$usage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenuBarIcon() }
            .store(in: &cancellables)

        store.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenuBarIcon() }
            .store(in: &cancellables)

        // Start auto-refresh
        store.startAutoRefresh()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            closePopover()
        } else {
            // Update content before showing
            popover.contentViewController = NSHostingController(
                rootView: MenuContentView(store: store)
            )
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Close popover when clicking outside
            eventMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    /// Renders the menu bar icon as compact usage bars (like Stats app)
    private func updateMenuBarIcon() {
        guard let button = statusItem.button else { return }

        if store.isLoading && !store.usage.hasData {
            button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Loading")
            button.title = ""
            return
        }

        if !store.isClaudeInstalled {
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Not installed")
            button.title = ""
            return
        }

        if !store.usage.hasData {
            button.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Claude Code Stats")
            button.title = ""
            return
        }

        // Draw custom mini bars like Stats app
        let image = renderBarsImage()
        button.image = image
        button.title = ""
    }

    /// Renders compact vertical bars for the menu bar (similar to Stats app)
    private func renderBarsImage() -> NSImage {
        let barWidth: CGFloat = 5
        let barSpacing: CGFloat = 2
        let barHeight: CGFloat = 16
        let cornerRadius: CGFloat = 1.5

        var bars: [(Int?, NSColor)] = []

        // Session bar
        bars.append((store.usage.sessionPercentLeft, barColor(for: store.usage.sessionPercentLeft)))

        // Weekly bar
        if let weekly = store.usage.weeklyPercentLeft {
            bars.append((weekly, barColor(for: weekly)))
        }

        // Opus bar
        if let opus = store.usage.opusPercentLeft {
            bars.append((opus, barColor(for: opus)))
        }

        // Sonnet bar
        if let sonnet = store.usage.sonnetPercentLeft {
            bars.append((sonnet, barColor(for: sonnet)))
        }

        let totalWidth = CGFloat(bars.count) * barWidth + CGFloat(max(0, bars.count - 1)) * barSpacing + 4
        let imageSize = NSSize(width: totalWidth, height: barHeight + 2)

        let image = NSImage(size: imageSize, flipped: false) { _ in
            var x: CGFloat = 2

            for (percent, color) in bars {
                let fillFraction = CGFloat(max(0, min(100, percent ?? 0))) / 100.0
                let fillHeight = barHeight * fillFraction
                let emptyHeight = barHeight - fillHeight
                let y: CGFloat = 1

                // Background (empty part)
                let bgRect = NSRect(x: x, y: y + fillHeight, width: barWidth, height: emptyHeight)
                let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
                NSColor.gray.withAlphaComponent(0.3).setFill()
                bgPath.fill()

                // Filled part
                if fillHeight > 0 {
                    let fillRect = NSRect(x: x, y: y, width: barWidth, height: fillHeight)
                    let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: cornerRadius, yRadius: cornerRadius)
                    color.setFill()
                    fillPath.fill()
                }

                x += barWidth + barSpacing
            }

            return true
        }

        image.isTemplate = false
        return image
    }

    private func barColor(for percent: Int?) -> NSColor {
        guard let pct = percent else { return .gray }
        switch pct {
        case 0..<15: return .systemRed
        case 15..<30: return .systemOrange
        case 30..<60: return .systemYellow
        default: return .systemGreen
        }
    }
}
