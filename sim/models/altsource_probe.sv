// Simulation stand-in for Quartus' altsource_probe (In-System Sources and
// Probes). The model in the precompiled altera_mf library leaves the source
// outputs floating, so run_tests.sh searches work first (-L work) and this
// stand-in is used: the JTAG side does not exist in
// simulation, so the source outputs stay at their initial value (0) unless a
// testbench forces them.

module altsource_probe #(
    parameter lpm_type                = "altsource_probe",
    parameter lpm_hint                = "UNUSED",
    parameter sld_auto_instance_index = "YES",
    parameter sld_instance_index      = 0,
    parameter instance_id             = "UNUSED",
    parameter probe_width             = 1,
    parameter source_width            = 1,
    parameter source_initial_value    = "0",
    parameter enable_metastability    = "NO"
) (
    input  logic [probe_width-1:0]  probe,
    output logic [source_width-1:0] source,
    input  logic                    source_clk,
    input  logic                    source_ena
);

  assign source = '0;

endmodule
