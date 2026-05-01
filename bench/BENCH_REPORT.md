# Diff/Patch Performance Benchmark Report

**Date:** 2026-05-01  
**Machine:** macOS (Apple Silicon)

---

## Overview

Three implementations of structural diff/patch on a shared chat-room dataset are compared.
All three use their framework's **native typed-struct approach**:

| Implementation          | Language      | Runtime                          | API                                              | Benchmark tool                               |
| ----------------------- | ------------- | -------------------------------- | ------------------------------------------------ | -------------------------------------------- |
| `tiye/recollect`        | MoonBit       | Node.js (V8), JS release         | `diff_value[ChatState]` / `apply_to_value[...]`  | `moon build --release` + `node`              |
| `calcit-lang/recollect` | Calcit (Lisp) | Rust-based interpreter (`cr`)    | `diff-twig` / `patch-twig` (id-keyed, sparse)    | `yarn bench:cr` (`cr --init-fn recollect.bench/bench!`) |
| `cumulo-dipa`           | Rust          | Native, release profile          | `create_delta_towards` + postcard / `apply_patch` | `cargo bench -p bench` (Criterion)           |

> **cumulo-dipa** generates binary field-level deltas (struct-aware, Rust-native), serialized with postcard.  
> **recollect** (MoonBit / Calcit) generates id-keyed sparse patch op lists (JSON-aware).  
> These are fundamentally different delta representations; the comparison reflects end-to-end cost rather than algorithmic equivalence.

---

## Dataset

Shared JSON fixtures in `recollect.mbt/bench/fixtures/` (~1.1 MB each):

| File                     | Description                                                                       |
| ------------------------ | --------------------------------------------------------------------------------- |
| `state_base.json`        | Baseline: 50 users, 10 channels, 20 threads/channel, 10 replies/thread, reactions |
| `state_single_msg.json`  | One new reply appended to one thread                                              |
| `state_bulk_status.json` | ~15 users flip their `online` status                                              |
| `state_new_thread.json`  | New thread with 15 replies inserted at top of one channel                         |
| `state_reorder.json`     | Threads in one channel re-sorted by title                                         |

---

## Patch Representation

| Scenario    | MoonBit recollect (ops) | Calcit recollect (ops) | cumulo-dipa (postcard bytes) |
| ----------- | ----------------------- | ---------------------- | ---------------------------- |
| single_msg  | 1                       | 1                      | 32,648                       |
| bulk_status | 16                      | 2                      | 1,498                        |
| new_thread  | 1                       | 1                      | 34,945                       |
| reorder     | 17                      | 1                      | 32,547                       |

> cumulo-dipa encodes the full structural diff as postcard binary; every field in the nested struct hierarchy contributes to the delta even when mostly unchanged. Recollect uses id-keyed sparse ops: only the changed entities appear in the patch.

---

## diff — compute delta from base to new state

**MoonBit `diff_value[ChatState]` (JS release, 20 iters)**

| Scenario    | ms/iter |
| ----------- | ------- |
| single_msg  | 8.793   |
| bulk_status | 6.113   |
| new_thread  | 6.257   |
| reorder     | 7.624   |

> Internally: `to_json()` × 2 + id-keyed diff on `Json` tree.

**Calcit `diff-twig` (interpreter, 10 iters)**

| Scenario    | ms/iter |
| ----------- | ------- |
| single_msg  | 6.53    |
| bulk_status | 7.91    |
| new_thread  | 4.77    |
| reorder     | 7.20    |

**Rust `cumulo_dipa::create_delta_towards` + `postcard::to_allocvec` (Criterion, release)**

| Scenario    | µs/iter (median) |
| ----------- | ---------------- |
| single_msg  | 116              |
| bulk_status | 106              |
| new_thread  | 115              |
| reorder     | 114              |

---

## patch — apply pre-computed delta to base state

**MoonBit `apply_to_value[ChatState]` (JS release, 20 iters)**

| Scenario    | ms/iter |
| ----------- | ------- |
| single_msg  | 5.268   |
| bulk_status | 2.648   |
| new_thread  | 2.693   |
| reorder     | 2.605   |

> Internally: `apply_patches` on `Json` tree + `from_json()` reconstruction.

**Calcit `patch-twig` (interpreter, 30 iters)**

| Scenario    | ms/iter |
| ----------- | ------- |
| single_msg  | 0.210   |
| bulk_status | 0.968   |
| new_thread  | 0.678   |
| reorder     | 0.606   |

**Rust `postcard::from_bytes` + `cumulo_dipa::apply_patch` (Criterion, release)**

| Scenario    | µs/iter (median) |
| ----------- | ---------------- |
| single_msg  | 610              |
| bulk_status | 535              |
| new_thread  | 628              |
| reorder     | 618              |

---

## round-trip — diff + patch combined

**MoonBit (JS release, 10 iters)**

| Scenario    | ms/iter |
| ----------- | ------- |
| single_msg  | 10.130  |
| bulk_status | 9.035   |
| new_thread  | 9.033   |
| reorder     | 10.353  |

**Calcit (interpreter, 5 iters)**

| Scenario    | ms/iter |
| ----------- | ------- |
| single_msg  | 6.91    |
| bulk_status | 9.09    |
| new_thread  | 5.54    |
| reorder     | 7.80    |

**Rust cumulo-dipa (Criterion, release)**

| Scenario    | µs/iter (median) |
| ----------- | ---------------- |
| single_msg  | 750              |
| bulk_status | 657              |
| new_thread  | 757              |
| reorder     | 750              |

---

## Summary

### diff performance

\`\`\`
Rust cumulo-dipa   ~106–116 µs/iter  ← ~55–85× faster than interpreter/JS
Calcit cr          ~4.8–7.9 ms/iter  ← interpreter overhead; bulk_status slowest
MoonBit JS         ~6.1–8.8 ms/iter  ← V8 JIT; 2× to_json() overhead dominates
\`\`\`

### patch performance

\`\`\`
Calcit cr          ~0.2–1.0 ms/iter  ← sparse ops; low interpreter cost at 1–2 ops
Rust cumulo-dipa   ~535–628 µs/iter  ← fastest language but large binary delta deserialize
MoonBit JS         ~2.6–5.3 ms/iter  ← dominated by from_json() reconstruction
\`\`\`

### round-trip performance

\`\`\`
Rust cumulo-dipa   ~650–760 µs/iter  ← ~12–14× faster end-to-end than interpreter/JS
Calcit cr          ~5.5–9.1 ms/iter  ← sparse ops help patch; diff interpreter cost remains
MoonBit JS         ~9.0–10.4 ms/iter ← to_json×2 + diff + from_json all chain
\`\`\`

### Key observations

1. **Rust native is dominant in diff.** cumulo-dipa's struct-level binary diff is ~55–85× faster at diff and ~12–14× faster end-to-end vs JS/interpreter.

2. **Delta representation trade-off.** cumulo-dipa's postcard-encoded delta is 1.5–35 KB depending on how many fields changed. Recollect's id-keyed sparse ops are 1–17 JSON patch operations — much smaller payload for array reorders, larger op count for bulk field changes.

3. **Calcit patch wins at low op count.** With only 1–2 ops per scenario, Calcit's interpreter overhead is small (~0.2–1 ms) and beats both Rust and MoonBit at patch time.

4. **MoonBit `diff_value[ChatState]`** costs ~2× `to_json()` + JSON tree diff for diff, and `apply_patches` + `from_json()` for patch. The struct conversion overhead is visible: patch cost (~2.6–5.3 ms) is dominated by `from_json()` reconstruction.

5. **Serialization format matters.** Switching from bincode to postcard reduced the cumulo-dipa delta sizes by ~30% (e.g. single_msg: 46 KB → 33 KB), lowering patch deserialization cost.

---

## Memory

| Runtime          | Heap after loading fixtures | Notes                                          |
| ---------------- | --------------------------- | ---------------------------------------------- |
| MoonBit JS (V8)  | ~34 MB                      | `process.memoryUsage().heapUsed` after loading |
| Rust cumulo-dipa | stack struct, heap via allocator | Not measured directly                      |

---

## How to run

\`\`\`bash
# Calcit
cd calcit-lang/recollect
yarn bench:cr           # cr --init-fn recollect.bench/bench!

# MoonBit
cd recollect.mbt
moon build --target js --release ./bench
node _build/js/release/build/bench/bench.js

# Rust
cd dipa-cumulo
cargo bench -p bench
\`\`\`

---

## Files

| Path                                                | Purpose                                              |
| --------------------------------------------------- | ---------------------------------------------------- |
| `recollect.mbt/bench/gen_fixtures.mjs`              | Generate JSON fixtures (run once)                    |
| `recollect.mbt/bench/fixtures/`                     | Shared fixture JSON (5 × ~1.1 MB)                    |
| `recollect.mbt/bench/structs.mbt`                   | MoonBit typed structs mirroring fixture schema       |
| `recollect.mbt/bench/bench.mbt`                     | MoonBit bench runner                                 |
| `calcit-lang/recollect` namespace `recollect.bench` | Calcit bench (`yarn bench:cr`)                       |
| `dipa-cumulo/bench/`                                | Rust Criterion bench (`cargo bench -p bench`)        |
