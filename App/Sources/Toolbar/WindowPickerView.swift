import AppKit
import CaptureKit
import SwiftUI

struct WindowPickerView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var windows: [WindowTarget] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose Window")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if windows.isEmpty {
                Text("No capturable windows")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(windows, id: \.windowID) { window in
                            windowRow(window)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 300)
        .task { await loadWindows() }
    }

    private func windowRow(_ window: WindowTarget) -> some View {
        Button {
            appState.selectedWindowTarget = window
            dismiss()
        } label: {
            HStack(spacing: 8) {
                appIcon(pid: window.appPID)
                VStack(alignment: .leading, spacing: 1) {
                    Text(window.appName ?? "Unknown")
                        .font(.system(size: 12, weight: .medium))
                    if let title = window.title {
                        Text(title)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if appState.selectedWindowTarget?.windowID == window.windowID {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func appIcon(pid: pid_t) -> some View {
        let icon = NSRunningApplication(processIdentifier: pid)?.icon ?? NSImage()
        return Image(nsImage: icon)
            .resizable()
            .frame(width: 20, height: 20)
    }

    private func loadWindows() async {
        guard let content = try? await ShareableContentService.currentContent() else {
            loading = false
            return
        }
        windows = ShareableContentService.windowTargets(from: content)
        loading = false
    }
}
