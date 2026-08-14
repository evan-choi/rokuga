import AppKit
import AVKit
import SwiftUI

/// Post-recording preview panel (task 7.3): expands in place from the thumbnail, AVPlayer + scrub bar, QuickTime-style two-finger horizontal scrub, Edit/Delete/Done.
@MainActor
final class PreviewPanelController {
    private static let size = NSSize(width: 520, height: 380)

    private let panel: CapturePanel
    private let model: PreviewModel
    private let appState: AppState

    init(recordingURL: URL, expandingFrom originFrame: NSRect?, appState: AppState) {
        self.appState = appState
        model = PreviewModel(url: recordingURL)

        let screen = NSScreen.main?.visibleFrame ?? .zero
        let targetFrame = NSRect(
            x: screen.maxX - Self.size.width - 20,
            y: screen.minY + 20,
            width: Self.size.width,
            height: Self.size.height
        )

        panel = CapturePanel(contentRect: originFrame ?? targetFrame)
        panel.contentView = NSHostingView(
            rootView: PreviewPanelView(
                model: model,
                onEdit: { [weak self] in self?.openEditor() },
                onDelete: { [weak self] in self?.deleteRecording() },
                onDone: { [weak self] in self?.close() }
            )
        )
        panel.onEscape = { [weak self] in self?.close() }

        panel.orderFrontRegardless()
        panel.makeKey()
        panel.registerForCaptureExclusion()
        if originFrame != nil {
            panel.setFrame(targetFrame, display: true, animate: true)
        }
    }

    private func openEditor() {
        let url = model.url
        model.pause()
        close()
        appState.presentTrimEditor(for: url)
    }

    private func deleteRecording() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Move recording to Trash?")
        alert.informativeText = model.url.lastPathComponent
        alert.addButton(withTitle: String(localized: "Move to Trash"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        model.pause()
        try? FileManager.default.trashItem(at: model.url, resultingItemURL: nil)
        appState.recordingWasDeleted(model.url)
        close()
    }

    func close() {
        model.pause()
        panel.close()
        appState.previewDidClose(self)
    }
}

@MainActor
final class PreviewModel: ObservableObject {
    let url: URL
    let player: AVPlayer
    @Published var progress: Double = 0
    @Published var isPlaying = false
    private var timeObserver: Any?
    private(set) var duration: Double = 0

    init(url: URL) {
        self.url = url
        player = AVPlayer(url: url)
        Task {
            duration = (try? await player.currentItem?.asset.load(.duration).seconds) ?? 0
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, self.duration > 0 else { return }
                self.progress = time.seconds / self.duration
            }
        }
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            if progress >= 0.999 {
                player.seek(to: .zero)
            }
            player.play()
        }
        isPlaying.toggle()
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(toProgress value: Double) {
        guard duration > 0 else { return }
        progress = min(max(value, 0), 1)
        let target = CMTime(seconds: progress * duration, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// QuickTime-style trackpad scrub: horizontal pan maps to timeline distance.
    func scrub(deltaX: CGFloat, viewWidth: CGFloat) {
        guard duration > 0, viewWidth > 0 else { return }
        pause()
        seek(toProgress: progress + Double(-deltaX / viewWidth))
    }
}

struct PreviewPanelView: View {
    @ObservedObject var model: PreviewModel
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrubbablePlayerView(model: model)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)
            controls
        }
        .background(GlassBackground(cornerRadius: 16))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Text(model.url.lastPathComponent)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Button("Edit", action: onEdit)
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityLabel(Text("Delete"))
            Button("Done", action: onDone)
                .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(action: model.togglePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel(Text(model.isPlaying ? "Pause" : "Play"))

            Slider(
                value: Binding(
                    get: { model.progress },
                    set: { model.seek(toProgress: $0) }
                )
            )
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }
}

/// AVPlayerLayer host that forwards trackpad scroll events for two-finger scrubbing.
struct ScrubbablePlayerView: NSViewRepresentable {
    @ObservedObject var model: PreviewModel

    func makeNSView(context: Context) -> ScrubbablePlayerNSView {
        let view = ScrubbablePlayerNSView()
        view.playerLayer.player = model.player
        view.onScrub = { [weak model] deltaX, width in
            model?.scrub(deltaX: deltaX, viewWidth: width)
        }
        return view
    }

    func updateNSView(_ view: ScrubbablePlayerNSView, context: Context) {
        view.playerLayer.player = model.player
    }
}

final class ScrubbablePlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()
    var onScrub: ((CGFloat, CGFloat) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer = playerLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else {
            super.scrollWheel(with: event)
            return
        }
        onScrub?(event.scrollingDeltaX, bounds.width)
    }
}
