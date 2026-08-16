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
/// The dark tint keeps panels legible over bright content (design.md — "vscode dark" tint direction).
struct GlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var cornerRadius: CGFloat = 16

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if reduceTransparency {
                shape.fill(Color(red: 0.12, green: 0.12, blue: 0.14))
            } else if #available(macOS 26.0, *) {
                shape.fill(.clear)
                    .glassEffect(.regular.tint(Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.4)), in: shape)
            } else {
                VisualEffectView()
                    .clipShape(shape)
                shape.fill(Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.55))
            }
        }
        .overlay(shape.strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
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
