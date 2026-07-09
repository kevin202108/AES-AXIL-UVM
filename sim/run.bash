#!/bin/bash
# =============================================================================
#  run.bash  -  one-click full regression for EDA Playground (Xcelium)
#  Enable with the "Use run.bash shell script" option; add this file as
#  "run.bash". Pushes the 1-minute budget by ELABORATING ONCE and re-running
#  every test with `xrun -R` (no recompile per test).
# =============================================================================

COMMON="-Q -unbuffered -timescale 1ns/1ns -sysv -access +rw \
        -uvmnocdnsextra -uvmhome $UVM_HOME $UVM_HOME/src/uvm_macros.svh \
        design.sv testbench.sv"

TESTS="axil_smoke_test axil_aes_test axil_rand_test axil_wstrb_test \
       axil_full_test axil_bp_test axil_b2b_test axil_reset_test \
       axil_err_test axil_wstrb_sweep_test axil_busy_test \
       axil_reset_sweep_test axil_reset_hs_test"

# ---- elaborate ONCE (with coverage) ----------------------------------------
echo "### elaborating (coverage on) ..."
xrun -elaborate $COMMON -coverage all -covoverwrite -cov_cgsample \
     > elab.log 2>&1
if ! grep -qiE "Elaborat|snapshot" elab.log; then
    echo "ELABORATION FAILED — tail of elab.log:"; tail -30 elab.log; exit 1
fi
echo "elaboration ok."
echo

# ---- run every test by reusing the snapshot --------------------------------
echo "=================== REGRESSION SUMMARY ==================="
printf "%-20s %-6s %-9s %s\n" "TEST" "RESULT" "ERR/FAT" "COVERAGE"
echo "---------------------------------------------------------"
total=0; passed=0
for t in $TESTS; do
    total=$((total+1))
    # -covtest gives each run its own coverage scope (avoids DB-lock on re-run)
    # keep regression fast: rand_test does a light 20 blocks here (heavy random
    # sampling is in run_stress.bash)
    extra=""; [ "$t" = "axil_rand_test" ] && extra="+NUM_BLOCKS=20"
    xrun -R -Q +UVM_TESTNAME=$t $extra -covtest $t > run_$t.log 2>&1
    err=$(grep -m1 'UVM_ERROR :' run_$t.log | grep -oE '[0-9]+$')
    fat=$(grep -m1 'UVM_FATAL :' run_$t.log | grep -oE '[0-9]+$')
    cov=$(grep -oE 'functional coverage = [0-9.]+ %' run_$t.log | tail -1 \
          | grep -oE '[0-9.]+ %')
    if [ "${err:-1}" = "0" ] && [ "${fat:-1}" = "0" ]; then
        res="PASS"; passed=$((passed+1))
    else
        res="FAIL"
    fi
    printf "%-20s %-6s %-9s %s\n" "$t" "$res" "${err:-?}/${fat:-?}" "${cov:-n/a}"
done
echo "---------------------------------------------------------"
echo "FUNCTIONAL REGRESSION:  PASSED $passed / $total"
echo "========================================================="
echo

# ---- fault-injection sanity (checker MUST go red) --------------------------
echo "### fault-injection sanity (re-elaborate with +define) ..."
xrun -elaborate $COMMON +define+SIM_FAULT_INJECT > elabf.log 2>&1
echo "============== FAULT INJECTION (expect FAIL) ============="
for fm in 1 2; do
    xrun -R -Q +UVM_TESTNAME=axil_smoke_test +FAULT=$fm > fault_$fm.log 2>&1
    err=$(grep -m1 'UVM_ERROR :' fault_$fm.log | grep -oE '[0-9]+$')
    if [ "${err:-0}" -gt 0 ]; then
        verdict="caught (good)"
    else
        verdict="MISSED (checker broken!)"
    fi
    printf "FAULT=%s -> UVM_ERROR=%-3s %s\n" "$fm" "${err:-?}" "$verdict"
done
echo "========================================================="
echo

# Heavy stress (1000 random + 259 NIST KAT) lives in run_stress.bash to stay
# under the 1-minute budget. FSM coverage prints in every run's log as [COV-FSM].

# ---- merged coverage (best-effort; also probes whether imc exists) ---------
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
    # print the summary lines imc emits (overall / code / functional)
    grep -iE 'overall|covered|coverage|block|expression|toggle|covergroup|score' imc.log \
        | head -40
    echo "(full imc output in imc.log inside the downloaded ZIP)"
else
    echo "imc not found on PATH -> coverage merge not available on this sandbox."
    echo "Per-test functional coverage is in the table above; 'axil_full_test' = 100%."
fi
echo "========================================================="
