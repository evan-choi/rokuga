import AppKit
import CaptureKit
import SwiftUI

@MainActor
final class CountdownOverlayController {
    private let panel: CapturePanel
    private let model = CountdownModel()

    init(display: DisplayTarget, onCancel: @escaping () -> Void) {
        let size = NSSize(width: 220, height: 220)
        let origin = NSPoint(
            x: display.frame.midX - size.width / 2,
            y: display.frame.midY - size.height / 2
        )
        panel = CapturePanel(contentRect: NSRect(origin: origin, size: size), level: .screenSaver)
        panel.contentView = NSHostingView(rootView: CountdownOverlayView(model: model).appLocale())
        panel.onEscape = onCancel
    }

    func present() {
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.registerForCaptureExclusion()
    }

    func update(remaining: Int) {
        model.remaining = remaining
    }

    func dismiss() {
        panel.close()
    }
}

@MainActor
final class CountdownModel: ObservableObject {
    @Published var remaining: Int = 0
}

struct CountdownOverlayView: View {
    @ObservedObject var model: CountdownModel

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.55))
            Text(verbatim: "\(model.remaining)")
                .font(.system(size: 110, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
                .animation(
                    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .snappy,
                    value: model.remaining
                )
            VStack {
                Spacer()
                Text("Esc to cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 22)
            }
        }
        .frame(width: 220, height: 220)
    }
}
