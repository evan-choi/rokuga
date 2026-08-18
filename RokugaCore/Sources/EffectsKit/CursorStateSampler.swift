import AppKit
import Foundation

/// A point-in-time snapshot of cursor state, in global CG (top-left origin) coordinates.
public struct CursorSnapshot: Sendable {
    public var location: CGPoint
    /// Click timestamps (host clock) with locations, newest last.
    public var clicks: [(time: TimeInterval, location: CGPoint)]

    public init(
        location: CGPoint,
        clicks: [(time: TimeInterval, location: CGPoint)] = []
    ) {
        self.location = location
        self.clicks = clicks
    }
}

public protocol CursorStateSampling: Sendable {
    func snapshot() -> CursorSnapshot
}

/// Samples cursor position at the configured capture rate on a private queue, so the
/// frame path never hops to or blocks the main thread.
public final class CursorStateSampler: CursorStateSampling, @unchecked Sendable {
    private let lock = NSLock()
    private let sampleQueue = DispatchQueue(label: "io.rokuga.effects.cursor-sampler", qos: .userInteractive)
    private let locationProvider: @Sendable () -> CGPoint
    let samplingInterval: TimeInterval

    private var latest = CursorSnapshot(location: .zero)
    private var clicks: [(time: TimeInterval, location: CGPoint)] = []
    private var timer: DispatchSourceTimer?
    private var clickMonitor: Any?

    public init(
        framesPerSecond: Int = 60,
        locationProvider: @escaping @Sendable () -> CGPoint = {
            CGEvent(source: nil)?.location ?? .zero
        }
    ) {
        samplingInterval = 1.0 / Double(max(framesPerSecond, 1))
        self.locationProvider = locationProvider
    }

    @MainActor
    public func start() {
        guard timer == nil else { return }

        sampleNow()
        let timer = DispatchSource.makeTimerSource(queue: sampleQueue)
        timer.schedule(deadline: .now() + samplingInterval, repeating: samplingInterval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.sampleNow()
        }
        self.timer = timer
        timer.resume()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            let location = locationProvider()
            lock.withLock {
                self.clicks = [(time: ProcessInfo.processInfo.systemUptime, location: location)]
            }
        }
    }

    @MainActor
    public func stop() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    func sampleNow() {
        let location = locationProvider()
        lock.withLock {
            latest = CursorSnapshot(
                location: location,
                clicks: latest.clicks
            )
        }
    }

    public func snapshot() -> CursorSnapshot {
        lock.withLock {
            var snap = latest
            let cutoff = ProcessInfo.processInfo.systemUptime - ClickRipple.lifetime
            clicks.removeAll { $0.time < cutoff }
            snap.clicks = clicks
            return snap
        }
    }
}

/// Native-style click indicator timeline (pure math, unit tested).
public enum ClickRipple {
    public static let lifetime: TimeInterval = 0.5
    static let radius: CGFloat = 40
    static let fadeStartProgress = 0.4

    /// Progress values in 0...1 for clicks still animating at `now`.
    public static func progresses(
        clicks: [(time: TimeInterval, location: CGPoint)],
        now: TimeInterval
    ) -> [(progress: Double, location: CGPoint)] {
        clicks.compactMap { click in
            let age = now - click.time
            guard age >= 0, age < lifetime else { return nil }
            return (progress: age / lifetime, location: click.location)
        }
    }

    static func opacity(at progress: Double) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        guard clamped > fadeStartProgress else { return 1 }
        let fadeProgress = (clamped - fadeStartProgress) / (1 - fadeStartProgress)
        let eased = fadeProgress * fadeProgress * (3 - 2 * fadeProgress)
        return CGFloat(1 - eased)
    }
}
