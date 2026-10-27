# Image generation (optional)

A separate ComfyUI stack on one GPU. It is not needed for text inference and does
not share the router's lifecycle. About 40 GB of disk and a second 16 GB card are
the practical minimum; the recorded machine runs it on the RTX 5060 Ti while the
4080 stays free.

All pinned versions, asset sizes, and hashes are in
[`../../image-gen/manifest.json`](../../image-gen/manifest.json). That file also
carries the exact `installationCommands` that were executed, which is the
authoritative sequence; the summary below is the readable version.

## Stack

| Component | Version |
|---|---|
| ComfyUI | 0.37.0, commit `73c9bad4d21e7addbe1d13bc92eee0f1431b017d` |
| ComfyUI-GGUF | commit `373048b8403a7820620065210a691263d4da0a61` |
| PyTorch | 2.13.0+cu130 from the `test/cu130` index |
| Python | 3.13 |

Clone ComfyUI without blobs, check out the pinned commit, do the same for the
GGUF node, create a Python 3.13 venv, install the CUDA build of torch from the
`cu130` test index, then install both requirements files. Exact commands:

```bash
git clone --filter=blob:none --no-checkout https://github.com/Comfy-Org/ComfyUI.git runtime/ComfyUI
git -C runtime/ComfyUI checkout --detach 73c9bad4d21e7addbe1d13bc92eee0f1431b017d
git clone --filter=blob:none --no-checkout https://github.com/leejet/ComfyUI-GGUF.git runtime/ComfyUI/custom_nodes/ComfyUI-GGUF
git -C runtime/ComfyUI/custom_nodes/ComfyUI-GGUF checkout --detach 373048b8403a7820620065210a691263d4da0a61
uv venv --python 3.13 .venv
uv pip install --python .venv/bin/python torch==2.13.0+cu130 torchvision torchaudio --index-url https://download.pytorch.org/whl/test/cu130
uv pip install --python .venv/bin/python -r runtime/ComfyUI/requirements.txt -r runtime/ComfyUI/custom_nodes/ComfyUI-GGUF/requirements.txt
```

## Weights

| Asset | File | Size |
|---|---|---:|
| Diffusion | `Sakura-Image-2.1-Turbo-Q4_K_M-3.77GiB.gguf` | 4,050,932,768 |
| Text encoder | `Sakura-TextEncoder-Qwen3VL-8B-Uncensored-bf16.safetensors` | 17,534,340,584 |
| VAE | `qwen_image_2.1_vae_bf16.safetensors` | 675,509,688 |

Download them from `webmp3/Sakura-Qwen-Image-2.1-Turbo-Uncensored-GGUF`, then check
each against the SHA-256 in the manifest. Run this from the directory that holds
`models/`, because the manifest records paths relative to it:

```bash
sha256sum -c --ignore-missing <(python3 -c "
import json
m = json.load(open('../../image-gen/manifest.json'))
for a in m['model']['assets']:
    print(a['sha256'] + '  ' + a['localPath'])
")
```

The manifest records a source revision that no longer resolves on the Hub (the
repository history was rewritten); the head is `accbcadb5d422f8cba0c44373b1229bfc9e7218b`
and the three files there still match the recorded sizes. Hashes are the check
that matters, not the revision pointer. If you install fresh, record the head you
actually used.

Place them exactly as the manifest's `localPath` values say:
`models/diffusion_models/`, `models/text_encoders/`, `models/vae/`.

## Sampling

The Turbo schedule is fixed, not discovered per prompt:

| Parameter | Value |
|---|---|
| Steps | 8 |
| CFG | 1.0 |
| Sampler | euler |
| Scheduler | manual, fixed sigmas |
| Sigmas | 1.0, 0.978453, 0.95418, 0.926626, 0.89508, 0.845148, 0.704534, 0.414568, 0.0 |

Load the workflow JSON from the upstream repository in the ComfyUI interface, or
drive the API at `http://127.0.0.1:8188`. The wrapper CLI used on the recorded
machine (`ai-mode image`) is local tooling and is not part of this recipe.

## Licence

The diffusion model and encoder are released under the Qwen Research License. Read
[the licence](https://huggingface.co/Qwen/Qwen-Image-2.1-Turbo) before use; the
recorded installation keeps the licence and notice files alongside the weights.
