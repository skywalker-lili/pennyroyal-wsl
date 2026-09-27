# WSL preflight results

Date: 2026-09-23/24. Model services stopped at user request; GPU verified 0 MiB. No model loaded for these tests.
Image digest: sha256:76258532b1c01f7583fbe951f90b80903db931030291db9db4e5a68b28567866; release v2.5.1, source 2d6689abdac6f200091e9aa1ae65e95b86d9dd82. Driver596.72, PyTorch2.13.0+cu130.

| Test | Result |
|---|---|
| mmap + cudaHostRegister, torch copy 16MiB x20 | PASS; median roundtrip0.630ms |
| torch pin_memory, torch copy16MiB x20 | PASS; median0.681ms |
| generic Triton host pointer roundtrip, both allocators | PASS |
| Actual Pennyroyal transfer_mamba kernel, cudaHostRegister | FAIL CUDA illegal memory access |
| Actual transfer_mamba kernel, torch pin_memory | PASS 20rounds;512KiB median0.069ms |
| NIXL POSIX io_uring O_DIRECT4MiB WRITE | PASS4.50ms |
| New container/process NIXL READ, exact bytes comparison | PASS10.14ms |

Small-buffer times are diagnostics, not model benchmarks. Generic copies were insufficient to detect the real-kernel fault. NIXL logs include an intentional nonexistent-path capability probe; this is not a transfer failure. Containers used only the per-container seccomp=unconfined setting for NIXL, as in upstream recipe; host policy unchanged.

Every test had a host-enforced60s timeout plus bounded15s kill. Fedora timeout wrapper exited125 without testing; switched to direct Python entrypoint plus host timeout. Actual tests then ran.

Proceed only using isolated local allocator overlay inspired by PR8 with SGLANG_HICACHE_TORCH_PINNED_ALLOC=1; PR8 remains unmerged Draft. Default released CUDA allocator is NOT validated for this WSL machine. Full HiCache QSA/Mamba persistence correctness and write-through decode performance remain to be tested.

Logs: ../../logs/host-register.log, host-pinned.log, mamba-register.log, mamba-pinned.log, nixl-WRITE.log, nixl-READ.log. Scripts: ../../dev/preflight-*.py.

Weight reuse: old FP8PLE SHA256 fully verified b070f9644adf93794d8a1030584ab705809387e64396a9327a68fa3a3a6666b3. Restoring source files locally with original HF LFS SHA verification; no full weights downloaded.

Code audit: PR8 head b4d107b73f49371267a192a3abfc3ee49b7381f6 contains comments only, no allocator routing implementation. Local overlay explicitly adds the conditional CUDA allocator route; it is not a merged or complete upstream patch.
