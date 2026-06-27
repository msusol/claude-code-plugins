---
description: Manage Kaggle notebooks via the CLI (kaggle kernels push) with version-controlled metadata; never instruct manual Kaggle UI edits.
paths:
  - "**/notebook/**"
  - "**/kernel-metadata.json"
---

# Kaggle notebook workflow

All Kaggle notebook changes (code, metadata, kernel sources, dataset sources) are
managed via `kaggle kernels push` from the local machine. **Never instruct the user to
make changes manually in the Kaggle UI** — all configuration lives in version-controlled
metadata files.

## Notebook naming convention

Each competition phase or modelling method gets its own notebook and metadata file,
named after the version slug:

```
notebook/
  v0.1-tfidf-baseline.ipynb
  v0.1-tfidf-baseline-kernel-metadata.json
  v0.2-llama-qlora.ipynb
  v0.2-llama-qlora-kernel-metadata.json
```

- Slug format: `vX.Y-<short-method-description>` — matches the versioned plan name in
  `docs/plans/vX.Y-<slug>-plan.md`.
- Kernel title and `id` in the metadata file must also reflect the version
  (e.g. `gdataranger/llm-classification-finetuning-v01-tfidf`).
- Never reuse or overwrite a prior notebook; create a new file for each new method.
- Keep an investigation doc in `docs/investigate/` tracking run results, errors, and
  fixes for each notebook — one `##` section per slug.

## Push pattern

The CLI requires the metadata file to be named exactly `kernel-metadata.json`. Use
`scripts/push_notebook.sh <slug>` (if present in the project) or the manual pattern:

```zsh
STAGE="$(mktemp -d)"
cp notebook/<slug>.ipynb "$STAGE/"
cp notebook/<slug>-kernel-metadata.json "$STAGE/kernel-metadata.json"
kaggle kernels push -p "$STAGE"
```

## Metadata is the single source of truth

- `competition_sources`, `dataset_sources`, `model_sources` are declared in
  `kernel-metadata.json`, not added through the UI.
- `enable_internet: false` for any submission notebook (Code Competitions score offline).
- `enable_gpu: true` requests *a* GPU but does not guarantee a specific model.
- **Setting `machine_shape` in metadata:** Once a kernel's accelerator has been set to
  T4 via the Kaggle UI, add `"machine_shape": "NvidiaTeslaT4"` to `kernel-metadata.json`
  — subsequent `kaggle kernels push` calls will respect it and prevent reversion to P100.
  Workflow:
  1. Open the kernel in the Kaggle UI → Settings → Accelerator → select T4.
  2. Add `"machine_shape": "NvidiaTeslaT4"` to the local `kernel-metadata.json`.
  3. Push via CLI as normal — T4 is now locked for all future pushes.
- If a CLI push auto-starts on the wrong accelerator (P100 instead of T4), stop it
  immediately via the UI to avoid burning quota, then follow the workflow above.
- **`device_map` on multi-GPU instances:** `device_map='auto'` splits the model across
  both GPUs on T4×2 instances, causing TRL's `_chunked_cross_entropy_loss` to raise
  `RuntimeError: indices should be either on cpu or on the same device as the indexed
  tensor (cuda:1)`. Fix: use `device_map='cuda:0'` to pin the entire model to one GPU.
  For models that fit on a single T4 (≤ ~13 GB fp16), single-GPU is always preferred.
- **pip dependency warnings** (`dask-cuda`, `cuml-cu12`, `numba-cuda` conflicts) appear
  on every Kaggle kernel run and are harmless — they relate to RAPIDS packages unrelated
  to HuggingFace/PEFT/TRL. Ignore them.
- **PEFT `autocast_adapter_dtype` is GPU-dependent:**
  - On **P100 (sm_60)**: `get_peft_model()` raises `cudaErrorNoKernelImageForDevice`
    during the fp16→fp32 adapter cast. Workaround: `get_peft_model(model, lora_config,
    autocast_adapter_dtype=False)`. Side effect: LoRA adapters stay in fp16.
  - On **T4**: do NOT pass `autocast_adapter_dtype=False`. PEFT must upcast adapters
    to fp32 so that fp16 mixed-precision training (`fp16=True` in SFTConfig) can
    unscale gradients correctly. Passing `autocast_adapter_dtype=False` on T4 causes
    `ValueError: Attempting to unscale FP16 gradients` at the first gradient clip step.
  - **Rule:** remove all P100 workarounds (`autocast_adapter_dtype=False`,
    `enable_mem_efficient_sdp(False)`, `enable_flash_sdp(False)`) before running on T4.

## P100 vs T4 GPU — when to use each

Kaggle may assign either a P100 (Pascal, sm_60) or a T4 (Turing, sm_75) depending on
availability and what is selected in the UI. They are **not interchangeable** for LLM work:

### P100 (sm_60) — avoid for LLM fine-tuning

- PyTorch ≥ 2.4 dropped sm_60 CUDA kernel compilation. Basic tensor ops (`.ne()`,
  `.to()`) raise `cudaErrorNoKernelImageForDevice` at runtime.
- `bitsandbytes` 4-bit and 8-bit CUDA kernels (`ops.cu`) are not compiled for sm_60 —
  quantized loading crashes even on older PyTorch.
- PEFT's `autocast_adapter_dtype` (fp16→fp32 cast) also hits sm_60 CUDA errors.
- Flash attention and memory-efficient SDP are unsupported; must disable both:
  ```python
  torch.backends.cuda.enable_mem_efficient_sdp(False)
  torch.backends.cuda.enable_flash_sdp(False)
  ```
- **Use P100 only for:** CPU-style inference, TF-IDF/LightGBM, or notebooks that do
  not touch PyTorch CUDA ops at all.

### T4 (sm_75) — default choice for LLM fine-tuning

- Full PyTorch 2.4+ CUDA support; all tensor ops work.
- `bitsandbytes` 4-bit / 8-bit quantization works (enables loading larger models).
- PEFT LoRA adapter dtype casting works without workarounds.
- 16 GB VRAM (same as P100); T4×2 gives 32 GB for larger models.
- **Use T4 for:** any HuggingFace/PEFT/TRL training or inference notebook.

### Selecting T4 in practice

`enable_gpu: true` in `kernel-metadata.json` requests a GPU but does not guarantee T4.
To ensure T4:

1. Open the kernel in the Kaggle UI.
2. Under **Settings → Accelerator**, select **GPU T4 × 1** (or × 2).
3. The selection persists for subsequent UI-triggered runs; CLI-pushed runs may revert
   to Kaggle's default assignment.

If a CLI push lands on P100 and the notebook needs CUDA ops, stop the run immediately
(saves quota) and re-run via the UI with T4 selected.
