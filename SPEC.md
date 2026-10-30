# AudioPeek version 1

Build spec for the first version. A later session should be able to implement from this file alone. Decisions below are the resolution comments on the map's children. Ticket summaries are not the decision. Duplicate tickets [CHRIS-607](https://linear.app/cl-workflow/issue/CHRIS-607/decide-how-version-1-handles-long-files-and-high-sample-rates) and [CHRIS-608](https://linear.app/cl-workflow/issue/CHRIS-608/decide-whether-version-1-also-ships-a-quick-look-extension-for-types) are not sources.

Map: [Map: Configurable waveform and spectrogram preview for audio files in Finder](https://linear.app/cl-workflow/issue/CHRIS-574/map-configurable-waveform-and-spectrogram-preview-for-audio-files-in).

The viewer picture is the Slip bundle in [`prototypes/viewer-look.html`](prototypes/viewer-look.html) (default state: chrome Slip, colormap magma, cursor hairline). Port that chrome. Do not restyle it, and do not ship the Card or Scope variants on that page. Baked pixels live in [`prototypes/viewer-look-data.js`](prototypes/viewer-look-data.js). [`prototypes/build_viewer_look.py`](prototypes/build_viewer_look.py) only baked the mock; it is not the product DSP (see DSP).

Playback in the shipping app is required. For this project, playing or previewing any audio or video file the work needs is allowed, including Finder, Quick Look, the in-app player, and any other player. Chris reversed the earlier per-file permission rule on 2026-09-21. The librosa correctness check still compares its fixture as data.

## Machine load

The open file's playback and its overview are one preview. They start together. Playback continues while that picture fills or recomputes. Do not delay play until the picture finishes.

Before a heavy run, and about once a second while it is active, read `ProcessInfo.processInfo.thermalState` and one CPU-busy sample (`host_statistics` or equivalent). Do not busy-wait. Do not run `powermetrics`, do not ask for a password, and do not add a GPU-utilization sampler or a Metal dependency to read the GPU. Thermal state is the GPU signal. `nominal` and `fair` are runnable. `serious` and `critical` mean do not start, or pause.

CPU: pause when busy time is at or above 85% of the sample window. Resume only after one window at or below 70% and thermal state is `nominal` or `fair`.

Pressure pauses the overview at the next chunk, keeps columns already painted, and continues that same pass when headroom returns. A selection change, or a debounced redraw that changes the columns, discards a paused pass instead of resuming it. If playback itself is what is driving the pressure, pause playback too, then resume it from the same playhead at the same slider gain. No meter, history, log, threshold setting, or "analyzing" copy. This gate never refuses a file for length or sample rate.

One heavy pair at a time: overview plus playback of the current file. A second file, a second overview, or a test sweep does not start on top. Encodes and the old measurement matrix are not version 1 work and are not a ship gate. If a session runs any heavy command anyway, the same gate applies.

User autoplay uses the persisted slider. First launch of that slider is unity. It never changes system volume or the default output device, and it never boosts above unity. Agent and test playback, unless that run is the volume control, uses a process-local gain and does not write it into the persisted slider or the system volume. The librosa check still does not play.

## Build phases

These phases are the order to build what this spec already requires. They add no product surface. A session implements from SPEC.md and does not reopen Linear tickets to change version 1. Where a closure below is tighter than the linked ticket, it is an audit fence from 2026-09-21, on top of the Linear locks, not a new Linear ticket.

Start at the first OPEN row. Do not start a later phase. A row stays OPEN until its verification has been run and the evidence cell says what happened. "Implemented" or "builds" does not close a row. A session that dies mid-phase leaves the row OPEN. Do not rebuild PASS rows unless a later re-run fails them.

| Phase | Status | Evidence |
| --- | --- | --- |
| 1. App shell and settings blob | PASS | 2026-09-21. Ad-hoc `Signature=adhoc`, bundle id `com.landschoot.audiopeek`, `LSUIElement` true. Fresh suite matched the factory knobs, had no volume key, and had not written the blob. First launch did not open settings. A hidden status item plus a second launch opened Settings on the same pid and left the dock and menu-bar prefs unchanged. Dock toggle went accessory, then regular (`lsappinfo` UIElement, then Foreground), then accessory. Reset restored the factory knobs, kept volume 0.25 and frame x=10 y=20 w=860 h=500, and did not create a volume key when one was absent. Injected `kSMErrorInvalidSignature` (3) and `kSMErrorInternalFailure` (2) left the toggle on, offered Login Items, and did not show Registered. The settings snapshots show the factory form and that failure copy. |
| 2. Hotkey and Slip panel | PASS | 2026-09-21. Option-Space registered (status 0). A second registration of that combo returned `eventHotKeyExistsErr` (-9878). Bare space and unmodified arrow keys returned `paramErr` (-50) and were not registered. The Carbon handler toggled a non-activating panel. Empty, two audio files, mixed, text, `.ogg`, and a folder left it closed. One local `.wav` opened it at 860 by 500 with filename `tone.wav`, metadata `WAV`, and header order play, filename, metadata, volume, settings. The Finder timer was scheduled only while the panel was visible, followed a new file, and stopped after an empty selection closed the panel. A click outside left the panel up. Escape, delivered through the Carbon handler, closed the panel and unregistered Escape. Rebind to Control-Option-K freed Option-Space. Bare space did not replace the combo. Play did not start audio. The volume slider stored 0.4 and both system-volume reads matched. An injected Automation denial left the panel closed, showed "Enable AudioPeek for Finder" in settings, and did not say Registered. The usage string is present. No global event monitor, event tap, Accessibility API, or `NSAppleScript`. Re-run on 2026-09-21 used a 1 s wav, because a 4-byte file now closes the panel. The panel opened with metadata "WAV · 44.1 kHz · 1 ch · 0:01", autoplay was running, and play paused it. The hotkey, selection, escape, and volume checks passed. |
| 3. Playback and the machine-load gate | PASS | 2026-09-21. Injected nominal thermal state and CPU 0.2 autoplayed a 1.2 s, 44.1 kHz, mono silent wav from the start. Duration read 1.2 s. Metadata was "WAV · 44.1 kHz · 1 ch · 0:01". Autoplay left the volume key absent. Pause and resume kept the playhead. A waveform seek to 0.25 landed at 0.3 s, and a spectrogram seek to 0.5 landed at 0.6 s. With both panes hidden, seek left the playhead where it was. Hiding the panel stopped playback. Injected serious thermal state at CPU 0.1, nominal at 0.9, and fair at 0.75 left playback stopped. Nominal at 0.7 started it. Stored volume 0.3 survived a relaunch on a new pid. A slider value of 2 clamped to 1. The two system-volume reads matched. A 4-byte wav left the panel closed and playback stopped. The unit-test sampler's first host_statistics read had no CPU window, and the read 1.1 s later was a fraction in 0...1. xcodebuild test finished with TEST SUCCEEDED. Re-run on 2026-09-21 waited for the playhead after the overview published state. Waveform seek landed at 0.3 s and spectrogram seek at 0.6 s. The rest of the playback and gate checks passed. |
| 4. Waveform overview | PASS | 2026-09-21. The test config holds the pass between ExtAudioFile reads. After the first read, 5 of 860 columns were painted, the pass was still running, and the first column maximum was 1.0. Playback was running while the picture filled. Injected serious thermal state paused that same pass, left the 5 columns in place, and playback continued. Fair at CPU 0.75 added no columns. Nominal at 0.70 resumed the same pass and painted 10 columns, with playback still running. A Finder selection change published nothing further on the old pass, and the next pass painted its own columns. The in-flight count stayed at 1. A 16-channel file used the header "WAV · 44.1 kHz · 16 ch · showing 8 · 0:00" and drew 8 lanes. Dual off kept "16 ch" and drew 1 lane. A height change kept the pass. A width change to 700 restarted it once and the column count was 700. The unit tests matched mixdown min/max to the samples, kept the first 8 channels, and cancelled inside the read, including before open. |
| 5. Spectrogram in that same pass | PASS | 2026-09-21. The same ExtAudioFile read feeds the waveform and a Slaney mel spectrogram. Pinned librosa 0.10.2, numpy 1.26.4, and scipy 1.14.1 compared the shipping columns as data and did not play. Middle columns matched within 0.0000 dB after peak-normalize, the power ratio was 1, and the waveform min/max error was 0. A 30 s, 44.1 kHz sine hid the percent bar (estimate 0.05 s), kept the pass running after one chunk, drew 128 mel bins and 1 lane, and playback was running. A 12 min wav showed the bar (estimate 1.2 s). After one chunk the fill was 0.000258 and playback continued. Changing n_fft to 1024 during playback restarted that pass once and playback continued. The in-flight count stayed at 1. A 16-channel file with both dual views on used the header "WAV · 44.1 kHz · 16 ch · showing 8 · 16 ch · showing 2 · 0:00" and drew 2 spectrogram lanes. xcodebuild test finished with TEST SUCCEEDED. |
| 6. Appearance and waveform color | PASS | 2026-09-21. Forced dark restyled the Slip chrome to 0.165, 0.165, 0.173 and the hairline to 1, 0.271, 0.227 at 1 px. Forced light restyled the chrome to 0.953, 0.953, 0.961 and the hairline to 1, 0.231, 0.188. System blue followed the appearance: light green 0.533 and dark green 0.569, both blue-dominant. Neither change restarted the pass, and playback kept running. A color-well red overrode system blue without restarting the pass or stopping playback. Reset restored system blue and kept the same pass and playback. Settings exposed the waveform color well and no appearance toggle. The magma ends stay on the Slip colormap. xcodebuild test finished with TEST SUCCEEDED. |
| 7. Regression | PASS | 2026-09-21. Re-ran phases 1 through 6 and xcodebuild test. Phases 1, 4, 5, and 6 passed unchanged. Phase 2's 4-byte fixture now closes the panel, so that re-run uses a 1 s wav; it then passed, including autoplay. Phase 3's spectrogram seek passed once the check waited for the playhead past an overview state write. TEST SUCCEEDED. Play and decode go through the machine-load gate sample before they start. No 3-hour or 192 kHz timing run. |
| 8. Distribution | PASS | 2026-09-21. Release `codesign` reported `Signature=adhoc`, flags `0x2(adhoc)`, and bundle id `com.landschoot.audiopeek`. The disk image at `build/AudioPeek.dmg` holds AudioPeek.app plus an Applications alias. The mounted copy kept that ad-hoc signature and bundle id. README covers Open Anyway, Login Items, a second launch, the overlay settings control, and the Automation re-grant after a new disk image. LICENSE is MIT with `Copyright (c) 2026 Christopher Landschoot`. |

### 1. App shell and settings blob

Ad-hoc signed `LSUIElement` app, with the bundle id, no Dock icon by default, and a status item. Settings open from the status item and from a second launch. UserDefaults holds the factory knobs, reset, and the login toggle, including the invalid-signature path and any other failure path to Login Items.

Stop: no hotkey, no Finder event, no overlay, no decode, no playback, no DMG, no README. Development builds are ad-hoc signed from this phase so they launch.

Verification:

- Fresh defaults.
- A hidden status item still opens settings on a second launch.
- Dock toggle.
- Reset restores the factory knobs and does not touch a volume key.
- An injected `SMAppService` failure offers Login Items and does not show registered.

### 2. Hotkey and Slip panel

A Carbon hotkey toggles a non-activating Slip panel. Header order matches the prototype. The selection rule is exactly one file. Escape closes the panel. Clicking outside does not dismiss it. The Finder poll runs only while the panel is visible. Play and volume are visible and inert.

Stop: no audio output, no decode, no STFT.

Verification:

- Toggle, rebind, and a bare space hotkey is rejected.
- Mixed, empty, multi-file, and non-audio selections do nothing, or close the panel if it is up.
- Escape closes the panel. A click outside does not. Arrow keys are not taken.
- A hidden panel means the Finder timer is not scheduled.
- An injected Automation denial closes nothing via Accessibility and leaves the panel closed.
- The plist usage string is present.

### 3. Playback and the machine-load gate

One shared gate. Autoplay, seek, play/pause, volume persistence, and the unity cap.

Stop: no overview columns, no second sampler.

Verification:

- Injected `serious` thermal state, or injected CPU at or above 85%, does not start playback. When the sample clears (one window at or below 70%, and thermal state `nominal` or `fair`), playback starts.
- Autoplay from 0, pause and resume, and seek on both panes.
- Volume survives relaunch, never exceeds unity, and the run does not change system volume.
- A cool machine and an unread if do not close the row.

### 4. Waveform overview

One background chunked pass, one column per layout point. Cancel inside the read loop, including during open. Pressure pauses the pass, keeps the columns already painted, and resumes that same pass. A selection change discards it. Dual on draws the first 8 channels and uses the header pattern.

Stop: no STFT, no percent bar.

Verification:

- Columns appear before the pass finishes.
- Cancel after the first column publishes nothing further, and the next pass is not blocked.
- Injected `serious` thermal state pauses the overview, and playback continues.
- A second pass does not run beside the first.
- The header truncates a file with more than 8 channels.

### 5. Spectrogram in that same pass

Do not add a second decoder. Linear, log-frequency, and mel Slaney, with the factory knobs. Dual on draws the first 2 channels and uses the header pattern. A debounced knob change restarts the pass. The percent bar comes from the published estimate only. The librosa check compares shipping Swift columns to numpy and pinned librosa, as data, and does not play. An import failure fails the row. A miss on a frame or two at each end is allowed. A miss in the middle fails. The prototype bake script is not the reference. The M3 Max paragraph is not a test oracle and not a length cap. Use short fixtures.

Stop: no DMG.

Verification:

- The 1 dB bar.
- The estimate show and hide cases.
- A knob change during playback.
- The 2-channel header.

### 6. Appearance and waveform color

Live OS appearance, system blue, the color well, reset, magma, and the Slip hairline. Playback does not stop on an appearance change.

Stop: no packaging, no Card or Scope, no theme toggle.

Verification:

- Force light and force dark.

### 7. Regression

Re-run every earlier verification. No new behavior. Every play or decode samples the gate first.

Stop: no 3-hour or 192 kHz timing run.

Verification:

- Every earlier verification is run again.
- A failed re-run reopens that earlier row.
- Every play or decode samples the gate first.

### 8. Distribution

The DMG, the MIT license, the copyright line, and the README paths: Open Anyway, Login Items, hidden icons, and the Automation re-grant.

Stop: no Developer ID, notarization, Homebrew, or Sparkle.

Verification:

- `codesign` shows an ad-hoc signature.
- The bundle id matches.
- The README contains those paths.

## What it is

AudioPeek is a personal macOS tool being open sourced. It shows a configurable waveform and spectrogram, and plays the audio, for the file selected in Finder. A custom hotkey opens it. Space toggles play while the panel is visible and Finder is front, and is unregistered otherwise. Finder's arrow keys still move the selection.

Version 1 is a written product with one job: view and play. It is a quick Finder preview, not an analysis tool. People who want zoom already have better tools.

Sources: [Settle the destination and the first design decisions](https://linear.app/cl-workflow/issue/CHRIS-575/settle-the-destination-and-the-first-design-decisions), [Decide whether the spacebar takeover mode ships in version 1](https://linear.app/cl-workflow/issue/CHRIS-582/decide-whether-the-spacebar-takeover-mode-ships-in-version-1), [Choose the name, license, and how people install it without a paid Apple account](https://linear.app/cl-workflow/issue/CHRIS-585/choose-the-name-license-and-how-people-install-it-without-a-paid-apple), [Decide how version 1 handles long files and high sample rates](https://linear.app/cl-workflow/issue/CHRIS-605/decide-how-version-1-handles-long-files-and-high-sample-rates).

## Architecture

One ad-hoc signed app. Deployment target macOS 15 and later. One process, one app target. Swift. AppKit for the overlay and drawing. SwiftUI for the settings form. No web view. No XPC. No Quick Look extension. No event tap.

Folders inside the app target, not extra packages:

- **App**: hotkey, status item, login item.
- **FinderBridge**: Apple Events to Finder.
- **Viewer**: overlay and playback.
- **Analysis**: chunked decode, STFT, and mel on a background queue. A selection change discards the in-flight pass. Pressure pauses it (see Machine load). On that queue, call `ExtAudioFileOpenURL` and check cancel between every `ExtAudioFileRead`.
- **Settings**: a preference-style window with three toolbar panes (General, Waveform, Spectrogram), each a grouped SwiftUI form; the window title follows the pane and the window sizes to it. One UserDefaults blob. The engine rereads that blob when settings change and at the start of the next analysis pass. The remembered window frame lives in that blob. The volume slider is a separate persisted value.

The process is an `LSUIElement` menu-bar extra. No Dock icon by default. The status item is shown by default and can be hidden. It shows the play mark and does not show the name. Its menu is Settings and Quit. The app icon is that same mark. Playback and analysis stay in-process. The app is not sandboxed.

Start at login is a settings toggle. On the first successful open of exactly one audio file, turn that toggle on and attempt `SMAppService` once. That open is the first useful launch. If registration fails for any reason, not only `kSMErrorInvalidSignature`, the toggle stays on and tells the person to add AudioPeek under Login Items (`SMAppService.openSystemSettingsLoginItems`). Do not write a LaunchAgent or add a helper. The README covers that path.

Launching the already-running app, from Finder or Spotlight, orders the settings window front. It does not change the Dock-icon or menu-bar preference. The viewer hotkey never opens settings.

Sources: [Decide the app architecture and how the pieces fit](https://linear.app/cl-workflow/issue/CHRIS-581/decide-the-app-architecture-and-how-the-pieces-fit), [Settle the destination and the first design decisions](https://linear.app/cl-workflow/issue/CHRIS-575/settle-the-destination-and-the-first-design-decisions).

## Overlay UX

### Window

Non-activating floating panel so Finder stays the front app. Arrow keys are Finder's. AudioPeek follows the current selection. The hotkey toggles the panel. Clicking outside does not dismiss it.

The Carbon hotkey handler returns immediately. It does not wait on Finder, open, or decode. Escape is the panel's cancel action. It closes the panel without activating the app and without taking Finder's arrow keys or space. Do not install a global event monitor or an event tap.

First show is 860 by 500 points, centered on the screen of the front Finder window. After that, remember the frame in the settings blob. A width change is a column-grid change: debounce the drag (mouse-up, or about 200 ms after the last change), then restart the overview once. Split height does not restart the pass.

The panel is the Slip chrome: one compact header row, rounded panel, waveform above the spectrogram. On macOS 26 and later the panel is Liquid Glass (regular style, 18 pt continuous corners); on macOS 15 it is the same layout on a solid background. The waveform and spectrogram are solid cards inset 12 pt from the sides and bottom, with concentric corners and a 6 pt gap that holds the split handle. That glass rim (12 pt on the sides and bottom, 8 pt along the top, minus the header controls and the cut-away corners) is the resize grab area. Hovering it shows a soft rim glow that follows the pointer along the panel's outline, the hint that works while Finder is front. No pane labels. No separate transport bar. Header order, as drawn: play/pause, filename, compact metadata, volume slider, loop, subtle settings gear. Metadata sits against the volume control and the filename truncates first; the play time never truncates. Header text and icons use the system label colors. The gear opens the settings window.

Both panes start visible, split 50/50. The split is draggable and remembered. Hiding a pane gives the other the leftover height.

Sources: [Decide the app architecture and how the pieces fit](https://linear.app/cl-workflow/issue/CHRIS-581/decide-the-app-architecture-and-how-the-pieces-fit), [Define the version 1 settings, presets, and viewer interactions](https://linear.app/cl-workflow/issue/CHRIS-583/define-the-version-1-settings-presets-and-viewer-interactions), [Pick the look of the viewer window](https://linear.app/cl-workflow/issue/CHRIS-584/pick-the-look-of-the-viewer-window).

### Opening and following Finder

On the hotkey, ask Finder for its selection off the main thread. The handler has already returned.

Open only when the selection is exactly one supported audio file (formats below) and that file is already local. Any other count, including two or more audio files, does nothing and shows no banner. If the overlay is up, close it. Same for mixed, empty, non-audio, folders, packages, and files that are not already local.

A supported file that fails to open or decode, and a `.mp4` or `.m4a` with no decodable audio, is the same as non-audio: do nothing, or close if the overlay is up. No error window. A `.mp4` that has audio plays and draws audio only, no video picture.

While the overlay is visible, reread Finder about once a second. At most one Apple Event in flight, off the main thread, the same compiled event as the hotkey. If it has not returned, do not send another and do not shorten the interval. Only the latest completed read starts an overview. Do not queue passes. Do not poll while hidden. Do not switch the poll to Accessibility or an event tap.

When that read is a new single local audio file, discard any paused or in-flight overview, start playback from the beginning, and start a new overview. Hiding or closing the panel stops playback and cancels the overview. Nothing plays while it is hidden.

The resolutions describe one selected file. They do not describe a multi-file picture.

Sources: [Decide the app architecture and how the pieces fit](https://linear.app/cl-workflow/issue/CHRIS-581/decide-the-app-architecture-and-how-the-pieces-fit), [Define the version 1 settings, presets, and viewer interactions](https://linear.app/cl-workflow/issue/CHRIS-583/define-the-version-1-settings-presets-and-viewer-interactions), [Test whether catching the spacebar in Finder is reliable](https://linear.app/cl-workflow/issue/CHRIS-579/test-whether-catching-the-spacebar-in-finder-is-reliable).

### Playback

Autoplay when the overlay opens on exactly one supported audio file, and when Finder moves onto a new one. The playhead starts at 0. Playback and the overview start together. Playback continues while the picture fills or recomputes. Do not delay play until the picture finishes.

The overlay has a mouse play/pause control. Bare space toggles play through a Carbon hotkey while the panel is visible and Finder is front, and is unregistered otherwise. The panel does not become key, so Finder's arrow keys still change the selection. That space hotkey is not the viewer hotkey.

Click or drag a visible waveform or spectrogram to seek. While the mouse is down, playback stays silent and the playhead follows the pointer. On release, playback resumes only if it was playing before the drag. A paused file stays paused. Dragging the header moves the window. If no pane is shown, seek does nothing. No zoom. Loop is a header toggle, off by default. With loop off, the end pauses with the playhead at the end, and pressing play from there starts at 0. With loop on, the end starts again at 0 when the machine-load gate allows it.

Playback uses the file's normal Core Audio output mix. The 8-lane and 2-channel caps apply to the picture only. Playback does not change system volume or the default output device.

The volume slider lives on the overlay only. It is persisted and is not a page in the settings window. User autoplay uses that slider. First launch of the slider is unity. It never boosts above unity. Remember the last value. Reset does not change it (see Settings). Agent and test playback follows Machine load.

Hiding or closing the panel stops playback. Nothing plays while the panel is hidden. Playback streams the file.

Sources: [Settle the destination and the first design decisions](https://linear.app/cl-workflow/issue/CHRIS-575/settle-the-destination-and-the-first-design-decisions), [Define the version 1 settings, presets, and viewer interactions](https://linear.app/cl-workflow/issue/CHRIS-583/define-the-version-1-settings-presets-and-viewer-interactions), [Decide how version 1 handles long files and high sample rates](https://linear.app/cl-workflow/issue/CHRIS-605/decide-how-version-1-handles-long-files-and-high-sample-rates).

### Look

Follow the system appearance (`NSApp.effectiveAppearance` or equivalent), including a live change while the overlay is up. Both light and dark are required. There is no in-app light/dark toggle and no appearance knob in settings. An OS appearance change does not restart the overview pass and must not hitch playback.

The factory spectrogram colors are magma. Settings can also use inferno, viridis, or gray. Changing colors redraws the current picture and does not start a new overview pass.

The playhead is a 1 px vertical hairline on both panes. No grabber, no riding dot. Use the Slip playhead color from the prototype stylesheet. The volume slider fill and the loop-on state use the system accent color instead, drawn by the app so they stay colored while the panel is not the key window.

Waveform color defaults to `NSColor.systemBlue` (the standard light and dark system blues, not the user's accent color). A color well in the settings window can override it. Reset to default restores system blue.

Sources: [Pick the look of the viewer window](https://linear.app/cl-workflow/issue/CHRIS-584/pick-the-look-of-the-viewer-window). Picture: [`prototypes/viewer-look.html`](prototypes/viewer-look.html).

### Channels in the header

The header is always on, including when both panes are off. Play/pause and volume stay. A hidden pane is not computed. Seek does nothing until a pane is shown.

Mixdown does not add a showing-count. If a view is drawing fewer channels than the file has, say so in that header. The locked pattern is `16 ch · showing 8`. If both caps apply, list both in that same header.

- Waveform, dual off: mix every channel to mono. No showing-count.
- Waveform, dual on: the first 8 channels, one lane each. If the file has more, the header includes the locked pattern `16 ch · showing 8`.
- Spectrogram, dual off (the default): mixdown. No showing-count.
- Spectrogram, dual on: the first 2 channels only. If the file has more, the header says so in that same pattern (`N ch · showing 2`). A silent drop looks like a bug.

The progress "times 2" applies only when the spectrogram is visible and dual is on.

Sources: [Define the version 1 settings, presets, and viewer interactions](https://linear.app/cl-workflow/issue/CHRIS-583/define-the-version-1-settings-presets-and-viewer-interactions).

## Settings

One settings blob in the UI (UserDefaults or equivalent). No config file. No named presets. No backup store.

Reset All Settings (General, inside the collapsed Advanced section) immediately replaces the settings-window knobs with the factory set, including Option-Space, the login item, icon visibility, split 50/50, and the system-blue waveform. There is no undo. Every tab ends with a collapsed Advanced section; the Waveform and Spectrogram tabs' Advanced sections hold their own reset (Reset Waveform Settings, Reset Spectrogram Settings) that restores only that tab's settings, including the Spectrogram analysis values. Opening or closing Advanced resizes the window with the same animation as switching tabs. Reset does not change the volume slider or the remembered window frame. If the blob does not decode, use factory defaults and continue.

The window is small, in the spirit of Rectangle, DockDoor, and Hidden Bar. It holds:

**Chrome**

- Login item
- Menu-bar icon visibility
- Dock icon visibility
- Viewer hotkey, rebindable. Factory default Option-Space

**Viewer**

- Show waveform (default on)
- Show spectrogram (default on)
- Waveform dual view (default on)
- Spectrogram dual view (default off: mixdown)
- Waveform amplitude: linear or dB (default linear)
- Waveform color: system blue by default, color well to override
- Split: waveform on top, spectrogram below, 50/50, draggable, remembered

**Spectrogram**

- Type: linear STFT, log-frequency, or mel (default mel)
- `n_fft`, hop in samples, window (Hann, Hamming, or Blackman)
- `n_mels`, `fmin`, `fmax` in Hz
- dB on/off, dB floor, dB range
- Factory default: `n_fft` 2048, hop 512, Hann, 128 mels, `fmin` 0, `fmax` Nyquist, dB on, floor -80, range 80

Restart the overview only when the change affects decode or the columns: spectrogram knobs, waveform linear/dB, dual-channel toggles, show/hide of a pane, or the pane's width. Debounce slider and resize drags (mouse-up, or about 200 ms after the last change), then restart once. Playback continues through that restart. Waveform color, volume, split height, hotkey, login item, icon visibility, and an OS appearance change do not restart the pass and must not hitch playback.

The status item menu is Settings and Quit. Settings opens this window. The Dock icon, when shown, also opens it. So does a second launch, which orders the window front and does not change the Dock-icon or menu-bar preference. So does the overlay gear. The viewer hotkey does not.

Sources: [Define the version 1 settings, presets, and viewer interactions](https://linear.app/cl-workflow/issue/CHRIS-583/define-the-version-1-settings-presets-and-viewer-interactions), [Pick the look of the viewer window](https://linear.app/cl-workflow/issue/CHRIS-584/pick-the-look-of-the-viewer-window), [Decide the app architecture and how the pieces fit](https://linear.app/cl-workflow/issue/CHRIS-581/decide-the-app-architecture-and-how-the-pieces-fit).

## DSP

The app uses Accelerate for the FFT and a hand-built mel filterbank. Nothing Python ships in the app. The mel path is a power spectrogram with a Slaney mel bank. It is not Apple's DCT spectrogram sample, and it is not the HTK-shaped bank in `prototypes/build_viewer_look.py` (that script only drew the mock; the measured passes used an HTK-shaped bank and noted the FLOP count matches Slaney).

Analysis runs at the file's native sample rate. Read PCM in chunks. Do not keep the whole file in RAM.

Mixdown is the average of all channels before min/max and before the STFT. Linear waveform min/max is full-scale amplitude in -1...1, drawn as the Slip filled envelope in the prototype. Waveform dB is 20*log10 of the column's absolute peaks versus full scale, from -80 dBFS at the bottom of the lane to 0 dBFS at the top. Factory `fmax` is a sentinel for that file's Nyquist, not a stored 22050. A custom `fmax` is fixed Hz clamped to that file's Nyquist.

The overlay shows one full-file overview, squeezed to the pane width. One waveform min/max and one spectrogram column per layout point of the pane width, not per device pixel, and not capped at the measured ~1100 columns. Spectrogram columns take the max across hops that fall in that column. Waveform columns take min and max. Linear STFT and log-frequency use that same STFT and the same column reduction; the frequency axis is linear or logarithmic. Mel uses the Slaney bank and the `n_mels` / `fmin` / `fmax` knobs. When spectrogram dB is on, apply the floor and range. When spectrogram dB is off, show the power values.

Do not start a pass if hop is below 1, `n_fft` is below hop, `n_mels` is below 1, or `fmin` is not below `fmax`. That is not a file-length or sample-rate refuse. A hidden pane is not computed.

There is no zoom, no scroll, and no on-disk cache of the overview.

Sources: [Decide how waveform and spectrogram DSP is checked for correctness](https://linear.app/cl-workflow/issue/CHRIS-609/decide-how-waveform-and-spectrogram-dsp-is-checked-for-correctness), [Decide how version 1 handles long files and high sample rates](https://linear.app/cl-workflow/issue/CHRIS-605/decide-how-version-1-handles-long-files-and-high-sample-rates), [Survey prior art and the other ways to hook a preview into Finder](https://linear.app/cl-workflow/issue/CHRIS-577/survey-prior-art-and-the-other-ways-to-hook-a-preview-into-finder).

## Long files and published limits

Open immediately. Fill the header from file metadata. Start autoplay from the stream. Paint the waveform and spectrogram as they complete, left to right. Playback continues while that picture fills or recomputes. Do not delay play until the picture finishes. Files longer than 30 seconds use a coarser picture unless Full detail is on.

A selection change discards the in-flight pass, including a pass that pressure had paused. A debounced redraw that changes the columns does the same. Pressure does not discard it: pause at the next chunk, keep columns already painted, and continue that same pass when headroom returns (see Machine load).

Cancel, when it applies, has to stop the decode and the STFT, not only ignore the result. If it does not, the next file waits on the last one. On the measurement harness, cancel after the first column unwound in under 1 ms, and that was only because the pass actually stopped.

On the analysis queue, run `ExtAudioFileOpenURL` and check cancel between every `ExtAudioFileRead`. If the selection changed during the open, discard the file and do not start the pass. A slow open is not a reason to refuse the format or to move the open onto the main thread. There is no duration timeout.

### Envelope

Copy this. It is not a cap. Do not add a length limit, a sample-rate limit, or a refuse-to-open.

- Never truncate the picture; no length or sample-rate refuse-to-open.
- README-citeable: M3 Max, about 6 s per hour at 44.1 kHz WAV, up to about 2x for Opus; measured through 3 h and 192 kHz PCM. MP3 max 48 kHz (codec); Opus is 48 kHz (codec). Dual spectrogram about 2x mixdown.
- Progress: left-to-right fill always; thin determinate percent bar only when estimated fill is over about 1 s.

The README cites this paragraph, from [Decide what version 1 publishes as length and sample-rate limits](https://linear.app/cl-workflow/issue/CHRIS-611/decide-what-version-1-publishes-as-length-and-sample-rate-limits). Measured on an Apple M3 Max, factory knobs, mixdown spectrogram, about 1100 columns:

- About 6 seconds per hour at 44.1 kHz for WAV/AIFF.
- Compressed formats cost more, up to about 2x for Opus.
- Scales with sample rate. Dual spectrogram is about 2x mixdown.
- Tested through 3 hours. Longer still opens.

Files past the measured box still open. The overlay gets no extra untested-size note. The header stays the compact metadata above. There is no second wording for long or high-rate files, and no "analyzing" copy.

Codec facts, not AudioPeek limits: MP3 does not exist above 48 kHz. Opus is always 48 kHz. There is no product sample-rate ceiling. Analysis uses the file's native rate.

### Progress bar

Left-to-right fill always, including when the bar is hidden.

The bar is a thin determinate bar along the bottom edge of the existing header. Its fill is the percent. No separate numeral and no "analyzing" copy. Show it only when the written estimate is over about 1 s. The estimate, from the same ticket: 6 s per hour at 44.1 kHz, times (file SR / 44100), times up to 2x for compressed, times 2 only when the spectrogram is visible and dual is on. It tracks real fill. It is not a per-format gate and it does not refuse the file.

### What the measurements were

These numbers are evidence for the envelope. They are not product limits. Both passes were decode-as-data on an Apple M3 Max (36 GB), one thread, ExtAudioFile plus Accelerate, factory knobs, about 1100 columns, mixdown unless noted. Thermal state stayed nominal. Peak RSS stayed about 13-17 MiB.

[Measure how expensive a full-file overview pass is on this Mac](https://linear.app/cl-workflow/issue/CHRIS-610/measure-how-expensive-a-full-file-overview-pass-is-on-this-mac): WAV mixdown, about 5.6 s per hour per 44.1 kHz. First column is tens of milliseconds. A 3 h 44.1 kHz stereo file finished in about 17 s. A 3 h 192 kHz stereo file finished in about 82 s. Dual spectrogram on a 15 min 96 kHz stereo file was about 2.1× mixdown. Cancel after the first column on a 1 h 96 kHz file unwound in 0.01 ms when the pass stopped.

[Measure overview-pass cost for every native audio format version 1 will open](https://linear.app/cl-workflow/issue/CHRIS-612/measure-overview-pass-cost-for-every-native-audio-format-version-1): compressed decode does not dwarf the spectrogram. Against a same-duration WAV mixdown, long-file factors were about 1.0× AIFF, 1.1× ALAC, 1.25× AAC (`.m4a` and `.mp4`), 1.5× FLAC, 1.7× MP3, 2.3× Opus at 48 kHz. The published envelope rounds that to "up to about 2x for Opus". A 3 h Opus file finished in about 42 s. The progress estimate still uses "up to 2x for compressed", not this table as a gate.

Sources: [Decide how version 1 handles long files and high sample rates](https://linear.app/cl-workflow/issue/CHRIS-605/decide-how-version-1-handles-long-files-and-high-sample-rates), [Decide what version 1 publishes as length and sample-rate limits](https://linear.app/cl-workflow/issue/CHRIS-611/decide-what-version-1-publishes-as-length-and-sample-rate-limits), [Measure how expensive a full-file overview pass is on this Mac](https://linear.app/cl-workflow/issue/CHRIS-610/measure-how-expensive-a-full-file-overview-pass-is-on-this-mac), [Measure overview-pass cost for every native audio format version 1 will open](https://linear.app/cl-workflow/issue/CHRIS-612/measure-overview-pass-cost-for-every-native-audio-format-version-1).

## Formats

Version 1 decodes what macOS already decodes, and only that. No bundled third-party decoder.

Supported:

- WAV
- AIFF (`.aif` and `.aiff`)
- MP3 (codec maximum 48 kHz)
- AAC in `.m4a` and `.mp4`. A `.mp4` that has audio plays and draws audio only, no video picture. A `.mp4` or `.m4a` with no decodable audio is the same as non-audio.
- ALAC
- FLAC
- Opus in `.opus` only (Core Audio reports 48 kHz; the container measured was Ogg)

`.opus` only for Opus. An `.ogg` file stays unsupported even if it contains Opus. OGG Vorbis is out. Treat an unsupported file like any other file the app does not decode. Codec rate notes (MP3 max 48 kHz, Opus is 48 kHz) are codec facts. Do not refuse a file because of its reported sample rate.

Sources: [Decide whether version 1 ships a Quick Look extension for types Apple does not preview](https://linear.app/cl-workflow/issue/CHRIS-606/decide-whether-version-1-ships-a-quick-look-extension-for-types-apple), [Decide the app architecture and how the pieces fit](https://linear.app/cl-workflow/issue/CHRIS-581/decide-the-app-architecture-and-how-the-pieces-fit), [Decide what version 1 publishes as length and sample-rate limits](https://linear.app/cl-workflow/issue/CHRIS-611/decide-what-version-1-publishes-as-length-and-sample-rate-limits), [Measure overview-pass cost for every native audio format version 1 will open](https://linear.app/cl-workflow/issue/CHRIS-612/measure-overview-pass-cost-for-every-native-audio-format-version-1), [Settle the destination and the first design decisions](https://linear.app/cl-workflow/issue/CHRIS-575/settle-the-destination-and-the-first-design-decisions).

## Permissions

Version 1 asks for one privacy grant: Automation for Finder, the first time a hotkey reads the selection.

**Hotkey.** Carbon `RegisterEventHotKey`. The handler returns immediately. It does not wait on Finder, open, or decode. No Accessibility and no Input Monitoring. Factory combo is Option-Space. The same combo may be registered by other processes; rebind is the way out. Do not register bare space as the viewer hotkey. A separate Carbon hotkey takes bare space for play/pause while the panel is visible and Finder is front, and is unregistered otherwise. Do not use `NSEvent` global monitors or a `CGEvent` tap in version 1.

**Selection.** Apple Events to Finder's `selection`, via Scripting Bridge or a compiled Apple Event. Do not compile an `NSAppleScript` on every hotkey. Do not walk Finder's UI with Accessibility. If Automation is denied or the event fails, stop retrying and say so in the existing settings window (enable AudioPeek for Finder). Offer an Open Automation button that opens System Settings > Privacy & Security > Automation. Do not fall through to Accessibility. Info.plist includes `NSAppleEventsUsageDescription` so the prompt can appear. The app is not sandboxed. Version 1 leaves Hardened Runtime off. Do not turn it on in version 1. With Hardened Runtime on, Apple Events fail quietly unless `com.apple.security.automation.apple-events` is set.

**Login item.** On the first successful open of exactly one audio file, turn the login toggle on and attempt `SMAppService.mainApp` once. That open is the first useful launch. Registration may fail for any reason, not only `kSMErrorInvalidSignature` on an ad-hoc signature. The toggle stays on and tells the person to add AudioPeek under Login Items. Offer `SMAppService.openSystemSettingsLoginItems()` from the settings toggle when registration fails. Do not write a LaunchAgent or add a helper.

**TCC identity.** Ad-hoc signing uses a cdhash designated requirement. Each rebuild, and each new GitHub DMG, is a new identity. Finder Automation will need re-granting after updates, not only on first install. There is no Accessibility prompt in version 1, because there is no event tap.

Sources: [Find out which hotkey and Finder-selection APIs need which permissions](https://linear.app/cl-workflow/issue/CHRIS-580/find-out-which-hotkey-and-finder-selection-apis-need-which-permissions), [Decide the app architecture and how the pieces fit](https://linear.app/cl-workflow/issue/CHRIS-581/decide-the-app-architecture-and-how-the-pieces-fit), [Choose the name, license, and how people install it without a paid Apple account](https://linear.app/cl-workflow/issue/CHRIS-585/choose-the-name-license-and-how-people-install-it-without-a-paid-apple).

## Distribution

- Display name AudioPeek. The menu bar shows the play mark and does not show the name. The app icon is that mark. The standard About panel shows the name AudioPeek. Do not build a custom About window. The status item menu is Settings and Quit.
- Bundle id `com.landschoot.audiopeek`.
- Public repo `https://github.com/crlandsc/audiopeek`.
- MIT. Copyright line: `Copyright (c) 2026 Christopher Landschoot`.
- Version 1 ships as an ad-hoc signed DMG on GitHub Releases. Download, drag to Applications. No extra Terminal steps.
- Ad-hoc signing is required so the binary runs on Apple silicon. "Unsigned" in older notes means no paid Developer ID and no notarization. A binary with no signature at all will not run.
- No Homebrew, official or personal tap. No Sparkle. Updates are a new DMG, downloaded by hand.
- Every new DMG can trip Gatekeeper again and reset the Automation grant. Recovery is Open Anyway, then the Automation grant. Do not strip quarantine, disable Gatekeeper, notarize, or add Sparkle.
- README uses Apple's current Gatekeeper path: try to open the app, then System Settings > Privacy & Security > Open Anyway ([Safely open apps on your Mac](https://support.apple.com/en-us/102445)). Do not document the old right-click or Control-click Open.
- README also covers the Login Items fallback, the Automation re-grant after a new DMG, and how to reach settings when the menu-bar and Dock icons are hidden: launch the app a second time, or open the overlay and use the settings control.

Sources: [Choose the name, license, and how people install it without a paid Apple account](https://linear.app/cl-workflow/issue/CHRIS-585/choose-the-name-license-and-how-people-install-it-without-a-paid-apple), [Decide the app architecture and how the pieces fit](https://linear.app/cl-workflow/issue/CHRIS-581/decide-the-app-architecture-and-how-the-pieces-fit).

## Tests

Behavioral pass/fail is the phase checklist in Build phases. A row stays OPEN until that verification has been run. This section is the numeric bar.

The comparison is shipping Swift columns against numpy and pinned librosa. The pin lives in a test extra or a venv, not the app target. The app target does not import librosa. The check has already failed to import librosa once on this machine; an unpinned environment will lie. An import failure fails the check.

The check reads the fixture as data and does not play it. The decode still goes through the machine-load gate. The 15 s WAV used for the look mock is a fine fixture.

- Waveform min/max per chunk matches numpy on the same samples.
- Mel spectrogram is within about 1 dB of librosa `melspectrogram` / `power_to_db` after the same peak-normalize (0 dB at the max, floor -80, range 80).
- Reference settings: `stft` / `melspectrogram` / `power_to_db`, `n_fft` 2048, hop 512, Hann, 128 mels, `fmin` 0, `fmax` Nyquist, power spectrogram, Slaney mel.
- The test uses the same column reduction as the overlay: waveform min/max, spectrogram max across hops in the layout point.

Streaming Accelerate will not match librosa `center=True` on the first and last frames. Missing the 1 dB bar on a frame or two at each end is acceptable. A miss in the middle fails. `fmin` 0 is a corner; low bins may be the noisy ones. The prototype bake script is not the reference. The M3 Max paragraph is not a test oracle and not a length cap.

Sources: [Decide how waveform and spectrogram DSP is checked for correctness](https://linear.app/cl-workflow/issue/CHRIS-609/decide-how-waveform-and-spectrogram-dsp-is-checked-for-correctness).

## Non-goals

- Spacebar takeover, a swallowing event tap, or any Accessibility prompt. Space stays Apple's player. Revisit only in a later version that has a stable signature and a gap the hotkey cannot close. [Decide whether the spacebar takeover mode ships in version 1](https://linear.app/cl-workflow/issue/CHRIS-582/decide-whether-the-spacebar-takeover-mode-ships-in-version-1), [Test whether catching the spacebar in Finder is reliable](https://linear.app/cl-workflow/issue/CHRIS-579/test-whether-catching-the-spacebar-in-finder-is-reliable).
- A Quick Look Preview Extension. Apple's preview wins for types it already claims. Confirmed on this Mac for WAV and MP3 after a live magenta control on a UTI the probe owned. The native set leaves no leftover type for an extension to own. [Decide whether version 1 ships a Quick Look extension for types Apple does not preview](https://linear.app/cl-workflow/issue/CHRIS-606/decide-whether-version-1-ships-a-quick-look-extension-for-types-apple), [Confirm on this Mac that a Quick Look extension cannot replace Apple's audio preview](https://linear.app/cl-workflow/issue/CHRIS-578/confirm-on-this-mac-that-a-quick-look-extension-cannot-replace-apples), [Find out whether a Quick Look extension can replace Apple's audio preview](https://linear.app/cl-workflow/issue/CHRIS-576/find-out-whether-a-quick-look-extension-can-replace-apples-audio).
- An `.ogg` file, including one that contains Opus, and any bundled decoder (libsndfile, ffmpeg, or otherwise).
- Paid Developer ID, notarization, and the Mac App Store.
- Homebrew and Sparkle.
- Named presets, config files, zoom, loop, scroll, and an overview cache.
- Refusing or truncating on duration or sample rate.
- An in-app appearance toggle.
- A GPU-utilization sampler, a Metal dependency, `powermetrics`, a password prompt, or a user-facing CPU meter. Thermal state is the GPU signal.
- A multi-file gallery, or any picture for a selection that is not exactly one supported audio file.
- Editing, Windows, and Linux.

## Risks

These are the ones that change how the code has to be written.

**Sample thermal state and one CPU-busy reading before and during every heavy run.** About once a second. Thermal state is the GPU signal. Do not sample GPU utilization, do not run `powermetrics`, and do not add Metal to read the GPU. `serious` or `critical`, or CPU busy at or above 85% of the window, means do not start, or pause. Resume only after one window at or below 70% and thermal state `nominal` or `fair`. Pressure pauses the overview and keeps painted columns. One heavy pair at a time. See Machine load.

**A test that writes unity into the system volume can hurt hearing.** User autoplay uses the persisted slider and never changes system volume. Agent and test playback, unless that run is the volume control, stays on a process-local gain and does not write the persisted slider.

**Pressure that cancels instead of pausing will restart a long file forever.** Pause keeps the painted columns and continues the same pass. A selection change, or a debounced redraw that changes the columns, is what discards it.

**A hotkey handler that waits can wedge the run loop.** The Carbon handler returns immediately. It does not wait on Finder, open, or decode.

**A denied Automation grant with no settings copy looks like a dead app.** Say so in the existing settings window (enable AudioPeek for Finder). Do not fall through to Accessibility. That path invites an Accessibility "fix".

**Cancel must stop the in-flight overview.** A selection change, or a debounced redraw that changes the columns, drops the current pass. Pressure pauses that pass. The decode loop itself has to observe the cancel. A flag checked only after the file finishes leaves the next file waiting. Measured unwind was under 1 ms on WAV only when the harness stopped the pass. [Decide how version 1 handles long files and high sample rates](https://linear.app/cl-workflow/issue/CHRIS-605/decide-how-version-1-handles-long-files-and-high-sample-rates), [Measure how expensive a full-file overview pass is on this Mac](https://linear.app/cl-workflow/issue/CHRIS-610/measure-how-expensive-a-full-file-overview-pass-is-on-this-mac), [Decide what version 1 publishes as length and sample-rate limits](https://linear.app/cl-workflow/issue/CHRIS-611/decide-what-version-1-publishes-as-length-and-sample-rate-limits).

**A column-changing redraw restarts the whole pass.** Debounce slider and resize drags, then discard and start over once. Waveform color, volume, split height, and an OS appearance change do not restart it. Playback continues. On this M3 Max a 3 h 192 kHz spectrogram is on the order of a minute of work, so a column-changing knob change on a file like that will hitch for about that long. Weaker Macs are slower than the envelope. [Define the version 1 settings, presets, and viewer interactions](https://linear.app/cl-workflow/issue/CHRIS-583/define-the-version-1-settings-presets-and-viewer-interactions), [Decide what version 1 publishes as length and sample-rate limits](https://linear.app/cl-workflow/issue/CHRIS-611/decide-what-version-1-publishes-as-length-and-sample-rate-limits).

**Ad-hoc TCC resets on every new binary.** Automation grants are stored against a cdhash designated requirement. A rebuild, and a new DMG, will ask for Finder Automation again. Same bundle id and same path do not preserve the grant. [Find out which hotkey and Finder-selection APIs need which permissions](https://linear.app/cl-workflow/issue/CHRIS-580/find-out-which-hotkey-and-finder-selection-apis-need-which-permissions), [Choose the name, license, and how people install it without a paid Apple account](https://linear.app/cl-workflow/issue/CHRIS-585/choose-the-name-license-and-how-people-install-it-without-a-paid-apple).

**`SMAppService` may fail for any reason.** `register` can return `kSMErrorInvalidSignature` without an Apple-issued signature, and any other failure takes the same path. The toggle stays on. The settings toggle and the README have to send the person to Login Items. Do not write a LaunchAgent or add a helper. [Decide the app architecture and how the pieces fit](https://linear.app/cl-workflow/issue/CHRIS-581/decide-the-app-architecture-and-how-the-pieces-fit), [Find out which hotkey and Finder-selection APIs need which permissions](https://linear.app/cl-workflow/issue/CHRIS-580/find-out-which-hotkey-and-finder-selection-apis-need-which-permissions).

Also carried into the build:

- Poll Finder only while the overlay is visible, about once a second, with at most one Apple Event in flight. If it has not returned, do not send another and do not shorten the interval. A fast timer of Apple Events wedged Finder during the spacebar probe. [Decide the app architecture and how the pieces fit](https://linear.app/cl-workflow/issue/CHRIS-581/decide-the-app-architecture-and-how-the-pieces-fit), [Test whether catching the spacebar in Finder is reliable](https://linear.app/cl-workflow/issue/CHRIS-579/test-whether-catching-the-spacebar-in-finder-is-reliable).
- Option-Space can collide with another app, or insert a non-breaking space while a Finder rename field is active. Rebind is the way out. A Sequoia rule about Option-only Carbon hotkeys was reported for sandboxed apps and was not re-tested here for an unsandboxed ad-hoc app. The factory default stays Option-Space. [Define the version 1 settings, presets, and viewer interactions](https://linear.app/cl-workflow/issue/CHRIS-583/define-the-version-1-settings-presets-and-viewer-interactions), [Find out which hotkey and Finder-selection APIs need which permissions](https://linear.app/cl-workflow/issue/CHRIS-580/find-out-which-hotkey-and-finder-selection-apis-need-which-permissions).
- The hotkey has to feel instant, and the window has to follow Finder, or the sidecar feels worse than Apple's preview. Header and autoplay start before the overview finishes. [Decide whether the spacebar takeover mode ships in version 1](https://linear.app/cl-workflow/issue/CHRIS-582/decide-whether-the-spacebar-takeover-mode-ships-in-version-1).
- One cold MP3 open spent 2.2 s inside `ExtAudioFileOpenURL` before the first column. The next MP3 opened in 17 ms. A short file can hitch with the percent bar still hidden, because the estimate is under about 1 s. [Measure overview-pass cost for every native audio format version 1 will open](https://linear.app/cl-workflow/issue/CHRIS-612/measure-overview-pass-cost-for-every-native-audio-format-version-1).
- The 1 h and 3 h compressed timings looped a 15 min tile. A single long bitstream may differ. Dense noise is the pessimistic lossless case. A cold multi-gigabyte read can add I/O the tables do not show. Dual spectrogram was not re-run on compressed files; expect about 2× mixdown on top of the format factor. [Measure overview-pass cost for every native audio format version 1 will open](https://linear.app/cl-workflow/issue/CHRIS-612/measure-overview-pass-cost-for-every-native-audio-format-version-1), [Measure how expensive a full-file overview pass is on this Mac](https://linear.app/cl-workflow/issue/CHRIS-610/measure-how-expensive-a-full-file-overview-pass-is-on-this-mac).
- A live OS appearance change has to restyle the chrome and the default system-blue waveform without hitching playback. Magma was chosen against a dark appearance and may feel loud on the light Slip panel. There is no in-app theme switch. A custom waveform color can clash with magma. Reset wipes the settings knobs and leaves the volume slider and the remembered frame. There are no named saves. The hairline can disappear on bright magma bands. [Pick the look of the viewer window](https://linear.app/cl-workflow/issue/CHRIS-584/pick-the-look-of-the-viewer-window).
- Gatekeeper's Open Anyway step can return on every downloaded DMG. The name collides in search with smaller `audiopeek` / `audio-peek` tools and with an unrelated magician-app feature. [Choose the name, license, and how people install it without a paid Apple account](https://linear.app/cl-workflow/issue/CHRIS-585/choose-the-name-license-and-how-people-install-it-without-a-paid-apple).
- Hiding the status item and the Dock icon is recoverable only because a second launch opens settings and the overlay gear does too. Both have to keep working. [Decide the app architecture and how the pieces fit](https://linear.app/cl-workflow/issue/CHRIS-581/decide-the-app-architecture-and-how-the-pieces-fit).
