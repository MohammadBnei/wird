#!/usr/bin/env python3
"""Turns the Qur'an-tuned Whisper checkpoint into the three files the app
downloads: an int8 ONNX encoder, an int8 ONNX decoder, and a token table.

    pip install torch transformers openai-whisper onnx onnxruntime onnxscript
    python scripts/export-voice-model.py

Two steps are not obvious, and ADR 0005 says why both matter. The HuggingFace
state dict has to be renamed into openai-whisper's own spelling before
sherpa's exporter will look at it, and the export has to go through the legacy
torch exporter: torch 2.14's dynamo export produces a graph sherpa-onnx loads
and then fails on, returning an empty transcript for every window rather than
an error.
"""

import argparse
import hashlib
import pathlib
import re
import subprocess
import sys
import urllib.request

import torch
import whisper
from transformers import WhisperForConditionalGeneration

# Apache-2.0 grants the conversion and its republication, and asks in return
# that the licence travel with it and that the changes be stated. Both happen
# here rather than by hand, so the upload is one command with nothing to
# remember. ADR 0007 has the rest.
CARD = """---
license: apache-2.0
base_model: {repo}
pipeline_tag: automatic-speech-recognition
language: ar
tags:
  - onnx
  - int8
  - sherpa-onnx
  - quran
---

# {name}, exported to ONNX for Wird

`{repo}` — whisper-base fine-tuned on `tarteel-ai/everyayah` — converted to
openai-whisper's own format, exported to ONNX with sherpa-onnx's
`export-onnx.py`, and quantised to int8 on `MatMul` only.

Three files, {size:.0f} MB together:

| File | What it is |
| --- | --- |
| `quran-encoder.int8.onnx` | the encoder |
| `quran-decoder.int8.onnx` | the decoder |
| `quran-tokens.txt` | the token table |

They are loaded by `sherpa-onnx` 1.13.8 as an offline Whisper recogniser, on
the phone, so that nothing anybody recites leaves it. Wird downloads them only
when a reader asks for voice-follow in Settings.

Nothing was retrained: the weights are upstream's, in another file format.
Reproduce with `scripts/export-voice-model.py` in
<https://github.com/MohammadBnei/wird>.

Licensed Apache-2.0, the licence the base model carries.
"""

EXPORTER = (
    'https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/master/'
    'scripts/whisper/export-onnx.py'
)

# The Garage store wird-api mints presigned GETs against. A phone asks
# wird.bnei.dev/models/<key> and is handed on; the bytes never cross the API.
STORE = 'https://s3.bnei.dev'
BUCKET = 'wird-models'
SPEECH = pathlib.Path(__file__).resolve().parent.parent / 'app/lib/data/speech.dart'


def published_key() -> str:
    """The bucket key the app is already asking for, read off the app.

    Typing it again here is how the last publish went to a host the app had
    stopped naming: the files landed somewhere real and every Download button
    still failed.
    """
    found = re.search(r"defaultVoiceModelOrigin\s*=\s*'([^']+)'", SPEECH.read_text())
    if not found or '/models/' not in found.group(1):
        sys.exit(f'{SPEECH} names no /models/ origin, so there is nowhere to publish')
    return found.group(1).split('/models/', 1)[1]

# HuggingFace on the left, openai-whisper on the right. Applied in order, as
# substring replacements, which is enough because the prefixes do not overlap.
NAMES = [
    ('model.', ''),
    ('encoder.embed_positions.weight', 'encoder.positional_embedding'),
    ('decoder.embed_positions.weight', 'decoder.positional_embedding'),
    ('decoder.embed_tokens.weight', 'decoder.token_embedding.weight'),
    ('.self_attn.', '.attn.'),
    ('.self_attn_layer_norm.', '.attn_ln.'),
    ('.encoder_attn.', '.cross_attn.'),
    ('.encoder_attn_layer_norm.', '.cross_attn_ln.'),
    ('.fc1.', '.mlp.0.'),
    ('.fc2.', '.mlp.2.'),
    ('.final_layer_norm.', '.mlp_ln.'),
    ('.q_proj.', '.query.'),
    ('.k_proj.', '.key.'),
    ('.v_proj.', '.value.'),
    ('.out_proj.', '.out.'),
    ('encoder.layer_norm.', 'encoder.ln_post.'),
    ('decoder.layer_norm.', 'decoder.ln.'),
    ('encoder.layers.', 'encoder.blocks.'),
    ('decoder.layers.', 'decoder.blocks.'),
]


def as_openai(repo: str, out: pathlib.Path) -> None:
    hf = WhisperForConditionalGeneration.from_pretrained(repo)
    weights = {}
    for key, value in hf.model.state_dict().items():
        for before, after in NAMES:
            key = key.replace(before, after)
        weights[key] = value

    c = hf.config
    dims = whisper.model.ModelDimensions(
        n_mels=c.num_mel_bins,
        n_audio_ctx=c.max_source_positions,
        n_audio_state=c.d_model,
        n_audio_head=c.encoder_attention_heads,
        n_audio_layer=c.encoder_layers,
        n_vocab=c.vocab_size,
        n_text_ctx=c.max_target_positions,
        n_text_state=c.d_model,
        n_text_head=c.decoder_attention_heads,
        n_text_layer=c.decoder_layers,
    )
    # Loud rather than nearly right: a mapping that has drifted leaves a model
    # that loads, runs, and transcribes noise.
    missing, unexpected = whisper.model.Whisper(dims).load_state_dict(
        weights, strict=False
    )
    if missing or unexpected:
        sys.exit(f'the name mapping has drifted: {missing} {unexpected}')
    torch.save({'dims': dims.__dict__, 'model_state_dict': weights}, out)


def exporter(name: str, into: pathlib.Path) -> pathlib.Path:
    path = into / 'export-onnx.py'
    source = urllib.request.urlopen(EXPORTER).read().decode()
    source = source.replace('"medium-aishell",', f'"medium-aishell", "{name}",', 1)
    source = source.replace(
        '    elif name == "medium-aishell":',
        f'    elif name == "{name}":\n'
        f'        return whisper.load_model("./{name}.pt")\n'
        '    elif name == "medium-aishell":',
        1,
    )
    source = source.replace(
        'opset_version=opset_version,', 'opset_version=opset_version,\n        dynamo=False,'
    )
    path.write_text(source)
    return path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', default='tarteel-ai/whisper-base-ar-quran')
    parser.add_argument('--name', default='base-ar-quran')
    parser.add_argument('--out', default='build/voice-model', type=pathlib.Path)
    args = parser.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    as_openai(args.repo, args.out / f'{args.name}.pt')
    script = exporter(args.name, args.out)
    subprocess.run(
        [sys.executable, script.name, '--model', args.name],
        cwd=args.out,
        check=True,
    )

    # The names the app asks the model origin for, in speech.dart.
    total = 0
    for was, now in [
        (f'{args.name}-encoder.int8.onnx', 'quran-encoder.int8.onnx'),
        (f'{args.name}-decoder.int8.onnx', 'quran-decoder.int8.onnx'),
        (f'{args.name}-tokens.txt', 'quran-tokens.txt'),
    ]:
        served = args.out / now
        (args.out / was).rename(served)
        total += served.stat().st_size
        digest = hashlib.sha256(served.read_bytes()).hexdigest()
        print(f'{served}  {served.stat().st_size / 1e6:.1f} MB  sha256:{digest}')

    card = args.out / 'README.md'
    card.write_text(CARD.format(repo=args.repo, name=args.name, size=total / 1e6))

    # Exporting is not publishing, and a file on the exporter's laptop is the
    # whole of what went wrong before: the app asked an origin that had never
    # been given anything. The last line of this script is the command that
    # makes the download real.
    key = published_key()
    print(
        f'\nexported, not published: a phone asking for these is answered '
        f'nothing until they are in the store wird-api signs against.\n'
        f'  aws --endpoint-url {STORE} s3 cp {args.out}/ s3://{BUCKET}/{key} '
        f"--recursive --exclude '*' --include 'quran-*' --include 'README.md'\n"
        f'\nRe-exported weights are a different model. Change the digest '
        f'segment of defaultVoiceModelOrigin in {SPEECH} and publish under the '
        f'new key, or a phone resumes a half-finished download onto weights it '
        f'never started against.'
    )


if __name__ == '__main__':
    main()
