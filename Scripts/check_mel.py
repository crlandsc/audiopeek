#!/usr/bin/env python3
"""Compare AudioPeek spectrogram columns to pinned librosa.

Reads the wav as data and does not play it. An import failure fails the check.
"""

import json
import sys

import librosa
import numpy
import scipy


def fail(message):
    print(message)
    sys.exit(1)


def main():
    if librosa.__version__ != "0.10.2" or numpy.__version__ != "1.26.4" or scipy.__version__ != "1.14.1":
        fail(
            "pinned imports were librosa %s numpy %s scipy %s"
            % (librosa.__version__, numpy.__version__, scipy.__version__)
        )
    if len(sys.argv) != 3:
        fail("usage: check_mel.py file.wav columns.json")
    audio, rate = librosa.load(sys.argv[1], sr=None, mono=True)
    with open(sys.argv[2], "r", encoding="utf-8") as handle:
        meta = json.load(handle)
    sample_rate = int(meta["sample_rate"])
    n_fft = int(meta["n_fft"])
    hop = int(meta["hop"])
    n_mels = int(meta["n_mels"])
    columns = int(meta["column_count"])
    if int(rate) != sample_rate or len(audio) == 0:
        fail("wav rate %s length %s" % (rate, len(audio)))
    spectrum = librosa.feature.melspectrogram(
        y=audio,
        sr=sample_rate,
        n_fft=n_fft,
        hop_length=hop,
        win_length=n_fft,
        window="hann",
        center=True,
        pad_mode="constant",
        power=2.0,
        n_mels=n_mels,
        fmin=0.0,
        fmax=sample_rate / 2,
        htk=False,
        norm="slaney",
    )
    reduced = numpy.zeros((columns, n_mels), dtype=numpy.float64)
    total = len(audio)
    for frame in range(spectrum.shape[1]):
        center = frame * hop
        column = min(columns - 1, (center * columns) // total)
        reduced[column] = numpy.maximum(reduced[column], spectrum[:, frame])
    swift = numpy.array(meta["mel"], dtype=numpy.float64)
    if swift.shape != reduced.shape:
        fail("shape swift %s librosa %s" % (swift.shape, reduced.shape))
    swift_db = librosa.power_to_db(swift, ref=numpy.max, top_db=80)
    librosa_db = librosa.power_to_db(reduced, ref=numpy.max, top_db=80)
    middle = slice(2, -2)
    delta = numpy.abs(swift_db[middle] - librosa_db[middle])
    worst = float(numpy.max(delta)) if delta.size else 0.0
    print("middle dB error %.4f" % worst)
    positive = (reduced[middle] > 1e-12) & (swift[middle] > 1e-12)
    if numpy.any(positive):
        ratio = swift[middle][positive] / reduced[middle][positive]
        print(
            "power ratio median %.6g p05 %.6g p95 %.6g"
            % (float(numpy.median(ratio)), float(numpy.percentile(ratio, 5)), float(numpy.percentile(ratio, 95)))
        )
    waveform_min = numpy.full(columns, numpy.inf)
    waveform_max = numpy.full(columns, -numpy.inf)
    for index, sample in enumerate(audio):
        column = min(columns - 1, (index * columns) // total)
        waveform_min[column] = min(waveform_min[column], sample)
        waveform_max[column] = max(waveform_max[column], sample)
    swift_min = numpy.array(meta["waveform_min"], dtype=numpy.float64)
    swift_max = numpy.array(meta["waveform_max"], dtype=numpy.float64)
    wave_error = max(
        float(numpy.max(numpy.abs(swift_min - waveform_min))),
        float(numpy.max(numpy.abs(swift_max - waveform_max))),
    )
    print("waveform error %.6f" % wave_error)
    if worst > 1.0 or wave_error > 0.002:
        fail("missed the 1 dB bar or the waveform columns")
    print("MEL CHECK PASS")


if __name__ == "__main__":
    main()
