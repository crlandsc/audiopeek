![AudioPeek playwave mark](playwave-mark.png)

# AudioPeek

AudioPeek previews one audio file in a floating panel. The panel shows a waveform, a spectrogram, and playback.

Select one local supported file in Finder and press Option-Space. Open With and a file dropped on AudioPeek each preview one local supported file.

Space toggles play only while the panel is visible and Finder is the front app. Arrow keys still move the Finder selection.

The menu and the settings window say AudioPeek Settings. When the Dock icon and the menu-bar icon are both hidden, launch AudioPeek again, or use the settings control in the panel header.

## Install

Download the disk image from [GitHub Releases](https://github.com/crlandsc/audiopeek/releases). Open it and drag AudioPeek to Applications.

macOS may block the first open because the app is ad-hoc signed. Try to open AudioPeek, then click Open Anyway in System Settings > Privacy & Security. Apple describes this in [Safely open apps on your Mac](https://support.apple.com/en-us/102445).

## Login items

The first time AudioPeek opens an audio file, it turns the login toggle on and tries to register as a login item. If that fails, Settings asks you to add AudioPeek under Login Items. Use Open Login Items, or add it in System Settings > General > Login Items.

## Finder Automation

Allow AudioPeek to control Finder so the hotkey can read the selection. If the hotkey opens Settings, click Open Automation, enable AudioPeek for Finder, and press the hotkey again.

A new disk image is a new ad-hoc signature. After you replace the app, enable AudioPeek for Finder again under System Settings > Privacy & Security > Automation.

## License

MIT. Copyright (c) 2026 Christopher Landschoot. See [LICENSE](LICENSE).
