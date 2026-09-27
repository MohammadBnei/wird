#!/usr/bin/env python3
"""Build a voice-follow fixture: a reciter heard by the shipped recogniser.

Voice-follow is graded against recordings rather than against opinion, and one
recording grades one voice. everyayah serves a file per aya, so concatenating
them gives exact aya boundaries without needing per-reciter word timings: the
truth a window is graded against is "which aya was being recited then", which
is reciter-independent and needs nobody to align anything by hand.

    scripts/voice-fixture.py --reciter Alafasy_128kbps --sura 96 --ayas 1-5 \
        --model /tmp/voice --out app/test/fixtures/alaq_alafasy_heard.json

Writes what the recogniser made of the audio, which is what the matcher is
graded on and is a few kilobytes rather than a few megabytes.

**This mirrors `PrayerVoice._handOver` deliberately**, down to the endpointing
and the single carried utterance. A fixture built any other way grades the
matcher on a transcript the app never sees, which is how five green fixtures
sat beside a feature that did not work on the owner's phone.
"""
import argparse, io, json, pathlib, urllib.request
import numpy as np, soundfile as sf, sherpa_onnx

RATE = 16000

# app/lib/data/speech.dart: heardQuiet. The quiet before the first word is not
# handed over, because what a recogniser invents out of a room is a phrase the
# matcher then has to refuse.
QUIET = 0.02


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


def open_recogniser(model):
    return sherpa_onnx.OnlineRecognizer.from_zipformer2_ctc(
        model=str(model / "model.int8.onnx"),
        tokens=str(model / "tokens.txt"),
        num_threads=2,
        sample_rate=RATE,
        feature_dim=80,
        enable_endpoint_detection=True,
    )


def listen(recogniser, audio, chunk_ms):
    """What the app would have had at each moment, fed as the phone feeds it.

    An utterance that ends is carried, and only the one before the one now
    being said — the same single-utterance memory `PrayerVoice` keeps, which is
    what lets the matcher read across the breath between two ayas without
    carrying a whole prayer.
    """
    stream = recogniser.create_stream()
    chunk = int(chunk_ms * RATE / 1000)
    windows, fed, carried, speaking = [], 0, "", False
    while fed < len(audio):
        piece = audio[fed : fed + chunk]
        fed += len(piece)
        if not speaking and np.max(np.abs(piece)) < QUIET:
            continue
        speaking = True
        stream.accept_waveform(RATE, piece)
        while recogniser.is_ready(stream):
            recogniser.decode_stream(stream)
        said = recogniser.get_result(stream)
        heard = f"{carried} {said}".strip()
        if recogniser.is_endpoint(stream):
            if said.strip():
                carried = said.strip()
            recogniser.reset(stream)
        windows.append({"atMs": int(fed * 1000 / RATE), "heard": heard})
    return windows


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--reciter", required=True)
    p.add_argument("--sura", type=int, required=True)
    p.add_argument("--ayas", required=True, help="1-5")
    p.add_argument("--model", required=True, help="a staged voice-model directory")
    p.add_argument("--out", required=True)
    p.add_argument("--chunk-ms", type=int, default=300)
    args = p.parse_args()

    first, last = (int(n) for n in args.ayas.split("-"))
    model = pathlib.Path(args.model)

    audio, bounds, urls = np.zeros(0, "float32"), [], []
    for aya in range(first, last + 1):
        one, url = fetch(args.reciter, args.sura, aya)
        urls.append(url)
        audio = np.concatenate([audio, one])
        bounds.append({"aya": aya, "endMs": int(len(audio) * 1000 / RATE)})

    windows = listen(open_recogniser(model), audio, args.chunk_ms)
    json.dump(
        {
            "what": f"{args.reciter} reciting {args.sura}:{first}-{last}, heard by "
            f"the phoneme recogniser in {model.name}",
            "audio": f"{urls[0]} .. {urls[-1]}, played back to back",
            "chunkMs": args.chunk_ms,
            "ayas": bounds,
            "windows": windows,
        },
        open(args.out, "w"),
        ensure_ascii=False,
        indent=1,
    )
    print(f"{args.out}: {len(windows)} chunks over {len(bounds)} ayas")


if __name__ == "__main__":
    main()
