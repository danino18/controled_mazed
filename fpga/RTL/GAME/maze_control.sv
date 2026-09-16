// The single vertical offset shared by every coral column.
// Holding up/down moves the whole maze; the speed ramps from 1 to
// MAZE_STEP_MAX px/frame so short taps give fine control. Holding both
// directions, or neither, keeps the maze still.

module maze_control
  import game_params_pkg::*;
(
    input  logic              clk,
    input  logic              resetN,
    input  logic              tick,        // once per frame
    input  logic              run,         // player may steer
    input  logic              restart,     // centre the maze
    input  logic              moveUp,
    input  logic              moveDown,
    output logic signed [9:0] mazeOffset,  // pixels; negative = openings move up
    output logic signed [4:0] mazeVy       // pixels moved in the last frame
);

  logic [3:0] holdFrames;
  logic [2:0] step;
  logic       up, down;
  int         next;

  assign up   = moveUp && !moveDown;
  assign down = moveDown && !moveUp;
  assign step = (holdFrames >= 4'd12) ? 3'(MAZE_STEP_MAX) : 3'd1 + 3'(holdFrames >> 2);

  always_comb begin
    next = int'(mazeOffset);
    if (up)   next = next - int'(step);
    if (down) next = next + int'(step);
    if (next < -MAZE_OFFSET_MAX) next = -MAZE_OFFSET_MAX;
    if (next >  MAZE_OFFSET_MAX) next =  MAZE_OFFSET_MAX;
  end

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      mazeOffset <= '0;
      mazeVy     <= '0;
      holdFrames <= '0;
    end else if (restart) begin
      mazeOffset <= '0;
      mazeVy     <= '0;
      holdFrames <= '0;
    end else if (tick) begin
      if (run) begin
        mazeOffset <= 10'(next);
        mazeVy     <= 5'(next - int'(mazeOffset));
      end else begin
        mazeVy <= '0;
      end
      if (run && (up || down)) begin
        if (holdFrames != 4'd15) holdFrames <= holdFrames + 4'd1;
      end else begin
        holdFrames <= '0;
      end
    end
  end

endmodule
