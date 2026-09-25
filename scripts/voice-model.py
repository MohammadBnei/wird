#!/usr/bin/env python3
"""Fetch the voice model and stage it under the names the app asks for.

The model is not ours and is not exported here: it is a published streaming
zipformer transducer, int8, Arabic among eight languages. What this script
does is pin *which* one, give the files the names `voiceModelParts` uses, and
compute the version key the app's origin path carries.

    scripts/voice-model.py --out /tmp/voice

Then hand the directory to whoever has the Garage credentials, to go under
`<bucket>/ar-stream/<version>/`. The version is the digest of the files' own
digests, so a different model cannot land on the key a half-finished download
is resuming against — an encoder and a joiner that disagree load without
complaint and transcribe nothing, which is a thing to debug once.

The model this replaced was whisper-base fine-tuned on the Qur'an, exported by
a script that lived here until 2026-09-25. It spelled recitation better and
could not do the job: it answers once per window, so accuracy and latency are
one dial turned opposite ways. ADR 0005 has the measurement.
"""
import argparse, hashlib, pathlib, urllib.request

REPO = "csukuangfj/sherpa-onnx-streaming-zipformer-ar_en_id_ja_ru_th_vi_zh-2025-02-10"
STEM = "epoch-75-avg-11-chunk-16-left-128"

# What it is published as, and what the app asks for. The app's names say what
# each file is rather than how it was trained, because the path they sit under
# already pins the training.
PARTS = {
    f"encoder-{STEM}.int8.onnx": "encoder.int8.onnx",
    f"decoder-{STEM}.onnx": "decoder.onnx",
    f"joiner-{STEM}.int8.onnx": "joiner.int8.onnx",
    "tokens.txt": "tokens.txt",
}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True)
    args = p.parse_args()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    digests = []
    for published, ours in PARTS.items():
        target = out / ours
        if not target.exists():
            url = f"https://huggingface.co/{REPO}/resolve/main/{published}"
            print(f"fetching {ours} ...", flush=True)
            urllib.request.urlretrieve(url, target)
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        digests.append(digest)
        print(f"{digest}  {target.stat().st_size:>10} B  {ours}")

    # Each digest on its own line, the way `shasum | awk | shasum` produces
    # it — the convention the whisper model's key was minted under, and the
    # reason this is a function rather than a number somebody pasted.
    version = hashlib.sha256(
        "".join(d + "\n" for d in digests).encode()
    ).hexdigest()[:12]
    total = sum((out / n).stat().st_size for n in PARTS.values())
    print()
    print(f"version {version}, {total / 1e6:.1f} MB")
    print(f"app/lib/data/speech.dart must say .../models/ar-stream/{version}/")


if __name__ == "__main__":
    main()
