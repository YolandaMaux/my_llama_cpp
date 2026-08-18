# Standalone llama.cpp router

Git-ready llama.cpp HTTP router with **CPU-only**, **standard NVIDIA GPU**, and **Titan X Maxwell (SM 5.2)** modes. Model files remain outside the repository and are mounted read-only at `/models`.

## File layout

| File | Role | Commit to Git? |
|---|---|---|
| `llamacpp_compose.yml` | Shared service configuration | Yes |
| `llamacpp_compose.standard-gpu.yml` | Official CUDA-image NVIDIA overlay | Yes |
| `llamacpp_compose.titanx.yml` | SM 5.2 source-build NVIDIA overlay | Yes |
| `llamacpp_Dockerfile.cpu` | CPU image definition | Yes |
| `llamacpp_Dockerfile.titanx` | CUDA/SM 5.2 build definition | Yes |
| `llamacpp_models.ini` | Router model IDs and GGUF paths | Yes, if paths are non-secret |
| `llamacpp.env` | Local machine configuration | **No** |
| `llamacpp.secrets.env` | Optional credentials/tokens | **No** |
| `llamacpp_start.sh` | Starts and manages the project | Yes |

## Why two env files?

`llamacpp.env` holds non-secret, host-specific values such as `MODELS_DIR`, port, GPU layers, and image tags. It is ignored because an absolute local path is not portable, although it has no credential by default. `llamacpp.secrets.env` is reserved for actual credentials if you later add a private registry, authenticated proxy, or telemetry integration. llama.cpp itself does not require a secret file.

Neither file is supplied to Compose using Compose's default `.env` convention. Instead, `llamacpp_start.sh` explicitly loads `llamacpp.env`, then optionally `llamacpp.secrets.env`, and exports the variables before calling `podman compose`. This avoids accidental conflict with unrelated project `.env` files.

## Prerequisites

- Podman and a working `podman compose` provider.
- `curl` for the optional helper commands.
- A local directory containing the GGUF and `mmproj` files named in `llamacpp_models.ini`.
- For `gpu` or `titanx`, a working NVIDIA driver and NVIDIA Container Toolkit/CDI configuration for Podman.

Check the GPU host first:

```bash
nvidia-smi
podman info
```

## Installation

```bash
unzip llamacpp-router-final.zip
cd llamacpp-router-final
cp llamacpp.env.example llamacpp.env
cp llamacpp.secrets.env.example llamacpp.secrets.env
chmod 600 llamacpp.env llamacpp.secrets.env
chmod +x llamacpp_start.sh
```

Edit `llamacpp.env` and set the absolute directory containing models:

```dotenv
MODELS_DIR=/home/riaz/LLM_models/Models_GGUF/models
```

Remove any model section in `llamacpp_models.ini` for files you do not own. API requests must use the exact INI section name in their `model` field.

Validate configuration before startup:

```bash
./llamacpp_start.sh validate
```

## CPU-only

Set:

```dotenv
LLAMA_ARG_N_GPU_LAYERS=0
```

Start:

```bash
./llamacpp_start.sh cpu
```

## Standard NVIDIA GPU

Set, for example:

```dotenv
LLAMA_ARG_N_GPU_LAYERS=99
LLAMACPP_STANDARD_GPU_IMAGE=ghcr.io/ggml-org/llama.cpp:server-cuda
```

Run:

```bash
./llamacpp_start.sh gpu
```

This mode uses the official CUDA server image and NVIDIA device reservation overlay. The image is pulled if missing; it is not locally compiled.

## Titan X / Maxwell SM 5.2

The Titan-X build compiles llama.cpp from source with `GGML_CUDA=ON` and `CMAKE_CUDA_ARCHITECTURES=52`. It may take minutes on the first build.

Set:

```dotenv
LLAMA_ARG_N_GPU_LAYERS=99
CUDA_IMAGE_TAG=12.4.1
```

Run:

```bash
./llamacpp_start.sh titanx
```

Use a CUDA image version compatible with your installed NVIDIA driver. Test a small model before production use.

## Verify and operate

```bash
./llamacpp_start.sh status
./llamacpp_start.sh health
./llamacpp_start.sh models
./llamacpp_start.sh logs
./llamacpp_start.sh down
```

The API listens at `http://127.0.0.1:8080`. Example request:

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"gemma-4-E4B-it-Q8_0","messages":[{"role":"user","content":"Reply with one sentence."}]}'
```

## Git initialization

```bash
git init
git add .gitignore llamacpp.env.example llamacpp.secrets.env.example \
  llamacpp_compose.yml llamacpp_compose.standard-gpu.yml \
  llamacpp_compose.titanx.yml llamacpp_Dockerfile.cpu \
  llamacpp_Dockerfile.titanx llamacpp_models.ini llamacpp_start.sh README.md
git commit -m 'Initial standalone llama.cpp router'
```

Never add `llamacpp.env`, `llamacpp.secrets.env`, GGUF files, or the host model directory. If a real credential is ever committed, rotate it immediately; removing it in a later commit does not remove it from Git history.

For production, do not expose port 8080 publicly; bind to a trusted interface or use a TLS/authenticated reverse proxy.
