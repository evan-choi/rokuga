import AVFoundation
import EncoderKit
import Foundation

/// AVCaptureSession-based microphone source feeding `MediaSink` (task 3.3).
/// SCStream's `.microphone` output type needs macOS 15; this path works on the 13.3 baseline.
public final class MicrophoneCapture: NSObject, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "io.rokuga.capture.microphone", qos: .userInteractive)
    private let stateLock = NSLock()
    private var sink: MediaSink?
    private var isPaused = false

    public static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    public func start(sink: MediaSink) throws {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw RecordingError.captureSourceLost
        }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw RecordingError.captureSourceLost
        }
        session.addInput(input)
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
        session.commitConfiguration()

        stateLock.withLock { self.sink = sink }
        session.startRunning()
    }

    public func pause() {
        stateLock.withLock { isPaused = true }
    }

    public func resume() {
        stateLock.withLock { isPaused = false }
    }

    public func stop() {
        session.stopRunning()
        stateLock.withLock { sink = nil }
    }
}

extension MicrophoneCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let target = stateLock.withLock { isPaused ? nil : sink }
        target?.append(sampleBuffer, of: .microphone)
    }
}
