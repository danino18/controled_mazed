// Splits each frame's game update into ordered one-clock steps:
//   tickMove  - positions advance (bird, maze, coral)
//   tickCheck - collision and scoring look at the new positions
//   tickState - the game state machine reacts
// startOfFrame arrives during vertical blanking, so all steps finish before
// the first visible line is drawn.

module frame_sequencer (
    input  logic clk,
    input  logic resetN,
    input  logic startOfFrame,
    output logic tickMove,
    output logic tickCheck,
    output logic tickState
);

  assign tickMove = startOfFrame;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      tickCheck <= 1'b0;
      tickState <= 1'b0;
    end else begin
      tickCheck <= tickMove;
      tickState <= tickCheck;
    end
  end

endmodule
