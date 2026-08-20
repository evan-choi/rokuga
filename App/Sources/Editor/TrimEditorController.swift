import AppKit
import SwiftUI

@MainActor
final class TrimEditorController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    let model: TrimEditorModel
    private let onClose: () -> Void

    init(url: URL, onClose: @escaping () -> Void) {
        model = TrimEditorModel(url: url)
        self.onClose = onClose

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = url.lastPathComponent
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()

        super.init()
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: TrimEditorView(model: model) { [weak self] in
                self?.requestClose()
            }
            .appLocale()
        )
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func requestClose() {
        if windowShouldClose(window) {
            window.close()
        }
    }

    /// Unsaved-changes guard (task 8.3): trimmed-but-unexported state prompts before discarding.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = L10n.string("Discard trim changes?")
        alert.informativeText = L10n.string("The trimmed range has not been exported.")
        alert.addButton(withTitle: L10n.string("Discard"))
        alert.addButton(withTitle: L10n.string("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        model.pause()
        onClose()
    }
}
