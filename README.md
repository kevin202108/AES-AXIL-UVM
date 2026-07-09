# AES-128 AXI4-Lite — UVM Verification

A byte-serial **AES-128** core wrapped in a standard **AXI4-Lite** register
interface, verified with a complete **UVM (SystemVerilog)** environment:
independent reference model, functional + FSM + code coverage, SVA protocol
assertions, fault injection, and a one-command regression.

> Built and verified on EDA Playground (Xcelium) and ported with **zero source
> changes** to a Synopsys VCS + UVM-1.2 flow for code-coverage sign-off.

---

## Highlights

- **AXI4-Lite slave wrapper + completion FSM** around a byte-serial AES
  core. Completion is tracked directly via the core's `done` and `ciphertext_valid`
  outputs, with SLVERR for out-of-range access.
- **Independent oracle**: a table-based AES-128 golden model (separate from the
  core's composite-field implementation) checks every ciphertext.
- **18 UVM tests**: directed (FIPS-197), constrained-random (vs golden),
  **259 NIST AESAVS known-answer vectors**, full WSTRB byte-enable sweep,
  AXI backpressure, AW/W stagger, back-to-back, reset-in-the-middle, exhaustive
  reset sweep, X-injection, and an error-response/protocol test.
- **Coverage**: functional, FSM, and SVA assertion coverage **100%**; DUT line
  99% / branch 95% (full code-coverage sign-off with documented waivers).
- **Proven checkers**: fault injection demonstrates the scoreboard catches both
  read-path and write-path bugs (a checker that never fails is worthless).
- **One-command regression** + clean `rtl / tb / sim / doc` layout, one class
  per file.

## Results (summary)

| Metric | Value |
|--------|-------|
| Tests passing | **18 / 18** (UVM_ERROR = 0) |
| Random vectors vs golden | 2000 blocks, 0 mismatches |
| NIST AESAVS KAT | 259 / 259 |
| Functional / FSM / Assert coverage | 100% |
| DUT line / branch coverage | 99.19% / 95.16% |

Full sign-off detail and coverage waivers: [`doc/VERIFICATION.md`](doc/VERIFICATION.md).

## Architecture

```
            AXI4-Lite                aes_axi_lite (DUT)
  master  ───────────►  ┌── AXI4-Lite slave ─┐   ┌── completion FSM ──┐
  (UVM driver/BFM)      │  KEY/PT/CTRL/      │──►│ FEED→WAIT→CAP→DONE │
                        │  STATUS/CIPHERTEXT │   │  (done, ct_valid)  │
                        └────────────────────┘   └────────┬───────────┘
                                                          ▼
                                                   AES-128 byte-serial core
```

## Register map

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00–0x0C | KEY0–3 | RW | 128-bit key (KEY3 = MS word) |
| 0x10–0x1C | PT0–3 | RW | 128-bit plaintext |
| 0x20 | CTRL | RW | bit0 = start |
| 0x24 | STATUS | RO | bit0 = done, bit1 = busy |
| 0x30–0x3C | CT0–3 | RO | 128-bit ciphertext |
| out of range | — | — | responds SLVERR |

## How to run

This is a **UVM-1.2** testbench, so it needs a UVM-capable simulator.

**Free, in browser — [EDA Playground](https://www.edaplayground.com/):**
paste `rtl/` into the Design pane and `tb/` into the Testbench pane, pick VCS
or Xcelium, add `+UVM_TESTNAME=axil_aes_test`, Run. See
[`doc/VERIFICATION.md`](doc/VERIFICATION.md) for details on files, tests, and options.

**Local / commercial simulator** (VCS / Xcelium / Questa) using the file list:

```sh
# compile once (whole project is pulled in via `include)
<sim> -sverilog -ntb_opts uvm-1.2 -f sim/filelist.f
# run any test
./simv +UVM_TESTNAME=axil_aes_test
```

A one-command regression + coverage script for VCS is in `sim/run_vcs.sh`.

> The EDA simulators themselves are **not** part of this repo — supply your own.

## Project structure

```
rtl/   design.sv (wrapper)         aes_rtl.sv (AES core)
tb/    testbench.sv, axil_*.svh (one class per file), aes_ref_model.svh,
       kat_*.dat (NIST AESAVS vectors)
sim/   filelist.f, run scripts
doc/   VERIFICATION.md (unified run guide and reports)
```

## What this demonstrates

UVM environment architecture · constrained-random + functional/FSM/code
coverage closure · independent reference modelling · SVA protocol checking ·
AXI4-Lite protocol · coverage-driven verification and waiver justification ·
simulator-portable, vendor-agnostic flow.

## License & attribution

The original RTL implementation of the AES-128 core was developed by [jeffyang0930](https://github.com/jeffyang0930).

This project is licensed under the MIT License — see the [`LICENSE`](LICENSE) file for details. The AES composite-field S-box architecture follows X. Zhang & K. Parhi, *"High-Speed VLSI Architectures for the AES Algorithm."* Test vectors follow the public NIST FIPS-197 / AESAVS structure.
