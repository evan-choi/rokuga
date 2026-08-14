import AppKit
import AVFoundation
import SwiftUI

/// Floating post-recording thumbnail (task 7.2): bottom-right, auto-dismisses, click expands into the preview panel, swipe-right dismisses.
@MainActor
final class ThumbnailPanelController {
    private static let size = NSSize(width: 240, height: 150)
    private static let margin: CGFloat = 20
    private static let timeout: TimeInterval = 6

    private let panel: CapturePanel
    private let recordingURL: URL
    private let appState: AppState
    private var dismissTimer: Timer?

    init(recordingURL: URL, appState: AppState) {
        self.recordingURL = recordingURL
        self.appState = appState

        let screen = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screen.maxX - Self.size.width - Self.margin,
            y: screen.minY + Self.margin
        )
        panel = CapturePanel(contentRect: NSRect(origin: origin, size: Self.size))
        panel.contentView = NSHostingView(
            rootView: ThumbnailView(
                recordingURL: recordingURL,
                onOpen: { [weak self] in self?.expandToPreview() },
                onSwipeDismiss: { [weak self] in self?.dismiss() },
                onHoverChanged: { [weak self] hovering in
                    if hovering {
                        self?.dismissTimer?.invalidate()
                    } else {
                        self?.scheduleTimeout()
                    }
                }
            )
        )
        panel.onEscape = { [weak self] in self?.dismiss() }
    }

    func present() {
        panel.orderFrontRegardless()
        panel.registerForCaptureExclusion()
        scheduleTimeout()
    }

    private func scheduleTimeout() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: Self.timeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.dismiss() }
        }
    }

    private func expandToPreview() {
        dismissTimer?.invalidate()
        let originFrame = panel.frame
        panel.close()
        appState.presentPreview(for: recordingURL, expandingFrom: originFrame)
    }

    func dismiss() {
        dismissTimer?.invalidate()
        panel.close()
        appState.thumbnailDidClose(self)
    }
}

struct ThumbnailView: View {
    let recordingURL: URL
    let onOpen: () -> Void
    let onSwipeDismiss: () -> Void
    let onHoverChanged: (Bool) -> Void

    @State private var thumbnail: CGImage?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.black.opacity(0.8))
                ProgressView()
            }
        }
        .frame(width: 240, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(radius: 14, y: 4)
        .offset(x: dragOffset)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover(perform: onHoverChanged)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = max(0, value.translation.width)
                }
                .onEnded { value in
                    if value.translation.width > 60 {
                        onSwipeDismiss()
                    } else if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                        dragOffset = 0
                    } else {
                        withAnimation(.snappy) { dragOffset = 0 }
                    }
                }
        )
        .task { await loadThumbnail() }
        .accessibilityLabel(Text("Recording saved — click to preview"))
    }

    private func loadThumbnail() async {
        let generator = AVAssetImageGenerator(asset: AVAsset(url: recordingURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 300)
        thumbnail = try? generator.copyCGImage(at: .zero, actualTime: nil)
    }
}
