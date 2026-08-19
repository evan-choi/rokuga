import AppKit
import CoreGraphics
import Darwin
import Foundation

@main
enum RokugaPerf {
    static func main() async {
        if ProcessInfo.processInfo.environment["ROKUGA_PERF_SUSPEND_FOR_PROFILING"] == "1" {
            raise(SIGSTOP)
        }
        do {
            guard let command = CommandLine.arguments.dropFirst().first else {
                throw PerfError.usage
            }
            let arguments = Array(CommandLine.arguments.dropFirst(2))
            switch command {
            case "check-permission":
                try printJSON(PermissionResult(granted: CGPreflightScreenCaptureAccess()))
            case "permission":
                try printJSON(PermissionResult(granted: CGRequestScreenCaptureAccess()))
            case "record":
                guard CGPreflightScreenCaptureAccess() else {
                    throw PerfError.screenRecordingPermission
                }
                await initializeHeadlessApplication()
                try await printJSON(RecordCommand.run(arguments: arguments))
            case "workload":
                try await WorkloadCommand.run(arguments: arguments)
            default:
                throw PerfError.invalidArgument("unknown command: \(command)")
            }
        } catch {
            let message = "error: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit((error as? PerfError)?.exitCode ?? 1)
        }
    }

    @MainActor
    private static func initializeHeadlessApplication() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
    }

    static func printJSON(_ value: some Encodable, pretty: Bool = true) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

struct PermissionResult: Codable {
    let granted: Bool
}

enum PerfError: Error, CustomStringConvertible {
    case usage
    case invalidArgument(String)
    case screenRecordingPermission
    case captureTargetNotFound
    case firstFrameTimeout
    case workloadUnavailable(String)
    case outputInspection(String)

    var exitCode: Int32 {
        switch self {
        case .usage, .invalidArgument: 2
        case .screenRecordingPermission: 77
        default: 1
        }
    }

    var description: String {
        switch self {
        case .usage:
            "usage: RokugaPerf <check-permission|permission|record|workload> [options]"
        case let .invalidArgument(message):
            message
        case .screenRecordingPermission:
            "Screen Recording permission is not granted; run the explicit permission command"
        case .captureTargetNotFound:
            "capture target not found"
        case .firstFrameTimeout:
            "no complete video frame arrived within 5 seconds"
        case let .workloadUnavailable(message):
            message
        case let .outputInspection(message):
            message
        }
    }
}
