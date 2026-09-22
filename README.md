# AudioPeek

AudioPeek previews the audio file you have selected in Finder. Option-Space opens a floating panel with a waveform, a spectrogram, and playback. Spacebar stays Apple's player.

The public repo is [https://github.com/crlandsc/audiopeek](https://github.com/crlandsc/audiopeek).

## Install

Download the AudioPeek disk image from [GitHub Releases](https://github.com/crlandsc/audiopeek/releases). Open it and drag AudioPeek to Applications.

macOS may block the first open because the app is ad-hoc signed. Try to open AudioPeek. Then open System Settings > Privacy & Security and click Open Anyway. Apple describes this path in [Safely open apps on your Mac](https://support.apple.com/en-us/102445).

## Login Items

The first time AudioPeek successfully opens an audio file, it turns on the login toggle and tries to register as a login item. If that registration fails, the toggle stays on and Settings tells you to add AudioPeek under Login Items. Use the Open Login Items button in Settings, or add AudioPeek yourself under System Settings > General > Login Items.

## Finder Automation

AudioPeek reads the Finder selection so the hotkey can open the selected file. Allow the Automation prompt for Finder. If the hotkey opens Settings, the Finder access section explains the grant and the Open Automation button opens System Settings > Privacy & Security > Automation. Enable AudioPeek for Finder, then press the hotkey again.

Every new disk image is a new ad-hoc signature, so macOS treats the update as a different app. After you replace AudioPeek with a newer disk image, grant Automation again: System Settings > Privacy & Security > Automation, and enable AudioPeek for Finder.

## Hidden menu bar and Dock icons

The Dock icon is hidden by default, and the menu-bar icon can be hidden too. When both are hidden, reach Settings in either of these ways:

- Launch AudioPeek a second time. The second launch opens Settings.
- Open the overlay and use the settings control in the header.

## How long the picture takes

Measured on an Apple M3 Max, factory knobs, mixdown spectrogram, about 1100 columns:

- About 6 seconds per hour at 44.1 kHz for WAV and AIFF.
- Compressed formats cost more, up to about 2x for Opus.
- The time scales with sample rate. A dual spectrogram is about 2x the mixdown.
- Tested through 3 hours and through 192 kHz PCM. Longer files still open.

MP3 does not exist above 48 kHz. Opus is always 48 kHz. AudioPeek has no length limit and no sample-rate ceiling.

## License

MIT. Copyright (c) 2026 Christopher Landschoot. See [LICENSE](LICENSE).
