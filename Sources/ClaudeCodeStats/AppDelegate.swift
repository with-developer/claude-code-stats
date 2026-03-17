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
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
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

        // Draw Stats-style image: label on top, percentage below
        let image = renderStatsImage()
        button.image = image
        button.title = ""
    }

    /// Renders Stats-style menu bar image: label on top, bold percentage below
    private func renderStatsImage() -> NSImage {
        let usage = store.usage

        var items: [(String, String)] = []
        if let s = usage.sessionPercentLeft { items.append(("5H", "\(s)%")) }
        if let w = usage.weeklyPercentLeft { items.append(("7D", "\(w)%")) }

        if items.isEmpty {
            items.append(("5H", "--%"))
        }

        let labelFont = NSFont.systemFont(ofSize: 7.5, weight: .medium)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        let labelColor = NSColor.labelColor.withAlphaComponent(0.6)
        let valueColor = NSColor.labelColor

        let spacing: CGFloat = 8
        let height: CGFloat = 22

        // Measure each item width
        var itemWidths: [CGFloat] = []
        for (label, value) in items {
            let labelSize = (label as NSString).size(withAttributes: [.font: labelFont])
            let valueSize = (value as NSString).size(withAttributes: [.font: valueFont])
            itemWidths.append(max(labelSize.width, valueSize.width))
        }

        let totalWidth = itemWidths.reduce(0, +) + spacing * CGFloat(max(0, items.count - 1)) + 4
        let imageSize = NSSize(width: totalWidth, height: height)

        let image = NSImage(size: imageSize, flipped: true) { _ in
            var x: CGFloat = 2

            for (idx, (label, value)) in items.enumerated() {
                let colWidth = itemWidths[idx]

                // Draw label on top (centered)
                let labelAttrs: [NSAttributedString.Key: Any] = [
                    .font: labelFont,
                    .foregroundColor: labelColor,
                ]
                let labelSize = (label as NSString).size(withAttributes: labelAttrs)
                let labelX = x + (colWidth - labelSize.width) / 2
                (label as NSString).draw(at: NSPoint(x: labelX, y: 1), withAttributes: labelAttrs)

                // Draw value below (centered)
                let valueAttrs: [NSAttributedString.Key: Any] = [
                    .font: valueFont,
                    .foregroundColor: valueColor,
                ]
                let valueSize = (value as NSString).size(withAttributes: valueAttrs)
                let valueX = x + (colWidth - valueSize.width) / 2
                (value as NSString).draw(at: NSPoint(x: valueX, y: 9), withAttributes: valueAttrs)

                x += colWidth + spacing
            }

            return true
        }

        image.isTemplate = true
        return image
    }
}
