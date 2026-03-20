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

    /// Warning color for low usage percentages (style 7 behavior)
    private func warningColor(for percent: Int?) -> NSColor {
        guard let pct = percent else { return NSColor.labelColor }
        switch pct {
        case 0..<15: return NSColor(red: 0.97, green: 0.44, blue: 0.44, alpha: 1.0)  // red
        case 15..<30: return NSColor(red: 0.98, green: 0.80, blue: 0.08, alpha: 1.0)  // yellow
        default: return NSColor.labelColor
        }
    }

    /// Whether any usage is in warning state
    private var hasWarning: Bool {
        let usage = store.usage
        let percents = [usage.sessionPercentLeft, usage.weeklyPercentLeft].compactMap { $0 }
        return percents.contains { $0 < 30 }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Set up the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 290, height: 380)
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

        store.$menuBarStyle
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
            if let logoPath = Bundle.main.path(forResource: "logo", ofType: "png"),
               let logo = NSImage(contentsOfFile: logoPath) {
                logo.size = NSSize(width: 18, height: 18)
                logo.isTemplate = true
                button.image = logo
            } else {
                button.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Claude Code Stats")
            }
            button.title = ""
            return
        }

        // Draw Stats-style image: label on top, percentage below
        let image = renderStatsImage()
        button.image = image
        button.title = ""
    }

    /// Renders menu bar image based on selected style
    private func renderStatsImage() -> NSImage {
        switch store.menuBarStyle {
        case .percentAndReset: return renderStyle2()
        case .inlineCompact: return renderStyle4()
        }
    }

    // MARK: - Style rendering helpers

    private struct MenuBarItem {
        let label: String      // "5H", "7D"
        let percent: Int
        let resetShort: String? // "48m", "2d3h"
    }

    private func menuBarItems() -> [MenuBarItem] {
        let usage = store.usage
        var items: [MenuBarItem] = []
        if let s = usage.sessionPercentLeft {
            items.append(MenuBarItem(label: "5H", percent: s, resetShort: usage.sessionResetShort))
        }
        if let w = usage.weeklyPercentLeft {
            items.append(MenuBarItem(label: "7D", percent: w, resetShort: usage.weeklyResetShort))
        }
        if items.isEmpty {
            items.append(MenuBarItem(label: "5H", percent: 0, resetShort: nil))
        }
        return items
    }

    /// Style 2: percentage + reset time (2 rows)
    private func renderStyle2() -> NSImage {
        let items = menuBarItems()
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        let resetFont = NSFont.systemFont(ofSize: 7, weight: .regular)
        let spacing: CGFloat = 8
        let height: CGFloat = 22
        let warn = hasWarning

        var itemWidths: [CGFloat] = []
        for item in items {
            let valStr = "\(item.percent)%"
            let resetStr = item.resetShort ?? ""
            let valSize = (valStr as NSString).size(withAttributes: [.font: valueFont])
            let resetSize = (resetStr as NSString).size(withAttributes: [.font: resetFont])
            itemWidths.append(max(valSize.width, resetSize.width))
        }

        let totalWidth = itemWidths.reduce(0, +) + spacing * CGFloat(max(0, items.count - 1)) + 4
        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: true) { _ in
            var x: CGFloat = 2
            for (idx, item) in items.enumerated() {
                let colWidth = itemWidths[idx]
                let valStr = "\(item.percent)%"
                let valColor = warn ? self.warningColor(for: item.percent) : NSColor.labelColor
                let valAttrs: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: valColor]
                let valSize = (valStr as NSString).size(withAttributes: valAttrs)
                (valStr as NSString).draw(at: NSPoint(x: x + (colWidth - valSize.width) / 2, y: 1), withAttributes: valAttrs)

                if let reset = item.resetShort {
                    let resetColor = warn ? valColor.withAlphaComponent(0.7) : NSColor.labelColor.withAlphaComponent(0.5)
                    let resetAttrs: [NSAttributedString.Key: Any] = [.font: resetFont, .foregroundColor: resetColor]
                    let resetSize = (reset as NSString).size(withAttributes: resetAttrs)
                    (reset as NSString).draw(at: NSPoint(x: x + (colWidth - resetSize.width) / 2, y: 14), withAttributes: resetAttrs)
                }
                x += colWidth + spacing
            }
            return true
        }
        image.isTemplate = !warn
        return image
    }

    /// Style 4: inline compact "83% 4h31m   88% 2d22h"
    private func renderStyle4() -> NSImage {
        let items = menuBarItems()
        let pctFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let resetFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)
        let height: CGFloat = 22
        let warn = hasWarning
        let gapPctReset: CGFloat = 2      // gap between "83%" and "4h31m"
        let gapBetweenItems: CGFloat = 10 // gap between items

        // Build segments with explicit gaps
        struct Segment {
            let text: String
            let attrs: [NSAttributedString.Key: Any]
            let trailingGap: CGFloat
        }

        var segments: [Segment] = []
        for (idx, item) in items.enumerated() {
            let valColor = warn ? warningColor(for: item.percent) : NSColor.labelColor
            let pctAttrs: [NSAttributedString.Key: Any] = [.font: pctFont, .foregroundColor: valColor]

            if let reset = item.resetShort {
                let resetColor = warn ? valColor.withAlphaComponent(0.7) : NSColor.labelColor.withAlphaComponent(0.5)
                let resetAttrs: [NSAttributedString.Key: Any] = [.font: resetFont, .foregroundColor: resetColor]
                segments.append(Segment(text: "\(item.percent)%", attrs: pctAttrs, trailingGap: gapPctReset))
                let isLast = idx == items.count - 1
                segments.append(Segment(text: reset, attrs: resetAttrs, trailingGap: isLast ? 0 : gapBetweenItems))
            } else {
                let isLast = idx == items.count - 1
                segments.append(Segment(text: "\(item.percent)%", attrs: pctAttrs, trailingGap: isLast ? 0 : gapBetweenItems))
            }
        }

        let totalWidth = segments.reduce(CGFloat(0)) { acc, seg in
            acc + (seg.text as NSString).size(withAttributes: seg.attrs).width + seg.trailingGap
        } + 4

        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: true) { _ in
            var x: CGFloat = 2
            for seg in segments {
                let size = (seg.text as NSString).size(withAttributes: seg.attrs)
                let y = (height - size.height) / 2
                (seg.text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: seg.attrs)
                x += size.width + seg.trailingGap
            }
            return true
        }
        image.isTemplate = !warn
        return image
    }

}
