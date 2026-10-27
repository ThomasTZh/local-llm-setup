# Replicate this setup

A working text and vision inference endpoint on two 16 GB GPUs, plus an optional
private search stack and an optional image generator. Steps 0 to 4 are the core
and take about an hour of wall time, most of it build and download. Steps 5 and 6
are independent additions.

Every path below assumes the recipe lives in `$AI_HOME`, default
`~/local-llm-setup`. Set `AI_HOME` to somewhere else and export it; every script
reads it.

```bash
export AI_HOME="$HOME/local-llm-setup"
```

## What you need

| Item | Minimum | Recorded machine |
|---|---|---|
| GPU | Two NVIDIA cards, 30 GB combined, compute 8.9 and 12.0 | RTX 4080 16 GB + RTX 5060 Ti 16 GB |
| Driver | A driver new enough for both cards | 595.104.02, open module |
| CUDA toolkit | 13.x with `nvcc` | 13.2 |
| Memory | 32 GB | 31 GiB |
| Disk | 40 GB for text, 80 GB with image generation | |
| Tools | `cmake`, `g++`, `git`, `python3`, `curl`, `hf` CLI | |

The catalogue is sized for 30 GB of VRAM. One 24 GB card would run the 15.2 GiB
text model at a shorter context; one 16 GB card would not.

## Step 0: check the machine

```bash
bash setup/preflight.sh
```

Prints one line per requirement and exits non-zero if something is missing. It
does not change anything.

## Step 1: build the engine

```bash
bash setup/build-llama.sh
```

Clones llama.cpp, checks out the pinned commit, builds with CUDA and Flash
Attention for both architectures, and prints the version. Expect the build to be
the longest single step; it is CPU-bound and uses all cores. The result is
`$AI_HOME/build/bin/llama-server` plus shared libraries in the same directory.

## Step 2: fetch the models

```bash
bash setup/download-models.sh
```

About 34 GB: the Swift 1.5 Qwen3.8-27B Q4_K_S weights, its F16 projector, the
Gemma-4-31B QAT Q4_0 weights, and Google's canonical Gemma chat template. Ends by
verifying all four SHA-256 values, so a truncated or corrupted download fails
here rather than at load time.

## Step 3: render the router config and start it

```bash
bash setup/router/install-router.sh
bash setup/router/start-router.sh
```

`install-router.sh` writes `$AI_HOME/runtime/models.ini` from the template,
substituting your `AI_HOME` for the placeholder paths, and fails if any model
file it references is missing. `start-router.sh` runs:

```bash
CUDA_DEVICE_ORDER=PCI_BUS_ID GGML_CUDA_DISABLE_GRAPHS=1 LLAMA_CACHE=... \
  llama-server --models-preset runtime/models.ini --models-max 1 \
               --host 127.0.0.1 --port 8080
```

Nothing is loaded yet. In another terminal:

```bash
curl -s http://127.0.0.1:8080/v1/models | python3 -m json.tool | grep '"id"'
```

Expect three ids and no process holding VRAM. The first request loads a model and
takes roughly half a minute; switching models unloads the previous one.

To run it as a user service:

```bash
mkdir -p ~/.config/systemd/user
install -m 644 setup/router/local-ai-router.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now local-ai-router.service
loginctl enable-linger "$USER"     # keep it running after logout
```

The unit assumes `~/local-llm-setup`; edit the two paths if you installed
elsewhere.

## Step 4: verify

```bash
bash setup/verify.sh          # endpoints, catalogue, hashes
bash setup/verify.sh --load   # also generates a short reply
```

The `--load` run is the one that proves the GPUs actually work: it triggers a
model load and asks for a few tokens.

## Step 5: private search and crawl (optional)

```bash
bash setup/web-stack/install-web-stack.sh
```

Needs rootless Podman. Generates a SearXNG secret and a Crawl4AI API token,
pulls both images, installs two user services, and waits until both answer. It
prints the API token at the end.

Images are pinned by tag here, not by digest. The recorded machine pins digests;
if you want the same immutability, run `podman images --digests` after the first
pull and replace the tags in the two unit files with `@sha256:...` references.

## Step 6: image generation (optional)

See [`image-gen/README.md`](image-gen/README.md). Separate ComfyUI installation,
separate GPU, about 40 GB of weights. Not needed for text inference.

## Step 7: clients

See [`clients/README.md`](clients/README.md). The short version: point any
OpenAI-compatible client at `http://127.0.0.1:8080/v1` and use the model ids from
`GET /v1/models`.

## Adapting to different hardware

The numbers in the server config encode this machine's two cards. Change them,
not the architecture:

- `tensor-split` in `models.ini` is the share of layers per GPU. 28:36 gives the
  4080 slightly more, matching its slightly faster memory. Scale the pair to your
  VRAM ratio; the split does not have to sum to a fixed number.
- `--device CUDA0,CUDA1` plus `CUDA_DEVICE_ORDER=PCI_BUS_ID` fixes which card is
  CUDA0. Confirm with
  `nvidia-smi --query-gpu=index,uuid,pci.bus_id,name --format=csv`. If your
  faster card is not on the lower bus number, set `AI_GPU_UUIDS` to the two UUIDs
  in the order you want.
- `ctx-size` is the context that fits. With less VRAM, lower it. `cache-type-k`
  q8_0 and `cache-type-v` q5_1 are the compression that makes 217,088 tokens fit
  on 30 GB; dropping to q8_0/q8_0 costs VRAM, and raising toward f16 costs a lot.
- `threads` 7 and `threads-batch` 8 suit 10 cores with hyperthreading. Keep
  generation threads at or below physical core count.
- `mmproj-device = CUDA1` keeps the vision projector on the second card, which is
  where it fits alongside its share of the weights.

## What was tested, and what was not

Executed on the recorded machine: this exact llama.cpp commit and build flags, the
router started from the published preset, the three models listed and served,
hash verification of all four downloads, and the search and crawl services.

Executed as part of preparing this recipe: the router preset was started from a
plain command line with no local tooling, and returned three model ids; every
script passes a shell syntax check; the ini rendering was run.

Not executed: a full clean-machine run of these scripts, the Podman install path
(no container runtime in the environment used to write this), a GPU load test in
that environment, and the ComfyUI installation. Steps that could not be run here
are marked in the verification record at
[`../verification/snapshot-2026-10-27.md`](../verification/snapshot-2026-10-27.md).
