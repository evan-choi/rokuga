import AppKit
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Panel background per task 4.4: Liquid Glass on macOS 26+, `NSVisualEffectView` on 13.3–15, solid color under Reduce Transparency.
/// A separate contrast scrim keeps chrome legible without changing the native material contract.
struct GlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var cornerRadius: CGFloat = 16

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let resolvedPalette = palette
        ZStack {
            if reduceTransparency {
                shape.fill(resolvedPalette.tint)
            } else {
                if #available(macOS 26.0, *) {
                    shape.fill(.clear)
                        .glassEffect(.regular, in: shape)
                } else {
                    VisualEffectView()
                        .clipShape(shape)
                }
                shape.fill(resolvedPalette.tint.opacity(resolvedPalette.scrimOpacity))
            }
        }
        .overlay(shape.strokeBorder(resolvedPalette.border, lineWidth: 1))
    }

    private var palette: GlassPalette {
        Self.palette(colorScheme: colorScheme, increasedContrast: colorSchemeContrast == .increased)
    }

    static func palette(colorScheme: ColorScheme, increasedContrast: Bool) -> GlassPalette {
        if colorScheme == .dark {
            return GlassPalette(
                tintColor: NSColor(srgbRed: 0.118, green: 0.118, blue: 0.137, alpha: 1),
                scrimOpacity: increasedContrast ? 0.84 : 0.70,
                borderColor: NSColor.white.withAlphaComponent(increasedContrast ? 0.26 : 0.14)
            )
        }

        return GlassPalette(
            tintColor: NSColor(srgbRed: 0.910, green: 0.910, blue: 0.925, alpha: 1),
            scrimOpacity: increasedContrast ? 0.92 : 0.56,
            borderColor: NSColor.black.withAlphaComponent(increasedContrast ? 0.22 : 0.12)
        )
    }
}

struct GlassPalette {
    let tintColor: NSColor
    let scrimOpacity: Double
    let borderColor: NSColor

    var tint: Color {
        Color(nsColor: tintColor)
    }

    var border: Color {
        Color(nsColor: borderColor)
    }
}

extension View {
    /// System capture chrome never shows focus rings; suppress them on our HUD surfaces.
    /// (macOS 13 has no `focusEffectDisabled`; the ring only appears there with Full Keyboard Access on.)
    @ViewBuilder
    func hiddenFocusRing() -> some View {
        if #available(macOS 14.0, *) {
            focusEffectDisabled()
        } else {
            self
        }
    }
}
