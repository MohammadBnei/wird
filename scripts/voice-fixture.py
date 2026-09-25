#!/usr/bin/env python3
"""Build a voice-follow fixture: a reciter heard by the shipped recogniser.

Voice-follow is graded against recordings rather than against opinion, and one
recording grades one voice. everyayah serves a file per aya, so concatenating
them gives exact aya boundaries without needing per-reciter word timings: the
truth a window is graded against is "which aya was being recited then", which
is reciter-independent and needs nobody to align anything by hand.

    scripts/voice-fixture.py --reciter Alafasy_128kbps --sura 96 --ayas 1-5

Writes app/test/fixtures/<sura>_<reciter>_heard.json. The audio is not kept:
the fixture holds what the recogniser made of it, which is what the matcher is
graded on and is a few kilobytes rather than a few megabytes.
"""
import argparse, io, json, pathlib, urllib.request
import numpy as np, soundfile as sf, sherpa_onnx

RATE = 16000


def resample(data, rate):
    if data.ndim > 1:
        data = data.mean(axis=1)
    if rate == RATE:
        return data.astype("float32")
    n = int(len(data) * RATE / rate)
    return np.interp(
        np.linspace(0, len(data), n, endpoint=False), np.arange(len(data)), data
    ).astype("float32")


def fetch(reciter, sura, aya):
    url = f"https://everyayah.com/data/{reciter}/{sura:03d}{aya:03d}.mp3"
    with urllib.request.urlopen(url, timeout=60) as answer:
        data, rate = sf.read(io.BytesIO(answer.read()), dtype="float32")
    return resample(data, rate), url


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--reciter", required=True)
    p.add_argument("--sura", type=int, required=True)
    p.add_argument("--ayas", required=True, help="1-5")
    p.add_argument("--model", required=True, help="directory holding the three files")
    p.add_argument("--window-ms", type=int, default=4000)
    p.add_argument("--hop-ms", type=int, default=750)
    p.add_argument("--out", required=True)
    args = p.parse_args()

    first, last = (int(n) for n in args.ayas.split("-"))
    model = pathlib.Path(args.model)
    recogniser = sherpa_onnx.OfflineRecognizer.from_whisper(
        encoder=str(model / "quran-encoder.int8.onnx"),
        decoder=str(model / "quran-decoder.int8.onnx"),
        tokens=str(model / "quran-tokens.txt"),
        language="ar",
        task="transcribe",
        num_threads=2,
    )

    audio, bounds, urls = np.zeros(0, "float32"), [], []
    for aya in range(first, last + 1):
        one, url = fetch(args.reciter, args.sura, aya)
        urls.append(url)
        audio = np.concatenate([audio, one])
        bounds.append({"aya": aya, "endMs": int(len(audio) * 1000 / RATE)})

    windows = []
    at = args.window_ms
    while at <= len(audio) * 1000 / RATE:
        start = max(0, int((at - args.window_ms) * RATE / 1000))
        stream = recogniser.create_stream()
        stream.accept_waveform(RATE, audio[start : int(at * RATE / 1000)])
        recogniser.decode_stream(stream)
        windows.append({"atMs": at, "heard": stream.result.text})
        at += args.hop_ms

    json.dump(
        {
            "what": f"{args.reciter} reciting {args.sura}:{first}-{last}, "
            "heard by tarteel-ai/whisper-base-ar-quran",
            "audio": f"{urls[0]} .. {urls[-1]}, played back to back",
            "windowMs": args.window_ms,
            "hopMs": args.hop_ms,
            "ayas": bounds,
            "windows": windows,
        },
        open(args.out, "w"),
        ensure_ascii=False,
        indent=1,
    )
    print(f"{args.out}: {len(windows)} windows over {len(bounds)} ayas")


if __name__ == "__main__":
    main()
