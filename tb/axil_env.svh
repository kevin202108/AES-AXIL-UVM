// =============================================================================
//  axil_env.svh  -  environment: agent + scoreboard + coverage
// =============================================================================
class axil_env extends uvm_env;
    `uvm_component_utils(axil_env)

    axil_agent      agent;
    axil_scoreboard sb;
    axil_coverage   cov;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = axil_agent     ::type_id::create("agent", this);
        sb    = axil_scoreboard::type_id::create("sb",    this);
        cov   = axil_coverage  ::type_id::create("cov",   this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.mon.ap.connect(sb.ap_imp);          // checker
        agent.mon.ap.connect(cov.analysis_export); // functional coverage
    endfunction
endclass
