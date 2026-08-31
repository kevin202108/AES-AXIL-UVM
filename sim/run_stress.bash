#!/bin/bash
# =============================================================================
#  run_stress.bash  -  deep/structural job (separate from run.bash to fit the
#  ~1-minute EDA Playground budget). Random on EDA Playground is transaction-
#  bound (~15s per 200 blocks), so big random volume needs multiple jobs or an
#  unmetered (local) simulator run; here we run the high-value structural items
#  plus a modest dual-oracle random batch.
#    - NIST KAT (259 known-answer vectors)
#    - exhaustive reset sweep (56 cycle points)
#    - X-injection
#    - 100 random blocks (dual oracle: SV + C via DPI-C)
#
#  EDA Playground: enable "Use run.bash shell script", paste this file as
#  run.bash (or rename), keep Design tab aes128.c. Same DPI link rule as
#  sim/run.bash — aes128.c must be on the compile/elaborate command line.
#  FSM coverage prints per run as [COV-FSM].
# =============================================================================

C_GOLDEN="aes128.c"
SV_TOPS="design.sv testbench.sv"

if command -v xrun >/dev/null 2>&1; then
    SIM=xcelium
elif command -v vcs >/dev/null 2>&1; then
    SIM=vcs
else
    echo "ERROR: neither xrun nor vcs found."; exit 1
fi
echo "### stress job simulator: $SIM  (DPI-C: $C_GOLDEN)"

if [ "$SIM" = "xcelium" ]; then
    COMMON="-Q -unbuffered -timescale 1ns/1ns -sysv -access +rw \
            -uvmnocdnsextra -uvmhome $UVM_HOME $UVM_HOME/src/uvm_macros.svh \
            $SV_TOPS $C_GOLDEN"

    echo "### elaborating (coverage on, aes128.c linked) ..."
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
else
    VCS_UVM="+incdir+$UVM_HOME/src $UVM_HOME/src/uvm.sv $UVM_HOME/src/dpi/uvm_dpi.cc -CFLAGS -DVCS"
    VCS_BASE="-full64 -licqueue $VCS_UVM -timescale=1ns/1ns +vcs+flush+all +warn=all -sverilog"
    # shellcheck disable=SC2086
    vcs $VCS_BASE $SV_TOPS $C_GOLDEN -l comp.log
    if [ ! -x ./simv ]; then
        echo "COMPILE FAILED:"; tail -30 comp.log; exit 1
    fi
    echo "compile ok."; echo

    run_one () {
        ./simv +vcs+lic+wait +UVM_TESTNAME=$1 $2 > st_$1.log 2>&1
        e=$(grep -m1 'UVM_ERROR :' st_$1.log | grep -oE '[0-9]+$')
        if [ "${e:-1}" = "0" ]; then r="PASS"; else r="FAIL"; fi
        printf "%-28s -> %s (UVM_ERROR=%s)\n" "$3" "$r" "${e:-?}"
    }
fi

echo "==================== STRESS / CORNERS ===================="
run_one axil_kat_test               ""                "NIST KAT (259 vectors)"
run_one axil_reset_exhaustive_test  ""                "exhaustive reset (56 pts)"
run_one axil_xinj_test              ""                "X-injection"
run_one axil_rand_test              "+NUM_BLOCKS=100" "random x100 dual oracle"
echo "---------------------------------------------------------"
katv=$(grep -oE 'NIST KAT: [0-9]+ vectors  pass=[0-9]+  fail=[0-9]+' st_axil_kat_test.log | tail -1)
fcov=$(grep -oE 'FSM state/transition coverage = [0-9.]+ %' st_axil_kat_test.log | tail -1)
rand=$(grep -oE 'RANDOM TEST: .* dual_fail=[0-9]+' st_axil_rand_test.log | tail -1)
echo "KAT detail : ${katv:-n/a}"
echo "FSM cov    : ${fcov:-n/a}"
echo "RAND detail: ${rand:-n/a}"
echo "========================================================="
