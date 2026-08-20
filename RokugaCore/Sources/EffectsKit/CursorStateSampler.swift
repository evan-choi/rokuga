import CoreGraphics
import Foundation

/// A point-in-time snapshot of cursor state, in global CG (top-left origin) coordinates.
public struct CursorSnapshot: Sendable {
    public var location: CGPoint

    public init(location: CGPoint) {
        self.location = location
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
    private var timer: DispatchSourceTimer?

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
    }

    @MainActor
    public func stop() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    func sampleNow() {
        let location = locationProvider()
        lock.withLock {
            latest = CursorSnapshot(location: location)
        }
    }

    public func snapshot() -> CursorSnapshot {
        lock.withLock { latest }
    }
}
