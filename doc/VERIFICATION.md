# Verification & Run Guide — AES-128 AXI4-Lite UVM Environment

## 1. Executive Summary & Results

The byte-serial AES-128 core is wrapped in a standard AXI4-Lite register interface and verified with a complete UVM environment. Verification covers functional correctness, registers and byte-enables, AXI4-Lite protocol compliance, and boundary/exception behaviour (reset, back-to-back, backpressure, error response, X-injection). An **independent table-based AES reference model** serves as the oracle, cross-checked against the **NIST AESAVS** known-answer vectors and constrained-random stimulus.

### Key Results
- **Functional:** FIPS-197 directed + constrained-random (vs an independent golden model) + **259 NIST AESAVS known-answer vectors**, all passing.
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
| `aes_ref_model.svh` | Independent table-based AES-128 golden model |
| `axil_sequences.svh` | Base / smoke / aes / rand / wstrb / full / b2b / kat / xinj / … |
| `axil_tests.svh` | The 18 tests |
| `kat_key.dat`, `kat_pt.dat`, `kat_ct.dat` | NIST AESAVS known-answer vectors |

---

## 4. Run Guide & Test Library

### 4.1 Running with a Local Simulator
To compile the project (compile roots are `design.sv` and `testbench.sv`):
```sh
# Compile once (whole project pulled in via `include + +incdir)
<sim_command> -sverilog -ntb_opts uvm-1.2 -f sim/filelist.f
```
To run a specific test:
```sh
# Run any test (no recompile needed)
./simv +UVM_TESTNAME=axil_kat_test
```
A one-command regression + merged coverage script is provided in `sim/run_vcs.sh`:
```sh
bash sim/run_vcs.sh
```

### 4.2 Running on EDA Playground (Free, in browser)
1. Add each `rtl/` and `tb/` file (and the three `.dat` files) using the **+** button.
2. Select a UVM-capable simulator (e.g., VCS or Xcelium).
3. Set compile roots to `design.sv` and `testbench.sv`.
4. In **Run options**, specify: `+UVM_TESTNAME=axil_aes_test`.
5. Run.

### 4.3 Code Coverage Collection
To collect coverage locally:
```sh
<sim_command> -sverilog -ntb_opts uvm-1.2 -f sim/filelist.f -cm line+cond+fsm+tgl+branch
./simv +UVM_TESTNAME=axil_full_test -cm line+cond+fsm+tgl+branch -cm_name full
urg -dir simv.vdb -report urgReport      # open urgReport/dashboard.html
```

### 4.4 Debug Options
* **FSM/Ciphertext Trace**: Add `+define+AES_DEBUG` to compile options.
* **Fault Injection**: Add `+define+SIM_FAULT_INJECT +FAULT=1` (or `2`) with `axil_smoke_test`.

### 4.5 Test Library Summary

| Test | Objective / Behavior |
|------|----------------------|
| `axil_smoke_test` | Register read/write/read-back (default) |
| `axil_aes_test` | FIPS-197 directed encryption |
| `axil_rand_test` | Random key/pt vs golden (`+NUM_BLOCKS=<n>`, default 100) |
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

---

## 7. Limitations & Future Work

* **Random Stimulus:** Samples the input space; although highly indicative, it is not a mathematical proof.
* **SVA Coverage:** Properties are verified in simulation only, not proven formally.
* **RTL Level Only:** No gate-level simulation or Static Timing Analysis (STA/SDF).
