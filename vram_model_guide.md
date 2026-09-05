Here's the breakdown by model in your `.ini`, using each model's total parameter count and its quantization's bits-per-weight. **These are weight sizes only** — actual resident VRAM will run somewhat higher once KV cache and compute buffers are added, especially for the entries running `ctx-size = 16384` with `parallel = 2`. [huggingface](https://huggingface.co/unsloth/gemma-4-12b-it-GGUF)

## Chat / instruct models

| Model | Params | Quant | Weights (VRAM) | Notes |
|---|---|---|---|---|
| gemma-4-E4B-it-Q8_0 | ~8B (4.5B active MoE) | Q8_0 | ~8.5 GB | 4.5B *active*, but full 8B resident in VRAM  [huggingface](https://huggingface.co/unsloth/gemma-4-12b-it-GGUF) |
| gemma-4-E4B-it-uncensored-Q8_0 | ~8B | Q8_0 | ~8.5 GB | Same base architecture |
| gemma-4-12b-it-Q6_K | ~12B | Q6_K | ~9.9 GB | Near your 12GB ceiling alone |
| gemma-4-12b-it-Q4_0 | ~12B | Q4_0 | ~6.7 GB | Your VRAM-tight fallback |
| Gemma-4-12b-it-Abliterated-Q6_K | ~12B | Q6_K | ~9.9 GB | Same footprint as the Q6_K above |
| Qwen3.5-9B-Uncensored-Q8_0 | 9B | Q8_0 | ~9.6 GB |  [huggingface](https://huggingface.co/Qwen/Qwen3.5-9B-Base) |
| Huihui-Qwythos-9B-…-Q8_0 | ~9B | Q8_0 | ~9.6 GB | Estimated from "9B" naming |
| Huihui-Qwen3.6-27B-abliterated-Q2_K | ~27.8B | Q2_K | ~11.6 GB | Very aggressive quant just to fit 12GB  [apxml](https://apxml.com/models/qwen35-9b) |

## Translation, code, vision, OCR, embedding/reranking

| Model | Params | Quant | Weights (VRAM) |
|---|---|---|---|
| translategemma-4b-it.f16 | ~4.3B | F16 | ~8.6 GB |
| Qwen2.5-Coder-7B-Instruct-Q5_K_M | 7.6B | Q5_K_M | ~5.2 GB |
| Qwen3-Coder-30B-A3B-Instruct-Q2_K_XL | 30.5B total (3.3B active) | Q2_K | ~12.8 GB — **will not fit your 12GB card alongside anything else**  [huggingface](https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF) |
| MiniCPM-V-4_6-F16 | ~8.1B | F16 | ~16.2 GB — **exceeds your entire 12GB card** |
| Qwen3VL-8B-Instruct-Q4_K_M | 8B | Q4_K_M | ~4.85 GB |
| SmolVLM2-2.2B-Instruct-Q8_0 | 2.2B | Q8_0 | ~2.3 GB |
| LocateAnything-3B-Q4_K_M | 3B | Q4_K_M | ~1.8 GB |
| GLM-OCR-Q8_0 | ~1B (est.) | Q8_0 | ~1.1 GB |
| GLM-OCR-f16 | ~1B (est.) | F16 | ~2.0 GB |
| PaddleOCR-VL-1.6-GGUF | 0.9B | ~Q8_0 | ~1.0 GB  [huggingface](https://huggingface.co/cstr/paddleocr-vl-1.6-GGUF) |
| granite-embedding-311M-BF16 | 0.311B | BF16 | ~0.62 GB |
| Qwen3-Embedding-4B-Q6_K | 4B | Q6_K | ~3.3 GB |
| qwen3-reranker-0.6b-q8_0 | 0.6B | Q8_0 | ~0.64 GB |
| Qwen3-Reranker-4B-q5_k_m | 4B | Q5_K_M | ~2.75 GB |

## What this means for your Titan X (12GB)

Two entries are effectively unusable as configured: `MiniCPM-V-4_6-F16` (~16.2 GB, larger than your whole card) and `Qwen3-Coder-30B-A3B-Instruct-UD-Q2_K_XL` (~12.8 GB, leaves zero headroom for KV cache, mmproj, or your always-on embedder/reranker). If you actually route a request to either, expect an immediate OOM regardless of LRU eviction, since evicting everything else still can't create enough free VRAM .

For your steady-state "always-on" pair — `granite-embedding-311M` (~0.62 GB) plus `qwen3-reranker-0.6b` (~0.64 GB) — you're only committing about 1.3 GB, leaving roughly 10.7 GB for whichever chat/vision/code model gets swapped into the third slot. That comfortably fits everything except the two oversized entries above, though the 12B Q6_K models (~9.9 GB) and the 27B Q2_K model (~11.6 GB) leave very little slack for KV cache at higher context or concurrent `parallel = 2` requests.

**Caveat:** figures for `GLM-OCR` and the MiniCPM-V/Qwen3VL vision models don't include the separate `mmproj` vision-tower file size, which adds a few hundred MB to a couple GB on top of the numbers above, and none of these figures include KV cache/compute-buffer overhead, which scales with `ctx-size × parallel` and can add another 10–30% on the entries running 16384 context.