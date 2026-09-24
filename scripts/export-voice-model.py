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
import pathlib
import subprocess
import sys
import urllib.request

import torch
import whisper
from transformers import WhisperForConditionalGeneration

EXPORTER = (
    'https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/master/'
    'scripts/whisper/export-onnx.py'
)

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
    for was, now in [
        (f'{args.name}-encoder.int8.onnx', 'quran-encoder.int8.onnx'),
        (f'{args.name}-decoder.int8.onnx', 'quran-decoder.int8.onnx'),
        (f'{args.name}-tokens.txt', 'quran-tokens.txt'),
    ]:
        served = args.out / now
        (args.out / was).rename(served)
        print(f'{served}  {served.stat().st_size / 1e6:.1f} MB')


if __name__ == '__main__':
    main()
