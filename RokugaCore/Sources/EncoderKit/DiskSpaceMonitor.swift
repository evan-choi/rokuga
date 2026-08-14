import Foundation
import SettingsKit

/// Disk-full protection (task 3.6): preflight before start, watermark polling while recording.
public final class DiskSpaceMonitor: @unchecked Sendable {
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "io.rokuga.diskmonitor")

    public init() {}

    public static func freeBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    /// Throws when there is not enough space to start a recording.
    public static func preflight(outputFolder: URL) throws {
        let free = freeBytes(at: outputFolder)
        guard free >= CaptureLimits.minFreeBytesToStart else {
            throw RecordingSinkError.diskFull(freeBytes: free)
        }
    }

    /// Polls every `interval` seconds; fires `onLowSpace` once when free space drops below the auto-stop watermark.
    public func start(
        outputFolder: URL,
        interval: TimeInterval = 30,
        onLowSpace: @escaping @Sendable (Int64) -> Void
    ) {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler {
            let free = Self.freeBytes(at: outputFolder)
            if free < CaptureLimits.autoStopFreeBytes {
                onLowSpace(free)
            }
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }
}

public enum RecordingSinkError: Error, Equatable, Sendable {
    case diskFull(freeBytes: Int64)
    case writerFailed(String)
    case notStarted
}
