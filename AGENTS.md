# AudioPeek – notes for coding agents

AudioPeek is a small macOS menu-bar app. Select one audio file in Finder, press a hotkey (Option-Space by default), and a floating panel shows its waveform and spectrogram and plays it. It is a quick Finder preview, not an analysis tool: view and play, no editing, no zoom.

README.md is the user-facing description. This file is for working on the code.

## Build and run

- Xcode project `AudioPeek.xcodeproj`, scheme `AudioPeek`, one app target plus `AudioPeekTests`. Swift, AppKit for the panel and drawing, SwiftUI for the Settings forms. Deployment target macOS 15. Apple silicon.
- Build: `xcodebuild -scheme AudioPeek -configuration Debug -destination 'platform=macOS' -derivedDataPath build/dd build`
- Unit tests: `xcodebuild test -scheme AudioPeek -destination 'platform=macOS' -derivedDataPath build/dd`
- No Xcode: `Scripts/build-app.sh` builds `build/AudioPeek.app` with only the Command Line Tools. It mirrors the Xcode target by hand.
- One dependency: Sparkle (the updater), a Swift package pinned to an exact version in the Xcode project. `Scripts/fetch-sparkle.sh` downloads that version into `build/sparkle/` for `build-app.sh` and the release scripts, checked against a pinned SHA-256. A new Sparkle version means the package pin in Xcode, `Package.resolved`, and the checksum in `fetch-sparkle.sh`.
- `build/` is gitignored; keep derived data, scratch output and disk images there.
- Source folders are Xcode synchronized groups, so new files are picked up without editing `project.pbxproj`.

## Code map

- `AudioPeek/App/`: `AppDelegate` (wiring, second launch opens Settings), `HotkeyCenter` (Carbon hotkeys: the viewer hotkey, Escape, and Space while the panel is up), `StatusItemController`, `LoginItemController` (`SMAppService`), `PlaywaveMark` (the eye logo, drawn in code, with an optional update dot), `UpdateController` (the updater: Sparkle in a normal launch, a recording fake under tests), `TestBridge` (test hooks, see below).
- `AudioPeek/FinderBridge/`: asks Finder for its selection with a compiled Apple Event, and decides whether it is exactly one supported, local audio file.
- `AudioPeek/Viewer/`:
  - `SlipPanelController`: the panel's lifecycle, Finder polling, playback, and starting and cancelling overview passes.
  - `SlipContentView`: all drawing and mouse handling: header, panes, glass rim, resize zones and rim glow, axes, playhead.
  - `PlaybackController`: AVAudioEngine playback, seek, loop, volume.
  - `WaveformOverview`: the background pass that reads the file and builds waveform columns.
  - `SpectrogramPass`: STFT, mel bank and column reduction, fed by that same read.
  - `MachineLoadGate`: thermal and CPU check before and during heavy work.
- `AudioPeek/Settings/`: `SettingsBlob` (every knob, one Codable value in UserDefaults), `SettingsStore`, `SettingsView` (the General, Waveform and Spectrogram panes), `SettingsWindowController` (toolbar panes, the window-resize animation).

## Rules the code depends on

- **The panel never becomes key.** It is a non-activating floating panel, so Finder stays frontmost and keeps its arrow keys. Anything that needs focus (text fields, color pickers) lives in the Settings window. Controls that use the accent color are drawn by the app, because a non-key panel would draw them gray.
- **No Accessibility, no event taps, no global event monitors.** Hotkeys are Carbon `RegisterEventHotKey`. The handler returns at once and never waits on Finder, file opening or decoding.
- **Finder polling** runs only while the panel is visible, about once a second, with at most one Apple Event in flight. A fast poll has wedged Finder before.
- **Exactly one supported local audio file** opens the panel. Anything else does nothing, or closes the panel if it is up. Formats are whatever Core Audio decodes: WAV, AIFF, MP3, AAC and ALAC (`.m4a`, `.mp4`, `.aac`), FLAC, Opus (`.opus`), Ogg Vorbis and Opus (`.ogg`), CAF, and the audio of `.mov`. No bundled decoders, so `.mkv`, `.webm` and `.wma` stay out; `.oga` opens but reports no length, so it stays out too. Ogg decoding was verified on macOS 27.2 only. Adding a format means the extension set in `AudioFileKind`, a document type in `Info.plist` (a unit test keeps their extension lists equal), the README list, and a decode test in `FormatDecodeTests`. Launch Services matches document types by UTI, not extension, so a type can bring along extensions AudioPeek refuses: `org.xiph.ogg-audio` also covers `.oga`, which then shows AudioPeek under Open With and does nothing when chosen.
- **Playback and the picture start together.** Never delay play until the picture finishes. Hiding the panel stops playback and cancels the pass.
- **One overview pass at a time.** A new selection, or a change that alters the columns (pane width, spectrogram settings, dual view, amplitude scale, showing or hiding a pane), cancels the pass and starts again. Debounce drags first. Color, volume, split height and appearance changes only redraw. Cancel is checked inside the read loop, not only at the end.
- **Machine load.** Before and about once a second during heavy work, read `ProcessInfo.thermalState` and one CPU sample. `serious` or `critical`, or CPU at or above 85%, pauses the pass (painted columns stay) and resumes it at or below 70%. No `powermetrics`, no GPU sampler, no Metal.
- **Volume.** The panel's slider is the only volume control. It never changes system volume and never goes above unity. Tests and agent runs use a process-local gain and must not write the saved slider or the system volume.
- **No length or sample-rate limits.** Long files open and paint left to right. A thin progress bar appears only when the estimated fill time is over about 1 s.
- **Appearance** follows the system live, light and dark. On macOS 26 and later the panel is Liquid Glass; on macOS 15 it is the same layout on a solid background.
- **Two build paths.** `Scripts/build-app.sh` copies the Xcode target's settings by hand: Swift flags, `Info.plist` variables, deployment target, signing, resources and the embedded Sparkle framework (headers stripped, only the framework re-signed, as Xcode does). Change one, change the other. `Scripts/check-builds.sh` catches drift, including byte-for-byte differences in the embedded frameworks and in the updater's `Info.plist` keys. New Swift files need nothing; the script finds them.
- **Updates.** Sparkle starts only in a normal launch. Unit tests and `--test-config` runs get `RecordingUpdaterDriver`, so no test starts an updater or reaches the network. A scheduled check never opens a window: it sets the dot on the menu bar eye, the "Update to …" menu title and the line in Settings, and choosing any of them opens Sparkle's window. Automatic installs (off by default) wait until AudioPeek is idle (no panel, nothing playing, Settings closed) or quits. No Notification Center alerts.
- **Locked in since 2.6.** The feed URL (`SUFeedURL`), the update public key (`SUPublicEDKey`), the release certificate (pinned in `Scripts/release-common.sh`) and the bundle id. Changing any of them strands installed copies or resets their Finder permission. Unit tests guard the feed URL and the key.

## DSP

- One read of the file (ExtAudioFile, native sample rate, in chunks) feeds both the waveform and the spectrogram. Never add a second decoder pass.
- One column per layout point of the pane width, not per device pixel. Waveform columns hold min and max. Spectrogram columns take the max over the hops that land in them. Columns no hop lands in repeat their neighbor.
- Spectrogram: Accelerate FFT, power spectrogram, and a hand-built Slaney mel bank (not HTK). Types are linear, log frequency and mel. Factory settings: n_fft 2048, hop 512, Hann, 128 mels, fmin 0, fmax at Nyquist, dB on with floor -80 and range 80, magma colors.
- Mixdown averages all channels. Dual view draws up to 8 waveform lanes and 2 spectrogram lanes, and the header says so (`16 ch · showing 8`).
- Files over 30 s use a coarse pass unless Full detail is on: each column reads only up to one window of samples (`OverviewDetail.inspectFrames`), with the hop raised to match. Core Audio's Opus decoder comes back from a seek quiet and needs about 240 ms to reach full level, so for Opus the reader seeks 240 ms early and throws that pre-roll away (`WaveformReader.seekPreroll`). It only seeks past gaps longer than the pre-roll, so the coarse pass never decodes more than a full read.

## Tests

- **Unit tests** (`AudioPeekTests/`) cover the DSP, the overview pass, settings coding, layout, resize zones and playback logic. Run them all after any change.
  - `AudioPeekTests/Fixtures/` holds small files Core Audio can't write itself (Ogg Vorbis, Opus in Ogg, a `.mov` with video), made once with ffmpeg. `silence.ogg` is the one end-to-end checks may play.
  - The decode tests need the system's audio codecs. A sandboxed shell can hide them and make Ogg, AAC and MOV look unsupported, so run tests unsandboxed.
- **Sound.** Unit tests and `verify-panel`, `verify-settings` and `verify-playback` play only silence. `verify-spectrogram` and `verify-appearance` open a 440 Hz tone and play it at full volume, and `Scripts/check-builds.sh` runs `verify-appearance`. Warn the user before running those.
- **End-to-end checks** (`Scripts/verify-*.swift`) launch a real instance of the app and drive it through `TestBridge`, checking settings, the panel and hotkeys, playback and the machine-load gate, the waveform, the spectrogram and appearance. Run each as `swift Scripts/verify-<name>.swift <path to AudioPeek.app>`, against any build (a Debug build day to day, `build/AudioPeek.app` from `Scripts/build-app.sh` in `check-builds`). Compile `verify-spectrogram` with `swiftc -O` first; it is slow interpreted.
  - They quit any running AudioPeek first, so warn the user before running them.
  - Timers also write the test state, so a script never treats the next write as a command's reply. Each command carries a `commandID`, and the script waits for that id in `lastCommandID`. To wait for a Finder read, wait until `finderReadCount` equals `finderRequestCount`. Wait for conditions, not fixed sleeps.
  - `TestBridge` only activates when the app is launched with `--test-config <json>`. That config gives the run its own UserDefaults suite and can inject Finder selections, machine load and login failures, so the checks never touch the user's settings.
- **librosa check**: `verify-spectrogram` runs `Scripts/check_mel.py`, which compares the shipping mel columns to pinned librosa within about 1 dB, reading the audio as data. It needs a venv at `build/mel-check`: `python3 -m venv build/mel-check && build/mel-check/bin/pip install -r Scripts/mel-requirements.txt`. An import failure fails the check.

## Icon and logo

The logo, an outlined eye with a waveform iris, is drawn in code (`PlaywaveMark`). `Scripts/render-playwave.swift` writes the app icon set and the README logo from it:

```bash
swiftc AudioPeek/App/PlaywaveMark.swift Scripts/render-playwave.swift -o build/render-playwave
build/render-playwave AudioPeek/Assets.xcassets/AppIcon.appiconset audiopeek-logo.png
```

## Releasing

- Releases are signed with a self-signed certificate ("AudioPeek Release Signing"), not notarized, and published by hand on GitHub Releases. No Developer ID or Homebrew. Both build paths stay ad-hoc signed so anyone can build from source; only `Scripts/release.sh` uses the certificate.
- Two keys, both in Chris's login keychain and backed up in a password manager, never in the repo: the certificate, whose fixed identity keeps the Finder permission across updates, and Sparkle's EdDSA update key (keychain account `audiopeek`), which signs every update. `Scripts/make-release-keys.sh` made them; agents never handle the private halves.
- Version: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.pbxproj` (two build configurations each). Bump both and commit.
- Run `Scripts/check-builds.sh` and confirm every step passes.
- Write the release notes to `build/release-notes-<version>.md`. They appear in the update window and on the GitHub release.
- Before a release that changes anything about updating or signing, run `Scripts/rehearse-update.sh` and walk through the update it prints, with Chris at the keyboard.
- Run `Scripts/release.sh`. It builds a clean Release, re-signs it inside out with the certificate, checks the identity, makes `build/release/AudioPeek.dmg`, writes `build/release/appcast.xml`, and verifies the appcast's signature against the key inside the built app. It prints the `gh release create` command; Chris runs it. Every release uploads both files: installed copies read `appcast.xml` from the latest release.
- After publishing, check that the feed URL serves the new appcast and that an installed copy finds the update.
- The README's install and update sections explain the flow to users; keep them in sync with any change to it.

## Not in scope

Developer ID signing and notarization, Homebrew, delta updates and beta channels, Quick Look extensions (Apple's preview wins for audio types), taking over Finder's spacebar, Accessibility prompts, bundled decoders (and the formats only they would open: `.mkv`, `.webm`, `.wma`), zoom and scroll, an overview cache, named presets, an in-app light/dark switch, and refusing files for length or sample rate.
