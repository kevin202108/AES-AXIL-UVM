// =============================================================================
//  axil_pkg.svh  -  UVM package: pulls in every component (one class per file)
//  Include order matters (dependencies): item -> driver/monitor -> agent ->
//  scoreboard -> env -> sequences -> tests.
// =============================================================================
package axil_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "axil_item.svh"        // axil_item + axil_sequencer typedef
    `include "axil_driver.svh"
    `include "axil_monitor.svh"
    `include "axil_agent.svh"
    `include "axil_scoreboard.svh"
    `include "axil_coverage.svh"
    `include "axil_env.svh"
    `include "aes_ref_model.svh"    // independent AES-128 golden oracle
    `include "axil_sequences.svh"   // base / smoke / aes / random sequences
    `include "axil_tests.svh"       // base / smoke / aes / random tests
endpackage
