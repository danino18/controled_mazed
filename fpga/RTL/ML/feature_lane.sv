// The player-dependent half of the network's inputs, one per lane, and their
// conversion to the network's 8-bit Q1.6 format (value / 64):
//
//   F0 e_next   next opening centre - bird centre   (px, 1.0 = 128 px)
//   F1 e_after  same for the column after it        (px, 1.0 = 128 px)
//               (= e_next when that column is not on screen or does not exist)
//   F2 v_rel    how fast e_next changes: maze speed - bird speed
//               (1/64 px per frame, 1.0 = 4 px per frame)
//   F3 tau      frames until the next column arrives (1.0 = 64 frames)
//
// A positive error means the opening is below the bird, so the maze should
// move up. All outputs are registered on sample.

module feature_lane
  import game_params_pkg::*, ml_pkg::*;
(
    input  logic                         clk,
    input  logic                         resetN,
    input  logic                         sample,
    // from feature_world
    input  logic [1:0]                   next1,
    input  logic [1:0]                   next2,
    input  logic                         vis1,
    input  logic                         use2,
    input  logic [6:0]                   tau,
    input  logic signed [10:0]           birdC,
    input  logic signed [11:0]           birdVy,
    // from this lane
    input  logic [NUM_COLUMNS-1:0][9:0]  gapTop,
    input  logic signed [4:0]            mazeVy,
    // network inputs
    output logic [NN_INPUTS-1:0][7:0]    feat,
    output logic                         aligned,   // next column on screen and |e_next| <= ALIGN_TOL
    output logic signed [10:0]           eNext      // unscaled, for debugging
);

  function automatic logic [7:0] sat8(input int v);
    if (v > 127)  return 8'd127;
    if (v < -128) return 8'h80;
    return 8'(v);
  endfunction

  int e1, e2, vrel;

  always_comb begin
    e1   = vis1 ? int'(gapTop[next1]) + GAP_H / 2 - int'(birdC) : 0;
    e2   = use2 ? int'(gapTop[next2]) + GAP_H / 2 - int'(birdC) : e1;
    vrel = int'(mazeVy) * (1 << FIXED_SHIFT) - int'(birdVy);
  end

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      feat    <= '0;
      aligned <= 1'b0;
      eNext   <= '0;
    end else if (sample) begin
      feat[0] <= sat8(e1 >>> 1);
      feat[1] <= sat8(e2 >>> 1);
      feat[2] <= sat8(vrel >>> 2);
      feat[3] <= {1'b0, tau};
      aligned <= vis1 && e1 <= ALIGN_TOL && e1 >= -ALIGN_TOL;
      eNext   <= 11'(e1);
    end
  end

endmodule
