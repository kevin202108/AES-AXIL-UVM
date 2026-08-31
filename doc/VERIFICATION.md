# Verification & Run Guide — AES-128 AXI4-Lite UVM Environment

## 1. Executive Summary & Results

The byte-serial AES-128 core is wrapped in a standard AXI4-Lite register interface and verified with a complete UVM environment. Verification covers functional correctness, registers and byte-enables, AXI4-Lite protocol compliance, and boundary/exception behaviour (reset, back-to-back, backpressure, error response, X-injection). An **independent table-based AES reference model** serves as the primary oracle, cross-checked against the **NIST AESAVS** known-answer vectors (KAT) and constrained-random stimulus. A second, independent oracle — an AES-128 **C reference model** imported through **SystemVerilog DPI-C** — cross-checks every random block against the SV golden model before the DUT is compared (dual-oracle verification, §2.4).

### Key Results
- **Functional:** FIPS-197 directed + constrained-random (dual-oracle: SV + C via DPI-C) + **259 NIST AESAVS known-answer vectors**, all passing.
- **DPI-C:** an independent AES-128 C golden model, imported via SystemVerilog DPI-C, agrees with the SV golden model on every random block; the DUT is only checked once the two oracles agree.
- **Coverage:** functional, FSM, and SVA assertion coverage **100%**; DUT line/branch coverage 99%/95% (code-coverage sign-off with documented waivers).
- **Checker confidence:** fault injection proves the scoreboard catches both read-path and write-path bugs.
- **Automation:** a single command runs the full regression and produces a pass/fail summary and merged coverage.

| Metric | Overall | DUT wrapper `aes_axi_lite` |
|--------|---------|----------------------------|
| Functional (covergroup) | **100%** | — |
| Assertion (SVA) | **100%** | 100% |
| FSM state/transition | **100%** | 100% |
| Line | 92.83% | **99.19%** |
| Branch | 88.35% | 95.16% |
| Toggle | 94.41% | 89.43% |
| Condition | 50.22% | 71.43% |

---

## 2. Design & Verification Architecture

### 2.1 AES Core & AXI4-Lite Wrapper

The `aes_axi_lite` module provides an AXI4-Lite slave register file and drives the byte-serial AES-128 core via an internal completion FSM. The wrapper tracks encryption completion using the `done` and `ciphertext_valid` signals exposed by the core, eliminating the need for a mirror LFSR controller.

**Verified timing behaviour:** The core is a continuous pipeline. The FSM feeds 16 bytes during `S_FEED`, waits for the core to assert `ciphertext_valid` in `S_WAIT`, captures the 16 bytes in `S_CAP` as they are validated, and moves to `S_DONE` when the core asserts `done`.

```
  S_IDLE ──(CTRL.start)──► S_FEED ──► S_WAIT ──► S_CAP ──► S_DONE ──► S_IDLE
  hold core in reset      feed 16B   wait valid  grab 16B  set done   park core
```

### 2.2 Register Map

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00–0x0C | KEY0–3 | RW | cipher_key[31:0] … [127:96] (KEY3 = MS word) |
| 0x10–0x1C | PT0–3 | RW | plaintext[31:0] … [127:96] (PT3 = MS word) |
| 0x20 | CTRL | RW | bit0 = start (ignored while busy) |
| 0x24 | STATUS | RO | bit0 = done, bit1 = busy |
| 0x30–0x3C | CT0–3 | RO | ciphertext[31:0] … [127:96] (CT3 = MS word) |
| other / addr[7:6]≠0 | — | — | unmapped → SLVERR |

*Note: For each 128-bit value, byte index 0 is the most significant byte (MSB).*

### 2.3 Verification Environment Architecture

```
top  (clock / reset via uvm_event / FSM covergroup)
    ┌── axil_env ────┐        ┌─ axil_if ─┐        ┌─ aes_axi_lite (DUT) ─┐
    │ ┌ axil_agent ┐ │        │ AXI4-Lite │        │  AXI slave + FSM     │
    │ │ sequencer  │ │◄──────►│ + SVA     │◄──────►│  + core done/valid   │
    │ │ driver(BFM)│ │        │ + covers  │        │  + AES-128 core      │
    │ │ monitor    │ │        └───────────┘        └──────────────────────┘
    │ └─────┬──────┘ │ 
    │  ┌────┴─────┐  │
    │  │scoreboard│  │ ◄── register model + independent AES golden model
    │  │coverage  │  │
    │  └──────────┘  │
    └────────────────┘
```

The UVM verification environment is built with a modular, one-class-per-file architecture. An independent textbook golden model `aes_ref_model` is used as an oracle to check the ciphertexts.

### 2.4 Dual-Oracle Verification (SV + C via DPI-C)

A second, language-independent AES-128 **C golden model** lives in `c_model/aes128.c` and is imported into the testbench through **SystemVerilog DPI-C** (`tb/aes_dpi.svh` declares `import "DPI-C" function void aes128_encrypt(...)` and wraps it as `dpi_encrypt128`, matching the 128-bit layout `aes_ref_model` already uses). It does not share code with `aes_ref_model` or with the DUT's composite-field datapath — it is a straightforward table-based implementation, written independently of the SV golden model.

```
  axil_dpi_seq / axil_rand_seq
       │
       ├─► import "DPI-C" aes128_encrypt / aes128_selfcheck
       │         │
       │         ▼
       │    c_model/aes128.c   (table-based AES-128, C)
       │
       ├─► aes_ref_model::encrypt128   (table-based AES-128, SV)
       │
       └─► DUT via AXI4-Lite
```

For every stimulus block, the sequence asks both oracles for the expected ciphertext before it drives the DUT:

1. `aes_ref_model::encrypt128(key, pt)` (SV) and `dpi_encrypt128(key, pt)` (C, via DPI-C) are computed.
2. If the two disagree, that is logged as a dual-oracle mismatch and the block is **not** driven onto the DUT — an oracle disagreement means the reference itself is unreliable for that input, so comparing the DUT against either one would not be meaningful.
3. Once the oracles agree, the DUT is driven and its ciphertext is checked against the agreed expected value.

`axil_dpi_test` runs this sequence once, plus a self-check of the C model against a hard-coded FIPS-197 vector, as a minimum smoke test for the DPI-C link. `axil_rand_test` runs it at scale (`+NUM_BLOCKS=<n>`, 2000 blocks in the full regression). Byte order matches the rest of the environment: for a 128-bit value, byte index 0 is the most significant byte, consistent with the `KEY3` / `PT3` / `CT3` register-map convention (§2.2).

---

## 3. Testbench Components & File List

| File | Contents |
|------|----------|
| `design.sv` | `aes_axi_lite` wrapper (AXI4-Lite + completion FSM); `` `include "aes_rtl.sv" `` |
| `aes_rtl.sv` | AES-128 core (AES_Core / AES_KeyExpand / AES_LFSR_Controler / AES_Sbox) |
| `testbench.sv` | Top: `` `include `` interface + package, `module top`, FSM covergroup |
| `axil_if.svh` | AXI4-Lite interface + SVA assertions + cover properties |
| `axil_pkg.svh` | Package; `` `include `` the components below in order |
| `axil_item.svh` | Transaction (+ sequencer typedef) |
| `axil_driver.svh` | AXI4-Lite master BFM (reset-aware; backpressure & AW/W stagger knobs) |
| `axil_monitor.svh` | Passive bus monitor |
| `axil_agent.svh` | Driver + monitor + sequencer |
| `axil_scoreboard.svh` | Register model + byte-enable + read-back checker |
| `axil_coverage.svh` | Functional covergroup |
| `axil_env.svh` | Agent + scoreboard + coverage |
| `aes_ref_model.svh` | Independent table-based AES-128 golden model (SV) |
| `aes_dpi.svh` | `import "DPI-C"` declarations + `dpi_encrypt128` wrapper |
| `axil_sequences.svh` | Base / smoke / aes / dpi / rand / wstrb / full / b2b / kat / xinj / … |
| `axil_tests.svh` | The 19 tests (includes `axil_dpi_test`) |
| `kat_key.dat`, `kat_pt.dat`, `kat_ct.dat` | NIST AESAVS known-answer vectors |

**C reference model (`c_model/`)**

| File | Contents |
|------|----------|
| `aes128.c` / `aes128.h` | Independent AES-128 golden model (C), DPI-C target |
| `aes128_selftest.c` | Standalone `gcc` self-check (no simulator needed) |
| `aes128_kat_check.c` | Standalone `gcc` check of all 259 NIST AESAVS vectors |

---

## 4. Run Guide & Test Library

### 4.1 Running with a Local Simulator
To compile the project (compile roots are `design.sv` and `testbench.sv`; the DPI-C golden model is linked alongside them):
```sh
# Compile once (whole project pulled in via `include + +incdir; link the C golden model)
<sim_command> -sverilog -ntb_opts uvm-1.2 -f sim/filelist.f c_model/aes128.c
```
To run a specific test:
```sh
# Run any test (no recompile needed)
./simv +UVM_TESTNAME=axil_dpi_test
./simv +UVM_TESTNAME=axil_kat_test
```
A one-command regression + merged coverage script is provided in `sim/run_vcs.sh`, which already links `c_model/aes128.c` and includes `axil_dpi_test` in its test list:
```sh
bash sim/run_vcs.sh
```

### 4.2 Running on EDA Playground (Free, in browser)
1. Add each `rtl/` and `tb/` file (and the three `.dat` files) using the **+** button.
2. Select a UVM-capable simulator (e.g., VCS or Xcelium).
3. Set compile roots to `design.sv` and `testbench.sv`.
4. In **Run options**, specify: `+UVM_TESTNAME=axil_aes_test`.
5. Run.

This covers every test except the DPI-C ones, since EDA Playground never puts
Design-pane `.c` files on the simulator command line by itself — see §4.3.

### 4.3 Running DPI-C Co-Simulation on EDA Playground

EDA Playground's default invocation is effectively `vcs ... design.sv
testbench.sv && ./simv +UVM_TESTNAME=...`. Extra Design-pane files are pulled
in via `` `include ``, but a `.c` file is never `` `include ``d, so
`c_model/aes128.c` is invisible to the simulator unless it is placed on the
compile line explicitly. Without that, `axil_dpi_test` and the DPI-C part of
`axil_rand_test` fail to elaborate with:
```text
Error-[DPI-DIFNF] DPI import function not found
  The definition of DPI import function/task 'aes128_selfcheck' does not exist.
```

**Recommended path — `sim/run.bash`:**
1. Add a Design-pane tab named exactly `aes128.c`, containing `c_model/aes128.c` (bare name, no `c_model/` prefix; the file is self-contained, so `aes128.h` is not needed on Playground).
2. Add every `tb/` file, including `aes_dpi.svh`.
3. Enable **Use run.bash shell script** and add `sim/run.bash` as a tab named `run.bash`.
4. Select VCS or Xcelium with UVM enabled, then Run.

`run.bash` detects the selected simulator, always puts `aes128.c` on the
compile/elaborate command line, and runs a budget-conscious regression:
`axil_dpi_test` and `axil_rand_test` at `+NUM_BLOCKS=20`. The heavier jobs —
259-vector KAT, an exhaustive reset sweep, X-injection, and a 100-block dual
oracle random run — are in `sim/run_stress.bash` (same setup, pasted as a
second `run.bash` job) to stay inside Playground's execution budget; the full
2000-block dual-oracle regression runs through `sim/run_vcs.sh` (§4.1) instead.

**Fallback — Compile Options (no `run.bash`):** if a shell script is not an
option, leave "Use run.bash" off and put `aes128.c` directly in the
**Compile Options** field, then set **Run options** yourself
(e.g. `+UVM_TESTNAME=axil_dpi_test`). This is not the primary path because a
missing or misspelled entry silently reproduces the `DPI-DIFNF` error above.

**If it fails:**

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Error-[DPI-DIFNF]`, `aes128_selfcheck` not found | `aes128.c` not on the compile line | Use `run.bash`, or add `aes128.c` to Compile Options |
| Default `vcs ... design.sv testbench.sv` runs instead of the script | "Use run.bash" is off, or the tab is not named `run.bash` | Enable the option; name the tab exactly `run.bash` |
| `Error-[EXCF]`, `cmp: No such file or directory` on VCS | Playground's VCS sandbox has no `cmp` binary, which VCS needs for incremental recompiles | `run.bash` installs a minimal `cmp` stub on `PATH` automatically; if it still occurs locally, install `cmp` or use `sim/run_vcs.sh` |
| `import "DPI-C"` errors | Selected simulator/language mode does not support DPI-C | Use VCS or Xcelium with SystemVerilog |
| Package cannot find `aes_dpi.svh` | Testbench tab missing | Add `aes_dpi.svh` (`tb/axil_pkg.svh` includes it) |

### 4.4 Code Coverage Collection
To collect coverage locally:
```sh
<sim_command> -sverilog -ntb_opts uvm-1.2 -f sim/filelist.f -cm line+cond+fsm+tgl+branch
./simv +UVM_TESTNAME=axil_full_test -cm line+cond+fsm+tgl+branch -cm_name full
urg -dir simv.vdb -report urgReport      # open urgReport/dashboard.html
```

### 4.5 Debug Options
* **FSM/Ciphertext Trace**: Add `+define+AES_DEBUG` to compile options.
* **Fault Injection**: Add `+define+SIM_FAULT_INJECT +FAULT=1` (or `2`) with `axil_smoke_test`.

### 4.6 Test Library Summary

| Test | Objective / Behavior |
|------|----------------------|
| `axil_smoke_test` | Register read/write/read-back (default) |
| `axil_aes_test` | FIPS-197 directed encryption |
| `axil_dpi_test` | DPI-C link minimum: C self-check, C vs FIPS-197, C vs SV golden model, DUT vs C |
| `axil_rand_test` | Random key/pt, dual oracle (SV + C via DPI-C) vs DUT (`+NUM_BLOCKS=<n>`, default 100) |
| `axil_kat_test` | 259 NIST AESAVS known-answer vectors |
| `axil_full_test` | Coverage-closure (all reachable bins, → 100%) |
| `axil_wstrb_test` / `axil_wstrb_sweep_test` | Byte-enable; all 16 strobes |
| `axil_err_test` | Unmapped/out-of-range → SLVERR; RO write ignored |
| `axil_busy_test` | Start-while-busy is ignored |
| `axil_bp_test` | AXI backpressure |
| `axil_stagger_test` | AW/W channel stagger |
| `axil_b2b_test` | Back-to-back, key persistence |
| `axil_reset_test` / `..._sweep` / `..._hs` / `..._exhaustive_test` | Reset corners |
| `axil_xinj_test` | X-injection on non-strobed bytes |

---

## 5. Code Coverage Closure & Waivers

### 5.1 Closed by Stimulus (Reachable Gaps)
* **AXI write-handshake conditions:** Expression `(~axi_awready && AWVALID && WVALID && aw_en)` had uncovered operand-independence rows because the master BFM asserted AWVALID and WVALID together.
* **Solution:** Added `axil_stagger_test` which staggers AW and W channels in random order with a random gap, improving wrapper condition coverage from 64.84% to 71.43%.

### 5.2 Excluded/Waived Items (Unreachable / Not-Applicable)

* **W1 — AES-core internal condition coverage:**
  * **Scope:** `Inverse_GF2tp2tp2`, `AES_Core`, and other GF sub-modules.
  * **Justification:** These represent the AES composite-field combinational datapath (XOR / AND-reduction logic). Their functional correctness is exhaustively verified (259 NIST KAT + 2000 random vectors vs independent golden model). Sub-condition independence of pure combinational logic is not a meaningful metric here.
* **W2 — Unreachable FSM default branch:**
  * **Scope:** `default: state <= S_IDLE;` safety branch in wrapper FSM.
  * **Justification:** FSM state encoding only uses 0–4; 5–7 are unreachable. Waveform trace confirms it is unreachable.
* **W3 — Unreachable AXI handshake operand combinations:**
  * **Scope:** Operand combinations involving `aw_en` or mutually-exclusive signals.
  * **Justification:** These cannot toggle independently under the master's protocol-compliant flow.

---

## 6. Phase-by-Phase Verification History

### Phase 1 — Register UVM Environment & Checker Confidence
* **Goal:** Verify standard register access and prove that UVM checkers flag bugs.
* **Results:**
  * `axil_smoke_test` passed without mismatches.
  * Injected `FAULT=1` (read-mux aliases KEY1→KEY0) and `FAULT=2` (KEY2 ignores writes); both were caught precisely by the scoreboard.

### Phase 2 — AES Core Integration & Completion FSM
* **Goal:** Wire the AES core behind AXI4-Lite registers and track completion.
* **Results:**
  * AES core was modified to pull out `done` and `ciphertext_valid` signals, eliminating the mirror LFSR controller.
  * FSM designed to stream 16 bytes during S_FEED, wait for valid during S_WAIT, capture during S_CAP, and complete on `done` in S_DONE.
  * `axil_aes_test` (FIPS-197) successfully completed.

### Phase 3a — Independent Golden Model & Random Regression
* **Goal:** Add table-based reference oracle and run robust regressions.
* **Results:** Run `axil_rand_test` with 2000 random key/plaintext blocks, achieving 0 mismatches.

### Phase 3b — Protocol, Byte-Enable & Functional Coverage
* **Goal:** Verify partial-byte writes and address space boundaries.
* **Results:**
  * Verified all 16 WSTRB patterns.
  * Verified out-of-range addresses respond with `SLVERR` and write-to-RO behaves correctly.
  * Achieved 100% functional coverage in `axil_full_test`.

### Phase 3c — Boundary & Exception Testing
* **Goal:** Stress-test back-to-back operations, resets, and X-injections.
* **Results:**
  * Verified reset at various offsets, during handshakes, and exhaustively.
  * Verified X-injection stability on unmapped byte lanes.

### Phase 3d — Assertions & Coverage Closure
* **Goal:** Implement system assertions and sign off coverage.
* **Results:**
  * 11 AXI4-Lite SVA assertions and 8 cover properties implemented (100% assertion coverage).
  * 100% FSM transition coverage.
  * Verified all 259 NIST AESAVS KAT vectors.

### Phase 4 — Dual-Oracle DPI-C Co-Simulation
* **Goal:** Add a second, independent oracle — an AES-128 **C golden model**, reachable from the UVM environment through SystemVerilog DPI-C — and use it to cross-check the existing SV golden model rather than replace it.
* **Results:**
  * `c_model/aes128.c`: a standalone, table-based AES-128 implementation with the same MSB-first byte layout as the SV golden model, validated offline with a `gcc`-only self-test (FIPS-197 + all-zero vector) and against all 259 NIST AESAVS vectors (`c_model/aes128_kat_check.c`) — neither requires a simulator.
  * `tb/aes_dpi.svh` imports the C golden model via `` `import "DPI-C"` ``. `axil_dpi_test` runs the minimum end-to-end check: C self-check, C model vs. the hard-coded FIPS-197 vector, C model vs. `aes_ref_model`, and one DUT block vs. the C-model expected value.
  * `axil_rand_seq` (used by `axil_rand_test`) was extended to dual-oracle: every random block is checked against both `aes_ref_model` and `dpi_encrypt128` before the DUT is driven, so a disagreement between the two oracles is caught independently of any DUT bug (§2.4).
  * Local VCS regression (`sim/run_vcs.sh`) runs `axil_dpi_test` plus `axil_rand_test` at 2000 blocks, dual-oracle, 0 mismatches. EDA Playground runs a lighter budget-conscious subset through `sim/run.bash` and `sim/run_stress.bash` (§4.3), since the sandboxed simulators there are metered.

---

## 7. Limitations & Future Work

* **Random Stimulus:** Samples the input space; although highly indicative, it is not a mathematical proof.
* **SVA Coverage:** Properties are verified in simulation only, not proven formally.
* **RTL Level Only:** No gate-level simulation or Static Timing Analysis (STA/SDF).
* **DPI-C Golden Model:** `aes_ref_model` (SV) and `c_model/aes128.c` are two independently written implementations of the same AES-128 specification, not two different specifications — dual-oracle agreement catches implementation bugs in either model, but not a shared misreading of the spec. A third, unrelated implementation (e.g. a widely used crypto library) would close that gap; it is not currently wired in.
* **EDA Playground DPI-C Budget:** `sim/run.bash` and `sim/run_stress.bash` run a reduced test subset to fit EDA Playground's execution budget. The full 2000-block dual-oracle regression is exercised through `sim/run_vcs.sh` (§4.1) instead.
