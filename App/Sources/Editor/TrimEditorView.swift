import AppKit
import SwiftUI
import TrimKit

struct TrimEditorView: View {
    @ObservedObject var model: TrimEditorModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrubbablePlayerView(player: model.player) { [weak model] deltaX, width in
                model?.scrub(deltaX: deltaX, viewWidth: width)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            controls
            TimelineRepresentable(model: model)
                .frame(height: 72)
                .padding(.horizontal, 16)
                .accessibilityLabel(Text("Trim timeline"))
                .accessibilityValue(Text(verbatim: "\(timeLabel(model.startSeconds)) – \(timeLabel(model.endSeconds))"))
                .accessibilityHint(Text("Use Arrow keys to nudge the start handle by one frame, Option-Arrow for the end handle"))
            footer
        }
        .frame(minWidth: 640, minHeight: 460)
        .background(Color(red: 0.11, green: 0.11, blue: 0.13))
        .preferredColorScheme(.dark)
        .sheet(isPresented: exportSheetShown) {
            exportProgressSheet
        }
        .alert(
            "Export Failed",
            isPresented: Binding(
                get: { model.exportError != nil },
                set: { if !$0 { model.exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.exportError ?? "")
        }
        .background(nudgeShortcuts)
    }

    private var exportSheetShown: Binding<Bool> {
        Binding(get: { model.exportProgress != nil }, set: { _ in })
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(action: model.togglePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(Text(model.isPlaying ? "Pause" : "Play"))

            Text(verbatim: "\(timeLabel(model.startSeconds)) – \(timeLabel(model.endSeconds))  (\(timeLabel(model.endSeconds - model.startSeconds)))")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            Image(systemName: "minus.magnifyingglass")
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { log2(model.pointsPerSecond) },
                    set: { model.pointsPerSecond = pow(2, $0) }
                ),
                in: log2(TrimEditorModel.minPointsPerSecond)...log2(TrimEditorModel.maxPointsPerSecond)
            )
            .frame(width: 130)
            .controlSize(.small)
            .accessibilityLabel(Text("Timeline zoom"))
            Image(systemName: "plus.magnifyingglass")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Frame-exact (re-encode)", isOn: $model.frameExact)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            Button("Export Audio Only…") { runExport(kind: .audioOnlyM4A) }
                .disabled(!model.hasAudio)

            Spacer()

            Button("Cancel", action: onClose)
                .keyboardShortcut(.cancelAction)
            Button("Save As…") { runExport(kind: model.frameExact ? .frameExact : .passthrough) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var exportProgressSheet: some View {
        VStack(spacing: 14) {
            ProgressView(value: model.exportProgress ?? 0)
                .frame(width: 260)
            Text(verbatim: "\(Int((model.exportProgress ?? 0) * 100))%")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Button("Cancel", action: model.cancelExport)
        }
        .padding(24)
    }

    /// Hidden buttons give frame-level arrow nudges full keyboard operability (tasks 8.5/9.5).
    private var nudgeShortcuts: some View {
        Group {
            Button("") { model.nudge(.start, byFrames: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { model.nudge(.start, byFrames: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { model.nudge(.end, byFrames: -1) }
                .keyboardShortcut(.leftArrow, modifiers: .option)
            Button("") { model.nudge(.end, byFrames: 1) }
                .keyboardShortcut(.rightArrow, modifiers: .option)
            Button("") { model.zoom(by: 1.25) }
                .keyboardShortcut("+", modifiers: .command)
            Button("") { model.zoom(by: 0.8) }
                .keyboardShortcut("-", modifiers: .command)
            Button("") { model.resetZoom(fittingWidth: 640) }
                .keyboardShortcut("0", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    private func runExport(kind: TrimExportKind) {
        model.pause()
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.directoryURL = OutputFolderStore.currentFolder()
        let base = model.url.deletingPathExtension().lastPathComponent
        switch kind {
        case .audioOnlyM4A:
            panel.nameFieldStringValue = base + " (Audio).m4a"
        default:
            panel.nameFieldStringValue = base + " (Trimmed)." + model.url.pathExtension
        }
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task { await model.export(kind: kind, to: destination) }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
