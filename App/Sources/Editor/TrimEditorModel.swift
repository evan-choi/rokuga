import AppKit
import AVFoundation
import Combine
import TrimKit

@MainActor
final class TrimEditorModel: ObservableObject {
    let url: URL
    let player: AVPlayer
    let thumbnails: ThumbnailStrip

    @Published var duration: Double = 0
    @Published var startSeconds: Double = 0
    @Published var endSeconds: Double = 0
    @Published var playheadSeconds: Double = 0
    @Published var pointsPerSecond: Double = 60
    @Published var isPlaying = false
    @Published var keyframes: [Double] = []
    @Published var frameExact = false
    @Published var hasAudio = false
    @Published var exportProgress: Double?
    @Published var exportError: String?
    @Published private(set) var exportedSinceChange = false

    var frameDuration: Double = 1.0 / 60.0
    private var timeObserver: Any?
    private var exporter: TrimExporter?

    static let minPointsPerSecond: Double = 4
    static let maxPointsPerSecond: Double = 400

    init(url: URL) {
        self.url = url
        player = AVPlayer(url: url)
        thumbnails = ThumbnailStrip(url: url)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 60),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.playheadSeconds = time.seconds
            }
        }

        Task { await load() }
    }

    private func load() async {
        let asset = AVURLAsset(url: url)
        duration = await (try? asset.load(.duration).seconds) ?? 0
        endSeconds = duration
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let fps = try? await track.load(.nominalFrameRate), fps > 0 {
            frameDuration = 1.0 / Double(fps)
        }
        hasAudio = await (try? TrimExporter(sourceURL: url).hasAudioTrack()) ?? false
        keyframes = await (try? KeyframeIndex.load(from: url))?.seconds ?? []
    }

    var trimRange: TrimRange {
        TrimRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            end: CMTime(seconds: endSeconds, preferredTimescale: 600)
        )
    }

    var isDirty: Bool {
        guard duration > 0 else { return false }
        let trimmed = startSeconds > 0.01 || endSeconds < duration - 0.01
        return trimmed && !exportedSinceChange
    }

    // MARK: Playback

    func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            if playheadSeconds >= endSeconds - 0.01 {
                seek(to: startSeconds)
            }
            player.play()
        }
        isPlaying.toggle()
    }

    func seek(to seconds: Double) {
        let clamped = min(max(seconds, 0), duration)
        playheadSeconds = clamped
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func scrub(deltaX: CGFloat, viewWidth: CGFloat) {
        guard duration > 0, viewWidth > 0 else { return }
        player.pause()
        isPlaying = false
        seek(to: playheadSeconds - Double(deltaX / viewWidth) * min(duration, 30))
    }

    // MARK: Trim handles

    enum Handle { case start, end }

    func setHandle(_ handle: Handle, seconds rawSeconds: Double, snap: Bool) {
        var seconds = min(max(rawSeconds, 0), duration)
        if snap, !frameExact,
           let nearest = KeyframeIndex(seconds: keyframes).nearest(to: seconds),
           abs(nearest - seconds) * pointsPerSecond < 6 {
            seconds = nearest
        }
        switch handle {
        case .start:
            startSeconds = min(seconds, endSeconds - frameDuration)
        case .end:
            endSeconds = max(seconds, startSeconds + frameDuration)
        }
        exportedSinceChange = false
        seek(to: seconds)
    }

    func nudge(_ handle: Handle, byFrames frames: Int) {
        let delta = Double(frames) * frameDuration
        switch handle {
        case .start:
            setHandle(.start, seconds: startSeconds + delta, snap: false)
        case .end:
            setHandle(.end, seconds: endSeconds + delta, snap: false)
        }
    }

    // MARK: Zoom

    func zoom(by factor: Double) {
        pointsPerSecond = min(max(pointsPerSecond * factor, Self.minPointsPerSecond), Self.maxPointsPerSecond)
    }

    func resetZoom(fittingWidth width: Double) {
        guard duration > 0 else { return }
        pointsPerSecond = min(max(width / duration, Self.minPointsPerSecond), Self.maxPointsPerSecond)
    }

    // MARK: Export

    func export(kind: TrimExportKind, to destination: URL) async {
        let exporter = TrimExporter(sourceURL: url)
        self.exporter = exporter
        exportProgress = 0
        exportError = nil
        do {
            try await exporter.export(kind: kind, range: trimRange, to: destination) { [weak self] value in
                Task { @MainActor [weak self] in self?.exportProgress = value }
            }
            exportedSinceChange = true
            exportProgress = nil
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch TrimExportError.cancelled {
            exportProgress = nil
        } catch {
            exportProgress = nil
            exportError = error.localizedDescription
        }
    }

    func cancelExport() {
        exporter?.cancel()
    }

    func pause() {
        player.pause()
        isPlaying = false
    }
}
