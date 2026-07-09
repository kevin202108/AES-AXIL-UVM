#!/bin/bash
# =============================================================================
#  run_vcs.sh  -  one-shot VCS + UVM-1.2 coverage regression
#
#  Usage (from anywhere; the script cd's to the project root itself):
#      bash sim/run_vcs.sh
#
#  Does: compile (with coverage) -> run all tests + 2000-block random ->
#        pass/fail summary -> URG report (HTML + text).
#  Open  urgReport/dashboard.html  for code coverage; text copy in urgReport_txt/.
# =============================================================================

cd "$(dirname "$0")/.." || exit 1     # -> AES_AXI_Lite root (filelist paths are relative)

CM="line+cond+fsm+tgl+branch"
TESTS="axil_smoke_test axil_aes_test axil_wstrb_test axil_wstrb_sweep_test \
       axil_full_test axil_bp_test axil_b2b_test axil_err_test axil_busy_test \
       axil_xinj_test axil_stagger_test axil_reset_test axil_reset_sweep_test \
       axil_reset_hs_test axil_reset_exhaustive_test axil_kat_test"

echo "### compiling (VCS + UVM 1.2 + coverage) ..."
vcs -full64 -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps -f sim/filelist.f \
    -debug_access+all -cm $CM -l comp.log
if [ ! -x ./simv ]; then
    echo "*** COMPILE FAILED - tail of comp.log ***"; tail -30 comp.log; exit 1
fi
echo "compile ok."

cp -f tb/kat_*.dat .                   # $readmemh needs the KAT data in the run dir

echo
echo "========================= REGRESSION ========================="
printf "%-32s %s\n" "TEST" "RESULT (ERR/FATAL)"
echo "--------------------------------------------------------------"
pass=0; total=0
for t in $TESTS; do
    total=$((total+1))
    ./simv +UVM_TESTNAME=$t -cm $CM -cm_name $t -l log_$t.log > /dev/null 2>&1
    e=$(grep -m1 'UVM_ERROR :' log_$t.log | grep -oE '[0-9]+$')
    f=$(grep -m1 'UVM_FATAL :' log_$t.log | grep -oE '[0-9]+$')
    if [ "${e:-1}" = "0" ] && [ "${f:-1}" = "0" ]; then r="PASS"; pass=$((pass+1)); else r="FAIL"; fi
    printf "%-32s %-4s (%s/%s)\n" "$t" "$r" "${e:-?}" "${f:-?}"
done

# heavy random (no 1-minute limit here)
total=$((total+1))
./simv +UVM_TESTNAME=axil_rand_test +NUM_BLOCKS=2000 -cm $CM -cm_name rand -l log_rand.log > /dev/null 2>&1
e=$(grep -m1 'UVM_ERROR :' log_rand.log | grep -oE '[0-9]+$')
if [ "${e:-1}" = "0" ]; then r="PASS"; pass=$((pass+1)); else r="FAIL"; fi
printf "%-32s %-4s (%s)\n" "axil_rand_test (2000 blocks)" "$r" "${e:-?}"
echo "--------------------------------------------------------------"
echo "PASSED $pass / $total"
echo "=============================================================="

echo
echo "### generating URG coverage report ..."
urg -dir simv.vdb -report urgReport          > urg.log 2>&1
urg -dir simv.vdb -format text -report urgReport_txt > urg_txt.log 2>&1
echo "HTML : urgReport/dashboard.html"
echo "text : urgReport_txt/  (grep -i cond/line for quick numbers)"
echo "done."
