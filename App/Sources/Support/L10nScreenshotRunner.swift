import AppKit
import SwiftUI

/// Localized-screenshot harness (task 9a.4). Launched as
/// `Rokuga -AppleLanguages "(ko)" --l10n-screenshots <outdir>`, renders the main
/// surfaces off-screen via view caching (no capture permission needed) and exits.
@MainActor
enum L10nScreenshotRunner {
    static func runIfRequested() -> Bool {
        guard let index = CommandLine.arguments.firstIndex(of: "--l10n-screenshots"),
              CommandLine.arguments.count > index + 1
        else { return false }

        // Sandbox-safe: render into the container temp dir and print the path for the harness to collect.
        let label = URL(fileURLWithPath: CommandLine.arguments[index + 1]).lastPathComponent
        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("l10n-screenshots", isDirectory: true)
            .appendingPathComponent(label, isDirectory: true)
        try? FileManager.default.removeItem(at: outDir)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        print("L10N_OUT=\(outDir.path)")

        let appState = AppState.shared
        snapshot(ToolbarView(appState: appState), size: NSSize(width: 560, height: 64), name: "toolbar", to: outDir)
        snapshot(OptionsPopoverView(), size: NSSize(width: 292, height: 560), name: "popover", to: outDir)
        snapshot(SettingsView(), size: NSSize(width: 460, height: 420), name: "settings", to: outDir)
        snapshot(
            TrimEditorView(model: TrimEditorModel(url: URL(fileURLWithPath: "/dev/null")), onClose: {}),
            size: NSSize(width: 760, height: 540),
            name: "editor",
            to: outDir
        )

        exit(0)
    }

    private static func snapshot<V: View>(_ view: V, size: NSSize, name: String, to directory: URL) {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: directory.appendingPathComponent("\(name).png"))
        window.close()
    }
}
