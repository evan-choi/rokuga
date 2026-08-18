import AppKit
import SwiftUI

/// Localized-screenshot harness (task 9a.4). Launched as
/// `Rokuga -AppleLanguages "(ko)" --l10n-screenshots <outdir>`, renders the main
/// surfaces off-screen via view caching (no capture permission needed) and exits.
@MainActor
enum L10nScreenshotRunner {
    static func runIfRequested() -> Bool {
        if let index = CommandLine.arguments.firstIndex(of: "--theme-screenshots"),
           CommandLine.arguments.count > index + 1 {
            renderThemeScreenshots(label: CommandLine.arguments[index + 1])
        }

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

    private static func renderThemeScreenshots(label: String) -> Never {
        let safeLabel = URL(fileURLWithPath: label).lastPathComponent
        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("theme-screenshots", isDirectory: true)
            .appendingPathComponent(safeLabel, isDirectory: true)
        try? FileManager.default.removeItem(at: outDir)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        print("THEME_OUT=\(outDir.path)")

        let appState = AppState.shared
        let toolbarCanvasSize = NSSize(width: 560, height: 64)
        snapshot(
            ToolbarView(appState: appState),
            size: toolbarCanvasSize,
            name: "toolbar-light",
            to: outDir,
            appearance: .aqua,
            flattenThemeBackdrop: true
        )
        snapshot(
            ToolbarView(appState: appState),
            size: toolbarCanvasSize,
            name: "toolbar-dark",
            to: outDir,
            appearance: .darkAqua,
            flattenThemeBackdrop: true
        )

        let previewURL = URL(fileURLWithPath: "/dev/null")
        snapshot(
            previewView(url: previewURL),
            size: NSSize(width: 520, height: 380),
            name: "preview-light",
            to: outDir,
            appearance: .aqua,
            flattenThemeBackdrop: true
        )
        snapshot(
            previewView(url: previewURL),
            size: NSSize(width: 520, height: 380),
            name: "preview-dark",
            to: outDir,
            appearance: .darkAqua,
            flattenThemeBackdrop: true
        )

        snapshot(
            TrimEditorView(model: TrimEditorModel(url: previewURL), onClose: {}),
            size: NSSize(width: 760, height: 540),
            name: "editor-light",
            to: outDir,
            appearance: .aqua,
            flattenThemeBackdrop: true
        )
        snapshot(
            TrimEditorView(model: TrimEditorModel(url: previewURL), onClose: {}),
            size: NSSize(width: 760, height: 540),
            name: "editor-dark",
            to: outDir,
            appearance: .darkAqua,
            flattenThemeBackdrop: true
        )

        exit(0)
    }

    private static func previewView(url: URL) -> PreviewPanelView {
        PreviewPanelView(model: PreviewModel(url: url), onEdit: {}, onDelete: {}, onDone: {})
    }

    private static func snapshot<V: View>(
        _ view: V,
        size: NSSize,
        name: String,
        to directory: URL,
        appearance: NSAppearance.Name? = nil,
        flattenThemeBackdrop: Bool = false
    ) {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        if let appearance {
            window.appearance = NSAppearance(named: appearance)
        }
        window.contentView = hosting
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let data = flattenThemeBackdrop
            ? flattenedThemePNG(from: rep, size: size)
            : rep.representation(using: .png, properties: [:])
        guard let data else { return }
        try? data.write(to: directory.appendingPathComponent("\(name).png"))
        window.close()
    }

    private static func flattenedThemePNG(
        from rep: NSBitmapImageRep,
        size: NSSize
    ) -> Data? {
        let image = NSImage(size: size)
        image.lockFocus()

        let bandWidth = size.width / 3
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: bandWidth, height: size.height).fill()
        NSColor(srgbRed: 0, green: 0.4, blue: 1, alpha: 1).setFill()
        NSRect(x: bandWidth, y: 0, width: bandWidth, height: size.height).fill()
        NSColor.black.setFill()
        NSRect(x: bandWidth * 2, y: 0, width: size.width - bandWidth * 2, height: size.height).fill()

        rep.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: rep.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let flattenedRep = NSBitmapImageRep(data: tiffData)
        else { return nil }
        return flattenedRep.representation(using: .png, properties: [:])
    }
}

@MainActor
enum AppearanceVerificationRunner {
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--verify-appearance-propagation") else { return false }

        let passed = verifyPropagation()
        print("APPEARANCE_PROPAGATION=\(passed ? "OK" : "FAILED")")
        exit(passed ? 0 : 1)
    }

    private static func verifyPropagation() -> Bool {
        let previousAppearance = NSApp.appearance
        let previewURL = URL(fileURLWithPath: "/dev/null")
        let surfaces = [
            makeSurface(name: "toolbar", view: AnyView(ToolbarView(appState: .shared)), isPanel: true),
            makeSurface(name: "popover", view: AnyView(OptionsPopoverView()), isPanel: true),
            makeSurface(
                name: "preview",
                view: AnyView(PreviewPanelView(
                    model: PreviewModel(url: previewURL),
                    onEdit: {},
                    onDelete: {},
                    onDone: {}
                )),
                isPanel: true
            ),
            makeSurface(
                name: "editor",
                view: AnyView(TrimEditorView(model: TrimEditorModel(url: previewURL), onClose: {})),
                isPanel: false
            )
        ]

        defer {
            surfaces.forEach { $0.window.close() }
            NSApp.appearance = previousAppearance
        }

        ThemeApplier.apply(.light)
        let lightPassed = surfacesMatch(surfaces, expected: .aqua)

        ThemeApplier.apply(.dark)
        let darkPassed = surfacesMatch(surfaces, expected: .darkAqua)

        ThemeApplier.apply(.auto)
        let inheritedName = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        let autoPassed = NSApp.appearance == nil
            && inheritedName.map { surfacesMatch(surfaces, expected: $0) } == true

        return autoPassed && lightPassed && darkPassed
    }

    private static func makeSurface(name: String, view: AnyView, isPanel: Bool) -> AppearanceSurface {
        let frame = NSRect(x: 0, y: 0, width: 760, height: 540)
        let hostingView = NSHostingView(rootView: view)
        let window: NSWindow

        if isPanel {
            window = CapturePanel(contentRect: frame, showsWindowShadow: false)
        } else {
            window = NSWindow(
                contentRect: frame,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
        }

        window.contentView = hostingView
        window.orderBack(nil)
        hostingView.layoutSubtreeIfNeeded()
        return AppearanceSurface(name: name, window: window, hostingView: hostingView)
    }

    private static func surfacesMatch(_ surfaces: [AppearanceSurface], expected: NSAppearance.Name) -> Bool {
        var passed = true

        for surface in surfaces {
            let matchesExpected = matches(surface.window.effectiveAppearance, expected: expected)
                && matches(surface.hostingView.effectiveAppearance, expected: expected)
                && surface.window.appearance == nil
                && surface.hostingView.appearance == nil
            if !matchesExpected {
                print("APPEARANCE_MISMATCH=\(surface.name):\(expected.rawValue)")
                passed = false
            }
        }

        return passed
    }

    private static func matches(_ appearance: NSAppearance, expected: NSAppearance.Name) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == expected
    }
}

@MainActor
private struct AppearanceSurface {
    let name: String
    let window: NSWindow
    let hostingView: NSView
}

@MainActor
enum ThemeRenderingVerificationRunner {
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--verify-theme-rendering") else { return false }

        let contrastPassed = verifyContrast()
        let accessibilityPassed = verifyAccessibilityRendering()
        let passed = contrastPassed && accessibilityPassed
        print("THEME_RENDERING=\(passed ? "OK" : "FAILED")")
        exit(passed ? 0 : 1)
    }

    private static func verifyContrast() -> Bool {
        let themes = [
            ThemeCase(name: "light", appearance: .aqua, colorScheme: .light),
            ThemeCase(name: "dark", appearance: .darkAqua, colorScheme: .dark)
        ]
        let backgrounds = [
            BackgroundCase(name: "white", color: .white),
            BackgroundCase(name: "black", color: .black),
            BackgroundCase(
                name: "high-chroma-blue",
                color: NSColor(srgbRed: 0, green: 0.4, blue: 1, alpha: 1)
            )
        ]
        var passed = true

        for theme in themes {
            for background in backgrounds {
                guard let measurement = measureTokens(theme: theme, background: background) else {
                    print("THEME_CONTRAST=FAILED theme=\(theme.name) background=\(background.name) reason=resolve")
                    passed = false
                    continue
                }

                let meetsThresholds = measurement.text >= 4.5 && measurement.control >= 3
                print(
                    String(
                        format: "THEME_CONTRAST=%@ theme=%@ background=%@ text=%.2f control=%.2f",
                        meetsThresholds ? "OK" : "FAILED",
                        theme.name,
                        background.name,
                        measurement.text,
                        measurement.control
                    )
                )
                passed = passed && meetsThresholds
            }
        }

        return passed
    }

    private static func verifyAccessibilityRendering() -> Bool {
        let light = ThemeCase(name: "light", appearance: .aqua, colorScheme: .light)
        let dark = ThemeCase(name: "dark", appearance: .darkAqua, colorScheme: .dark)
        let white = BackgroundCase(name: "white", color: .white)
        let black = BackgroundCase(name: "black", color: .black)

        let reducedLightOnWhite = surfaceColor(theme: light, background: white, reduceTransparency: true)
        let reducedLightOnBlack = surfaceColor(theme: light, background: black, reduceTransparency: true)
        let reducedDarkOnWhite = surfaceColor(theme: dark, background: white, reduceTransparency: true)
        let reducedDarkOnBlack = surfaceColor(theme: dark, background: black, reduceTransparency: true)
        let normalLightStrength = surfaceStrength(theme: light, background: white)
        let increasedLightStrength = surfaceStrength(theme: light, background: white, increasedContrast: true)
        let normalDarkStrength = surfaceStrength(theme: dark, background: black)
        let increasedDarkStrength = surfaceStrength(theme: dark, background: black, increasedContrast: true)

        let reduceTransparencyPassed = maximumChannelDifference(
            reducedLightOnWhite,
            reducedLightOnBlack
        ) <= 0.02 && maximumChannelDifference(reducedDarkOnWhite, reducedDarkOnBlack) <= 0.02
        let increaseContrastPassed = increasedLightStrength >= normalLightStrength
            && increasedDarkStrength >= normalDarkStrength
        let passed = reduceTransparencyPassed && increaseContrastPassed

        print(
            String(
                format: "ACCESSIBILITY_RENDERING=%@ reduce-transparency=%@ increase-contrast=%@ light-strength=%.2f->%.2f dark-strength=%.2f->%.2f",
                passed ? "OK" : "FAILED",
                reduceTransparencyPassed ? "OK" : "FAILED",
                increaseContrastPassed ? "OK" : "FAILED",
                normalLightStrength,
                increasedLightStrength,
                normalDarkStrength,
                increasedDarkStrength
            )
        )
        return passed
    }

    private static func measureTokens(
        theme: ThemeCase,
        background: BackgroundCase
    ) -> (text: Double, control: Double)? {
        guard let semanticColors = resolvedSemanticColors(for: theme.appearance) else { return nil }
        let surface = surfaceColor(theme: theme, background: background)
        let activeControl = composite(semanticColors.label, opacity: 1, over: surface)
        let selectedSurface = composite(semanticColors.selection, opacity: 1, over: surface)
        let selectedText = composite(semanticColors.label, opacity: 1, over: selectedSurface)
        let recordSurface = composite(semanticColors.controlBackground, opacity: 0.72, over: surface)
        let recordText = composite(semanticColors.label, opacity: 1, over: recordSurface)

        let text = [
            contrastRatio(activeControl, surface),
            contrastRatio(selectedText, selectedSurface),
            contrastRatio(recordText, recordSurface)
        ].min() ?? 0

        return (text, contrastRatio(activeControl, surface))
    }

    private static func surfaceColor(
        theme: ThemeCase,
        background: BackgroundCase,
        reduceTransparency: Bool = false,
        increasedContrast: Bool = false
    ) -> NSColor {
        let palette = GlassBackground.palette(
            colorScheme: theme.colorScheme,
            increasedContrast: increasedContrast
        )
        return composite(
            palette.tintColor,
            opacity: reduceTransparency ? 1 : palette.scrimOpacity,
            over: background.color
        )
    }

    private static func surfaceStrength(
        theme: ThemeCase,
        background: BackgroundCase,
        increasedContrast: Bool = false
    ) -> Double {
        contrastRatio(
            surfaceColor(theme: theme, background: background, increasedContrast: increasedContrast),
            background.color
        )
    }

    private static func resolvedSemanticColors(for appearanceName: NSAppearance.Name) -> SemanticColors? {
        guard let appearance = NSAppearance(named: appearanceName) else { return nil }
        var resolvedColors: SemanticColors?
        appearance.performAsCurrentDrawingAppearance {
            guard let label = NSColor.labelColor.usingColorSpace(.sRGB),
                  let selection = NSColor.unemphasizedSelectedContentBackgroundColor.usingColorSpace(.sRGB),
                  let controlBackground = NSColor.controlBackgroundColor.usingColorSpace(.sRGB)
            else { return }
            resolvedColors = SemanticColors(
                label: label,
                selection: selection,
                controlBackground: controlBackground
            )
        }
        return resolvedColors
    }

    private static func composite(_ foreground: NSColor, opacity: Double, over background: NSColor) -> NSColor {
        guard let foregroundRGB = foreground.usingColorSpace(.sRGB),
              let backgroundRGB = background.usingColorSpace(.sRGB)
        else { return background }

        let alpha = foregroundRGB.alphaComponent * CGFloat(opacity)
        let inverseAlpha = 1 - alpha
        return NSColor(
            srgbRed: foregroundRGB.redComponent * alpha + backgroundRGB.redComponent * inverseAlpha,
            green: foregroundRGB.greenComponent * alpha + backgroundRGB.greenComponent * inverseAlpha,
            blue: foregroundRGB.blueComponent * alpha + backgroundRGB.blueComponent * inverseAlpha,
            alpha: 1
        )
    }

    private static func contrastRatio(_ first: NSColor, _ second: NSColor) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private static func relativeLuminance(_ color: NSColor) -> Double {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }

        func linearized(_ value: CGFloat) -> Double {
            let channel = Double(value)
            return channel <= 0.04045
                ? channel / 12.92
                : pow((channel + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearized(rgb.redComponent)
            + 0.7152 * linearized(rgb.greenComponent)
            + 0.0722 * linearized(rgb.blueComponent)
    }

    private static func maximumChannelDifference(_ first: NSColor, _ second: NSColor) -> CGFloat {
        guard let firstRGB = first.usingColorSpace(.sRGB),
              let secondRGB = second.usingColorSpace(.sRGB)
        else { return 1 }

        return max(
            abs(firstRGB.redComponent - secondRGB.redComponent),
            abs(firstRGB.greenComponent - secondRGB.greenComponent),
            abs(firstRGB.blueComponent - secondRGB.blueComponent)
        )
    }

    private struct ThemeCase {
        let name: String
        let appearance: NSAppearance.Name
        let colorScheme: ColorScheme
    }

    private struct BackgroundCase {
        let name: String
        let color: NSColor
    }

    private struct SemanticColors {
        let label: NSColor
        let selection: NSColor
        let controlBackground: NSColor
    }
}
