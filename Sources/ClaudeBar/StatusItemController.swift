import AppKit
import Combine
import ClaudeBarCore
import SwiftUI

/// The menu bar item: its label, and the dropdown shown on click.
@MainActor
final class StatusItemController: NSObject {
    private let state: AppState
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let dropdown = NSPopover()
    private var subscriptions = Set<AnyCancellable>()

    init(state: AppState) {
        self.state = state
        super.init()
        dropdown.behavior = .transient
        let host = NSHostingController(rootView: DropdownView().environmentObject(state))
        host.sizingOptions = .preferredContentSize
        dropdown.contentViewController = host
        item.button?.target = self
        item.button?.action = #selector(toggleDropdown)
        state.$output.combineLatest(state.$needsAttention)
            .sink { [weak self] output, attention in self?.updateTitle(output, attention: attention) }
            .store(in: &subscriptions)
    }

    private func updateTitle(_ output: StatusOutput, attention: Bool) {
        item.button?.attributedTitle = MenuBarTitle.make(usage: output.usage, attention: attention)
    }

    @objc private func toggleDropdown() {
        if dropdown.isShown {
            dropdown.performClose(nil)
            return
        }
        guard let button = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        dropdown.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        state.acknowledge()
    }
}

enum MenuBarTitle {
    /// "◆ 42% · 18%" (5h · 7d), each colored by level; "◆•" when something needs the user; "◆ —" with no data.
    static func make(usage: UsageSummary, attention: Bool) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let plain: [NSAttributedString.Key: Any] = [.font: font]
        let s = NSMutableAttributedString(string: "◆", attributes: plain)
        if attention {
            s.append(NSAttributedString(string: "•", attributes: [.font: font, .foregroundColor: NSColor(Theme.waiting)]))
        }
        guard usage.fiveHourPct != nil || usage.sevenDayPct != nil else {
            s.append(NSAttributedString(string: " —", attributes: plain))
            return s
        }
        func pct(_ value: Double?) -> NSAttributedString {
            guard let value else { return NSAttributedString(string: "—", attributes: plain) }
            return NSAttributedString(string: Format.percent(value),
                                      attributes: [.font: font, .foregroundColor: Theme.nsColor(UsageLevel(percent: value))])
        }
        s.append(NSAttributedString(string: " ", attributes: plain))
        s.append(pct(usage.fiveHourPct))
        s.append(NSAttributedString(string: " · ", attributes: plain))
        s.append(pct(usage.sevenDayPct))
        return s
    }
}
