import AppKit
import SwiftUI

extension WaveformColor {
    var nsColor: NSColor {
        if usesSystemBlue {
            return .systemBlue
        }
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

struct WaveformColorWell: NSViewRepresentable {
    var color: NSColor
    var onChange: (NSColor) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell(style: .expanded)
        well.color = color
        well.target = context.coordinator
        well.action = #selector(Coordinator.changed(_:))
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.onChange = onChange
        if well.color != color {
            well.color = color
        }
    }

    final class Coordinator: NSObject {
        var onChange: (NSColor) -> Void

        init(onChange: @escaping (NSColor) -> Void) {
            self.onChange = onChange
        }

        @objc func changed(_ sender: NSColorWell) {
            onChange(sender.color)
        }
    }
}
