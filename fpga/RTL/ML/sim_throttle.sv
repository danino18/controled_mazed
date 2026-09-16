// Simulation speed of the trainer: allows one step every sim_period(level)
// clocks (level 0 = one step per VGA frame, 72.6 steps/s; level 7 = steps back
// to back). It is a free-running divider, independent of the video.

module sim_throttle
  import ml_pkg::*;
(
    input  logic       clk,
    input  logic       resetN,
    input  logic [2:0] level,
    input  logic       stepTaken,   // the simulator started a step
    output logic       stepGo
);

  logic [18:0] period;
  logic [18:0] count;
  logic        credit;
  logic        wrap;

  assign period = sim_period(level);
  assign wrap   = (count >= period - 19'd1);
  assign stepGo = (period == 19'd0) || credit;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      count  <= '0;
      credit <= 1'b0;
    end else begin
      if (period == 19'd0 || wrap) count <= '0;
      else                         count <= count + 19'd1;

      if (wrap)           credit <= 1'b1;
      else if (stepTaken) credit <= 1'b0;
    end
  end

endmodule
