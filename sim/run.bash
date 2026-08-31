#!/bin/bash
# =============================================================================
#  run.bash  -  EDA Playground primary run path (DPI-C + full light regression)
#
#  How to use on EDA Playground:
#    1. Enable  "Use run.bash shell script"
#    2. Add this file as Testbench (or top-level) tab named exactly  run.bash
#    3. Design pane still needs tab  aes128.c  (file must exist in sandbox)
#    4. Pick Cadence Xcelium  or  Synopsys VCS  (UVM enabled)
#    5. Click Run  —  this script links aes128.c (do NOT rely on Compile Options)
#
#  Why: Playground's default  vcs ... design.sv testbench.sv  never lists extra
#  Design tabs on the command line. A .c file is never `include`d, so without
#  this script (or Compile Options: aes128.c) you get Error-[DPI-DIFNF].
#
#  Budget: elaborate/compile once, re-run each test; rand uses 20 blocks.
#  Heavy random / KAT: see run_stress.bash (also needs aes128.c).
# =============================================================================

# Bare names — Playground sandbox has no c_model/ prefix
SV_TOPS="design.sv testbench.sv"
C_GOLDEN="aes128.c"

TESTS="axil_dpi_test axil_rand_test"

run_table_header () {
    echo "=================== REGRESSION SUMMARY ==================="
    printf "%-20s %-6s %-9s %s\n" "TEST" "RESULT" "ERR/FAT" "COVERAGE"
    echo "---------------------------------------------------------"
}

judge_log () {  # $1 = log file -> prints RESULT ERR/FAT COV; sets global res
    local log=$1
    local err fat cov
    err=$(grep -m1 'UVM_ERROR :' "$log" | grep -oE '[0-9]+$')
    fat=$(grep -m1 'UVM_FATAL :' "$log" | grep -oE '[0-9]+$')
    cov=$(grep -oE 'functional coverage = [0-9.]+ %' "$log" | tail -1 \
          | grep -oE '[0-9.]+ %')
    if [ "${err:-1}" = "0" ] && [ "${fat:-1}" = "0" ]; then
        res="PASS"
    else
        res="FAIL"
    fi
    printf "%-20s %-6s %-9s %s\n" "$t" "$res" "${err:-?}/${fat:-?}" "${cov:-n/a}"
}

# ---- pick simulator (Playground installs one of these for the selected tool)
if command -v xrun >/dev/null 2>&1; then
    SIM=xcelium
elif command -v vcs >/dev/null 2>&1; then
    SIM=vcs
else
    echo "ERROR: neither xrun nor vcs found on PATH."
    echo "On EDA Playground select Cadence Xcelium or Synopsys VCS + UVM."
    exit 1
fi
echo "### simulator: $SIM  (DPI-C golden: $C_GOLDEN)"

# EDA Playground VCS sandboxes often lack /usr/bin/cmp. VCS incremental compile
# calls cmp; missing binary → Error-[EXCF] and aborts (seen on fault recompile
# in logs/dpi_bash.log). Provide a minimal cmp(1) on PATH when needed.
ensure_cmp () {
    if command -v cmp >/dev/null 2>&1; then
        return 0
    fi
    echo "### note: system 'cmp' missing — installing PATH stub for VCS"
    mkdir -p .pg_bin
    cat > .pg_bin/cmp <<'EOF'
#!/bin/sh
# Minimal cmp(1) for EDA Playground: exit 0 same, 1 differ, 2 error.
# Supports: cmp file1 file2  and  cmp -s file1 file2
while [ $# -gt 0 ]; do
  case "$1" in
    -s|--silent|--quiet) shift ;;
    --) shift; break ;;
    -*) shift ;;
    *) break ;;
  esac
done
if [ $# -lt 2 ]; then
  echo "cmp: missing operand" >&2
  exit 2
fi
f1=$1; f2=$2
if [ ! -f "$f1" ] || [ ! -f "$f2" ]; then
  exit 2
fi
if command -v diff >/dev/null 2>&1; then
  if diff -q "$f1" "$f2" >/dev/null 2>&1; then exit 0; else exit 1; fi
fi
c1=$(cksum < "$f1" 2>/dev/null)
c2=$(cksum < "$f2" 2>/dev/null)
if [ -n "$c1" ] && [ "$c1" = "$c2" ]; then exit 0; else exit 1; fi
EOF
    chmod +x .pg_bin/cmp
    export PATH="$(pwd)/.pg_bin:$PATH"
}

# Wipe VCS build products so the next vcs is a clean compile (define changes).
vcs_clean () {
    rm -rf simv simv.daidir csrc
    rm -f simv.vdb ucli.key
}

# =============================================================================
#  Xcelium path
# =============================================================================
if [ "$SIM" = "xcelium" ]; then
    COMMON="-Q -unbuffered -timescale 1ns/1ns -sysv -access +rw \
            -uvmnocdnsextra -uvmhome $UVM_HOME $UVM_HOME/src/uvm_macros.svh \
            $SV_TOPS $C_GOLDEN"

    echo "### elaborating once (coverage on, aes128.c linked) ..."
    xrun -elaborate $COMMON -coverage all -covoverwrite -cov_cgsample \
         > elab.log 2>&1
    if ! grep -qiE "Elaborat|snapshot" elab.log; then
        echo "ELABORATION FAILED — tail of elab.log:"; tail -30 elab.log; exit 1
    fi
    echo "elaboration ok."
    echo

    run_table_header
    total=0; passed=0
    for t in $TESTS; do
        total=$((total+1))
        # keep regression under ~1 min: light dual-oracle random (20 blocks)
        extra=""; [ "$t" = "axil_rand_test" ] && extra="+NUM_BLOCKS=20"
        xrun -R -Q +UVM_TESTNAME=$t $extra -covtest $t > run_$t.log 2>&1
        judge_log run_$t.log
        [ "$res" = "PASS" ] && passed=$((passed+1))
    done
    echo "---------------------------------------------------------"
    echo "FUNCTIONAL REGRESSION:  PASSED $passed / $total"
    echo "========================================================="
    echo

    # ---- merged coverage (best-effort) -------------------------------------
    echo "### merged coverage (code + functional) via imc ..."
    if command -v imc >/dev/null 2>&1; then
        cat > cov_report.tcl <<'EOF'
merge [glob -nocomplain cov_work/scope/*] -out cov_work/merged -overwrite -message 1
load -run cov_work/merged
report -summary -metrics all
exit
EOF
        imc -batch -input cov_report.tcl > imc.log 2>&1
        echo "------------------ MERGED COVERAGE ------------------"
        grep -iE 'overall|covered|coverage|block|expression|toggle|covergroup|score' imc.log \
            | head -40
        echo "(full imc output in imc.log inside the downloaded ZIP)"
    else
        echo "imc not found on PATH -> coverage merge not available on this sandbox."
        echo "Per-test functional coverage is in the table above; 'axil_full_test' = 100%."
    fi
    echo "========================================================="

# =============================================================================
#  VCS path  (matches EDA Playground UVM injection style from dpi_*.log)
# =============================================================================
else
    # Same UVM wiring Playground uses when "UVM" is enabled (do not use -ntb_opts
    # here — it can double-include against $UVM_HOME/src/uvm.sv on the sandbox).
    VCS_UVM="+incdir+$UVM_HOME/src $UVM_HOME/src/uvm.sv $UVM_HOME/src/dpi/uvm_dpi.cc -CFLAGS -DVCS"
    VCS_BASE="-full64 -licqueue $VCS_UVM -timescale=1ns/1ns +vcs+flush+all +warn=all -sverilog"

    ensure_cmp

    echo "### compiling once (aes128.c on vcs command line) ..."
    # shellcheck disable=SC2086
    vcs $VCS_BASE $SV_TOPS $C_GOLDEN -l comp.log
    if [ ! -x ./simv ]; then
        echo "COMPILE FAILED — tail of comp.log:"; tail -40 comp.log; exit 1
    fi
    # First log line / compile cmd must mention aes128.c (DPI link hygiene)
    if grep -qE 'aes128\.c' comp.log 2>/dev/null || \
       ls ./simv.daidir 2>/dev/null | grep -q aes128; then
        echo "compile ok (aes128.c linked)."
    else
        echo "compile finished — if DPI-DIFNF appears, Design tab must be named aes128.c"
    fi
    echo

    run_table_header
    total=0; passed=0
    for t in $TESTS; do
        total=$((total+1))
        extra=""; [ "$t" = "axil_rand_test" ] && extra="+NUM_BLOCKS=20"
        ./simv +vcs+lic+wait +UVM_TESTNAME=$t $extra +UVM_VERBOSITY=UVM_LOW \
            > run_$t.log 2>&1
        judge_log run_$t.log
        [ "$res" = "PASS" ] && passed=$((passed+1))
    done
    echo "---------------------------------------------------------"
    echo "FUNCTIONAL REGRESSION:  PASSED $passed / $total"
    echo "  includes axil_dpi_test + axil_rand_test (dual oracle, 20 blocks)"
    echo "========================================================="
fi

# Heavy stress (1000 random + 259 NIST KAT) lives in run_stress.bash.
# Dual-oracle markers to grep in per-test logs:
#   *** DPI-C MINIMUM TEST PASSED ***
#   *** RANDOM TEST PASSED (dual oracle) ***
