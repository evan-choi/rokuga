import AppKit
import AVFoundation
import Foundation
import QuartzCore

enum WorkloadCommand {
    @MainActor
    static func run(arguments: [String]) throws {
        let options = try WorkloadOptions(arguments)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()

        guard let screen = NSScreen.screens.first(where: { $0.backingScaleFactor >= 2 }) ?? NSScreen.main else {
            throw PerfError.workloadUnavailable("no display is available")
        }

        let contentSize = CGSize(width: 1920, height: 1080)
        let origin = CGPoint(
            x: screen.frame.midX - contentSize.width / 2,
            y: screen.frame.midY - contentSize.height / 2
        )
        let window = NSWindow(
            contentRect: CGRect(origin: origin, size: contentSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = false
        window.isOpaque = true
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.sharingType = .readOnly
        window.title = "RokugaPerf Workload"
        window.contentView = WorkloadView(frame: CGRect(origin: .zero, size: contentSize), motion: options.motion)
        window.orderFrontRegardless()
        window.displayIfNeeded()
        CATransaction.flush()

        let tone = options.audio ? try ToneGenerator() : nil
        try tone?.start()

        let scale = window.backingScaleFactor
        try RokugaPerf.printJSON(WorkloadResult(
            command: "workload",
            pid: ProcessInfo.processInfo.processIdentifier,
            widthPoints: Int(contentSize.width),
            heightPoints: Int(contentSize.height),
            backingScale: Double(scale),
            widthPixels: Int(contentSize.width * scale),
            heightPixels: Int(contentSize.height * scale),
            motion: options.motion,
            audio: options.audio
        ), pretty: false)

        withExtendedLifetime((window, tone)) {
            app.run()
        }
    }
}

private struct WorkloadOptions {
    var motion = false
    var audio = false

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            guard index + 1 < arguments.count else {
                throw PerfError.invalidArgument("missing value for \(flag)")
            }
            let value = arguments[index + 1]
            switch flag {
            case "--motion":
                motion = try Self.boolean(value, name: flag)
            case "--audio":
                audio = try Self.boolean(value, name: flag)
            default:
                throw PerfError.invalidArgument("unknown option: \(flag)")
            }
            index += 2
        }
    }

    private static func boolean(_ value: String, name: String) throws -> Bool {
        switch value {
        case "on": true
        case "off": false
        default: throw PerfError.invalidArgument("invalid \(name): \(value)")
        }
    }
}

@MainActor
private final class WorkloadView: NSView {
    init(frame frameRect: NSRect, motion: Bool) {
        super.init(frame: frameRect)
        wantsLayer = true
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        root.frame = bounds
        layer = root

        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.18, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.24, green: 0.06, blue: 0.32, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.02, green: 0.28, blue: 0.30, alpha: 1).cgColor
        ]
        gradient.frame = bounds
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        root.addSublayer(gradient)

        let stripes = CALayer()
        let stripeWidth: CGFloat = 64
        stripes.frame = bounds.insetBy(dx: -stripeWidth, dy: 0)
        for index in 0 ..< 32 {
            let stripe = CALayer()
            stripe.backgroundColor = NSColor.white.withAlphaComponent(index.isMultiple(of: 2) ? 0.16 : 0.03).cgColor
            stripe.frame = CGRect(
                x: CGFloat(index) * stripeWidth,
                y: 0,
                width: stripeWidth,
                height: bounds.height
            )
            stripes.addSublayer(stripe)
        }
        root.addSublayer(stripes)

        let grid = CAShapeLayer()
        let path = CGMutablePath()
        for item in stride(from: CGFloat(0), through: bounds.width, by: 120) {
            path.move(to: CGPoint(x: item, y: 0))
            path.addLine(to: CGPoint(x: item, y: bounds.height))
        }
        for item in stride(from: CGFloat(0), through: bounds.height, by: 120) {
            path.move(to: CGPoint(x: 0, y: item))
            path.addLine(to: CGPoint(x: bounds.width, y: item))
        }
        grid.path = path
        grid.strokeColor = NSColor.white.withAlphaComponent(0.2).cgColor
        grid.lineWidth = 1
        root.addSublayer(grid)

        let label = CATextLayer()
        label.alignmentMode = .center
        label.contentsScale = 2
        label.fontSize = 72
        label.foregroundColor = NSColor.white.cgColor
        label.frame = CGRect(x: 0, y: bounds.midY - 48, width: bounds.width, height: 96)
        label.string = "Rokuga 4K Performance Workload"
        root.addSublayer(label)

        guard motion else { return }
        let translation = CABasicAnimation(keyPath: "transform.translation.x")
        translation.fromValue = 0
        translation.toValue = stripeWidth * 2
        translation.duration = 0.5
        translation.repeatCount = .greatestFiniteMagnitude
        translation.timingFunction = CAMediaTimingFunction(name: .linear)
        stripes.add(translation, forKey: "motion")

        let gradientMotion = CABasicAnimation(keyPath: "endPoint")
        gradientMotion.fromValue = CGPoint(x: 1, y: 1)
        gradientMotion.toValue = CGPoint(x: 0, y: 1)
        gradientMotion.duration = 2
        gradientMotion.autoreverses = true
        gradientMotion.repeatCount = .greatestFiniteMagnitude
        gradientMotion.timingFunction = CAMediaTimingFunction(name: .linear)
        gradient.add(gradientMotion, forKey: "gradient-motion")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ToneGenerator {
    private let engine = AVAudioEngine()
    private let source: AVAudioSourceNode

    init() throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else {
            throw PerfError.workloadUnavailable("cannot create the 48 kHz stereo audio format")
        }
        var phase = 0.0
        let increment = 2 * Double.pi * 440 / format.sampleRate
        source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0 ..< Int(frameCount) {
                let sample = Float(sin(phase) * 0.12)
                phase += increment
                if phase >= 2 * Double.pi {
                    phase -= 2 * Double.pi
                }
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
    }

    func start() throws {
        engine.prepare()
        try engine.start()
    }
}

private struct WorkloadResult: Codable {
    let command: String
    let pid: pid_t
    let widthPoints: Int
    let heightPoints: Int
    let backingScale: Double
    let widthPixels: Int
    let heightPixels: Int
    let motion: Bool
    let audio: Bool
}
