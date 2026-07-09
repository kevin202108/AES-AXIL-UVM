// =============================================================================
//  filelist.f  -  compile file list for LOCAL simulators (Questa/VCS/Xcelium).
//  Not used by EDA Playground (that flow is flat: paste design.sv / testbench.sv
//  and add the other files via "+").
//
//  Only the two roots are listed: design.sv pulls in aes_rtl.sv, and
//  testbench.sv pulls in axil_if.svh + axil_pkg.svh (which includes the rest),
//  all via `include resolved through the +incdir paths below.
//
//  Example (run from the project root  AES_AXI_Lite/):
//    Xcelium : xrun -uvm -sv -f sim/filelist.f +UVM_TESTNAME=axil_aes_test
//    VCS     : vcs  -sverilog -ntb_opts uvm -f sim/filelist.f +UVM_TESTNAME=axil_aes_test
//    Questa  : (vlog -sv +incdir+rtl +incdir+tb rtl/design.sv tb/testbench.sv) then vsim
//
//  Sim-only options:
//    +define+AES_DEBUG          per-cycle FSM/ciphertext trace
//    +define+SIM_FAULT_INJECT +FAULT=1|2   fault-injection sanity check
// =============================================================================

+incdir+rtl
+incdir+tb

rtl/design.sv
tb/testbench.sv
