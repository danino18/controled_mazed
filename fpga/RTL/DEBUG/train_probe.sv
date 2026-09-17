// JTAG view of the trainer (Quartus In-System Sources and Probes, instance
// "TRNP"), for measuring training on the board from a PC:
//
//   probe  (read with quartus_stp, see tools/train_probe.tcl)
//     the trainer's snapshot statistics: generation, champion, last
//     validation, mean survival, stall, stage, steps per second, final test,
//     committed AI
//   source (written with quartus_stp; all zero after configuration)
//     [0]      start training (rising edge; only on the mode menu)
//     [1]      stop training and keep the champion (rising edge)
//     [2]      leave the training screen when training is complete (rising edge)
//     [4:3]    difficulty to train on, [6:5] coral columns (1..3), [9:7] world speed
//     [10]     use [13:11] as the simulation speed instead of Numpad 4/6
//     [13:11]  simulation speed level
//     [14]     SignalTap trigger helper (free)
//
// The sources only add requests; the keyboard and KEY1 keep working. With
// ENABLE = 0 (simulation) the sources stay zero.

module train_probe #(
    parameter bit ENABLE = 1'b1
) (
    input  logic         clk,
    input  logic         resetN,
    input  logic [191:0] probe,
    output logic         startReq,      // one clock
    output logic         stopReq,       // one clock
    output logic         exitReq,       // one clock
    output logic [1:0]   difficulty,
    output logic [1:0]   columns,
    output logic [2:0]   speed,
    output logic         simOverride,
    output logic [2:0]   simLevel,
    output logic         marker
);

  logic [15:0] source;

  generate
    if (ENABLE) begin : jtag
      altsource_probe #(
          .sld_auto_instance_index("YES"),
          .sld_instance_index     (0),
          .instance_id            ("TRNP"),
          .probe_width            (192),
          .source_width           (16),
          .source_initial_value   ("0"),
          .enable_metastability   ("YES")
      ) issp (
          .probe     (probe),
          .source    (source),
          .source_clk(clk),
          .source_ena(1'b1)
      );
    end else begin : none
      assign source = '0;
    end
  endgenerate

  logic [2:0] last;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      last     <= '0;
      startReq <= 1'b0;
      stopReq  <= 1'b0;
      exitReq  <= 1'b0;
    end else begin
      last     <= source[2:0];
      startReq <= source[0] && !last[0];
      stopReq  <= source[1] && !last[1];
      exitReq  <= source[2] && !last[2];
    end
  end

  assign difficulty  = source[4:3];
  assign columns     = source[6:5];
  assign speed       = source[9:7];
  assign simOverride = source[10];
  assign simLevel    = source[13:11];
  assign marker      = source[14];

endmodule
