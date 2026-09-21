import AppKit
import Combine
import SwiftUI

@MainActor
final class HotkeyCapture: ObservableObject {
    @Published var recording = false
    @Published var rejection: String?
    var onCapture: (HotkeyCombo) -> Bool = { _ in false }
    private var token: Any?

    func begin() {
        recording = true
        rejection = nil
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func end() {
        recording = false
        if let token {
            NSEvent.removeMonitor(token)
            self.token = nil
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard recording else { return event }
        if event.keyCode == 53 {
            end()
            return nil
        }
        let combo = HotkeyCombo(event: event)
        if onCapture(combo) {
            rejection = nil
            end()
        } else {
            rejection = "Space by itself is not available."
        }
        return nil
    }
}

struct HotkeyRecorder: View {
    var combo: HotkeyCombo
    var onCapture: (HotkeyCombo) -> Bool
    @StateObject private var capture = HotkeyCapture()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Viewer hotkey")
                Spacer()
                Button(capture.recording ? "Type a shortcut" : combo.displayString) {
                    capture.onCapture = onCapture
                    if capture.recording {
                        capture.end()
                    } else {
                        capture.begin()
                    }
                }
            }
            if let rejection = capture.rejection {
                Text(rejection)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear { capture.end() }
    }
}
