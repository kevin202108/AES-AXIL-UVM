#!/bin/bash
# =============================================================================
#  run_stress.bash  -  deep/structural job (separate from run.bash to fit the
#  ~1-minute EDA Playground budget). Random on EDA Playground is transaction-
#  bound (~15s per 200 blocks), so big random volume needs multiple jobs or an
#  unmetered (local) simulator run; here we run the high-value structural items
#  plus a modest random batch.
#    - NIST KAT (259 known-answer vectors)
#    - exhaustive reset sweep (56 cycle points)
#    - X-injection
#    - 100 random blocks vs golden
#  FSM coverage prints per run as [COV-FSM].
# =============================================================================

COMMON="-Q -unbuffered -timescale 1ns/1ns -sysv -access +rw \
        -uvmnocdnsextra -uvmhome $UVM_HOME $UVM_HOME/src/uvm_macros.svh \
        design.sv testbench.sv"

echo "### elaborating (coverage on) ..."
xrun -elaborate $COMMON -coverage all -covoverwrite -cov_cgsample > elab.log 2>&1
if ! grep -qiE "Elaborat|snapshot" elab.log; then
    echo "ELABORATION FAILED:"; tail -30 elab.log; exit 1
fi
echo "elaboration ok."; echo

run_one () {  # $1 = test, $2 = extra plusargs, $3 = label
    xrun -R -Q +UVM_TESTNAME=$1 $2 -covtest $1 > st_$1.log 2>&1
    e=$(grep -m1 'UVM_ERROR :' st_$1.log | grep -oE '[0-9]+$')
    if [ "${e:-1}" = "0" ]; then r="PASS"; else r="FAIL"; fi
    printf "%-28s -> %s (UVM_ERROR=%s)\n" "$3" "$r" "${e:-?}"
}

echo "==================== STRESS / CORNERS ===================="
run_one axil_kat_test               ""               "NIST KAT (259 vectors)"
run_one axil_reset_exhaustive_test  ""               "exhaustive reset (56 pts)"
run_one axil_xinj_test              ""               "X-injection"
run_one axil_rand_test              "+NUM_BLOCKS=100" "random x100 vs golden"
echo "---------------------------------------------------------"
katv=$(grep -oE 'NIST KAT: [0-9]+ vectors  pass=[0-9]+  fail=[0-9]+' st_axil_kat_test.log | tail -1)
fcov=$(grep -oE 'FSM state/transition coverage = [0-9.]+ %' st_axil_kat_test.log | tail -1)
echo "KAT detail : ${katv:-n/a}"
echo "FSM cov    : ${fcov:-n/a}"
echo "========================================================="
