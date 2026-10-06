import AppKit
import SwiftUI

/// Hosts SwiftUI in a popover so the first click acts at once. A menu bar app isn't always made active when its
/// popover opens; a plain hosting view then spends the first click on activating, and buttons (like the
/// dropdown's tabs) never fire.
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: ((NSSize) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        reportSize()
    }

    // SwiftUI content changes (data arriving, a new tab) re-run layout: measure again each time.
    override func layout() {
        super.layout()
        reportSize()
    }

    private func reportSize() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onSizeChange?(self.intrinsicContentSize.height > 0 ? self.intrinsicContentSize : self.fittingSize)
        }
    }
}

/// A view controller around ClickThroughHostingView whose preferredContentSize follows the SwiftUI content,
/// so the popover resizes with it (e.g. when switching tabs).
final class ClickThroughHostingController<Content: View>: NSViewController {
    private let rootView: Content

    init(rootView: Content) {
        self.rootView = rootView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let host = ClickThroughHostingView(rootView: rootView)
        host.sizingOptions = [.intrinsicContentSize]
        host.onSizeChange = { [weak self] size in
            guard let self, size.width > 0, size.height > 0, size != self.preferredContentSize else { return }
            self.preferredContentSize = size
        }
        view = host
        preferredContentSize = host.fittingSize
    }
}
