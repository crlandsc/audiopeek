<p align="center">
  <img alt="AudioPeek" src="audiopeek-logo.png" width="200">
</p>

# AudioPeek

AudioPeek is a lightweight app designed to supplement the audio preview on Mac.

When previewing audio files on Mac, have you ever wished you could see more than just a scrub bar? AudioPeek allows audio previews to render the waveform *and* spectrogram, filling the gap between a bare bones audio preview and having to import files into a professional audio application.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="audiopeek-preview-dark.png">
    <img alt="The AudioPeek preview panel showing a waveform above a spectrogram" src="audiopeek-preview.png">
  </picture>
</p>


## Install

Just like any other Mac application, download the disk image (`AudioPeek.dmg`) from [GitHub Releases](https://github.com/crlandsc/audiopeek/releases). Open it and drag AudioPeek to Applications.

#### IMPORTANT
The first open is *blocked*. macOS shows:
> Apple could not verify "AudioPeek.app" is free of malware that may harm your Mac or compromise your privacy.

This message is expected and requires a one-time action to enable the application:

1. In that dialog, click Done. *Do not* move the app to the Trash.
2. Open **System Settings** > **Privacy & Security**.
3. In the **Security** section, find AudioPeek and click "Open Anyway", then Open.

You only need to do this once. Apple walks through the same steps in [Safely open apps on your Mac](https://support.apple.com/en-us/102445).

#### Allow Finder access
AudioPeek needs to ask Finder which file you have selected. The first time you press the shortcut, macOS asks:
> "AudioPeek" wants access to control "Finder".

Click **Allow**. If you clicked **Don't Allow**, a **Finder access** section appears at the top of the General tab in AudioPeek's Settings. Click **Open Automation** there. That opens the Mac's Automation settings. Turn on **Finder** under AudioPeek, then press the shortcut again.


## How to use it

1. Select an audio file in Finder.
2. Press **Option-Space**.

That's it! AudioPeek opens a small panel over Finder, starts playing, and draws the waveform and spectrogram as it goes.

While the panel is open:

- **Arrow keys** still move around in Finder, and AudioPeek follows along to the next file.
- **Space** plays and pauses.
- **Click or drag** anywhere on the waveform or spectrogram to jump to that spot.
- There are **volume slider** and **loop button** controls in the top bar.
- **Esc** or **Option-Space** again closes the panel.

You can also right-click an audio file and choose **Open With** > **AudioPeek**, or drag a file onto the AudioPeek icon.

#### Supported files
AudioPeek plays anything your Mac already knows how to play:

- WAV
- AIFF (`.aif`, `.aiff`)
- MP3
- AAC and Apple Lossless (`.m4a`, `.mp4`)
- FLAC
- Opus (`.opus`)

For video files (`.mp4`), AudioPeek only shows and plays the audio. Long files work too (Tested on an M3 Max – AudioPeek reads about an hour of audio every 6 seconds, and it keeps playing the whole time).


## Settings

Open Settings from the AudioPeek icon in the menu bar, or from the gear in the top right of the panel. Settings has three tabs:

- **General**: change the **shortcut** from Option-Space to something else, turn **Open at login** on or off, show or hide the **menu bar icon** and the **Dock icon**, and choose whether to show the **waveform**, the **spectrogram**, or both (and how to split the space).
- **Waveform**: show every channel separately instead of one combined view (**dual view**), switch between linear and dB amplitude, and pick the waveform color.
- **Spectrogram**: dual view, the spectrogram type (linear, log frequency, or mel), its colors, and optional **frequency** and **time axes**.

Each tab ends with a collapsed **Advanced** section:

- **General** has **Full detail**, which reads every sample even for files longer than 30 seconds, and **Reset All Settings**, which puts every setting on all three tabs back to how it started.
- **Spectrogram** has the analysis controls (FFT size, hop, window, number of mel bands, frequency range, and dB range) if you want more control.
- **Waveform** and **Spectrogram** each have a reset that only touches that tab.

Resetting never changes the volume or the panel's size and position.

#### Accidentally hid both icons?
If you turned off the menu bar icon *and* the Dock icon, open AudioPeek again from Applications (or Spotlight) and Settings will be displayed.

#### Open at login
AudioPeek turns on **Open at login** the first time it opens a file, so the shortcut is always ready. You can turn it off in Settings. Next to it is an **Open Login Items** button that takes you to the Mac's Login Items settings. If macOS doesn't allow AudioPeek to add itself, Settings says so: click the button and add AudioPeek to the list.


## Updating

To update, download the newest `AudioPeek.dmg` from [GitHub Releases](https://github.com/crlandsc/audiopeek/releases), quit AudioPeek, and drag the new copy into Applications to replace the old one. Your settings are kept.

Each new version is treated by macOS as a new app, so you'll need to repeat two quick steps:

1. The **Open Anyway** step from [Install](#install).
2. Turn **Finder** back on for AudioPeek under **System Settings** > **Privacy & Security** > **Automation**.


## Requirements

- macOS 15 (Sequoia) or later
- A Mac with Apple silicon (M1 or newer)


## License

MIT. Copyright (c) 2026 Christopher Landschoot. See [LICENSE](LICENSE).
