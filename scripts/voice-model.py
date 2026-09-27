#!/usr/bin/env python3
"""Stage the voice model under the names the app asks for.

The model is not ours and is not exported here: it is Quran-Lab's streaming
zipformer, a CTC model over a 251-symbol Qur'anic phoneme alphabet. What this
script does is pin *which* one, give the files the names `voiceModelParts`
uses, and compute the version key the app's origin path carries.

    https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3

The weights are gated on Hugging Face, so they are not fetched here — access
is granted to a person, not to a script. Download them once by hand, then:

    scripts/voice-model.py --from ~/Downloads/zipformer_p-arabic-v3 --out /tmp/voice

Then hand the directory to whoever has the Garage credentials, to go under
`<bucket>/ar-phoneme/<version>/`. The version is the digest of the files' own
digests, so a different model cannot land on the key a half-finished download
is resuming against — weights and a token table that disagree load without
complaint and transcribe nothing, which is a thing to debug once.

Licensed Quran-Lab No-Profit License 1.2. Three conditions bind us: the model
and anything it powers are never charged for, its output is never presented as
an authoritative ruling on somebody's recitation, and an application built on
it says plainly that automatic tajwīd feedback can be wrong and is not a
teacher. The third is a user-visible obligation and is met on the Sources
screen. ADR 0009 carries the reasoning; the LICENSE itself is inside the gate.

This replaced a multilingual transducer, which replaced whisper-base fine-tuned
on the Qur'an. Both are measured against this one in ADR 0009; the short of it
is that a multilingual model chooses a language from the first sounds of
بِسْمِ ٱللَّهِ and cannot be argued out of the choice, and an alphabet with no Latin
letter in it cannot make that mistake.
"""
import argparse, hashlib, pathlib, shutil

# What it is published as, and what the app asks for. The app's names say what
# each file is rather than how it was trained, because the path they sit under
# already pins the training.
PARTS = {
    "zipformer_p_arabic_v3.1.int8.onnx": "model.int8.onnx",
    "tokens.txt": "tokens.txt",
}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--from", dest="src", required=True,
                   help="the downloaded model directory")
    p.add_argument("--out", required=True)
    args = p.parse_args()
    src, out = pathlib.Path(args.src), pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    digests = []
    for published, ours in PARTS.items():
        target = out / ours
        if not target.exists():
            shutil.copyfile(src / published, target)
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        digests.append(digest)
        print(f"{digest}  {target.stat().st_size:>10} B  {ours}")

    # Each digest on its own line, the way `shasum | awk | shasum` produces
    # it — the convention the first model's key was minted under, and the
    # reason this is a function rather than a number somebody pasted.
    version = hashlib.sha256(
        "".join(d + "\n" for d in digests).encode()
    ).hexdigest()[:12]
    total = sum((out / n).stat().st_size for n in PARTS.values())
    print()
    print(f"version {version}, {total / 1e6:.1f} MB, {total} B")
    print(f"app/lib/data/speech.dart must say .../models/ar-phoneme/{version}/")


if __name__ == "__main__":
    main()
