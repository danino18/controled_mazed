// The player-independent half of the network's inputs, computed once per step
// from the world (and shared by every training lane).
//
//   next1   the column still to be passed with the smallest x
//   next2   the active column after it (next1 when there is no other column)
//   vis1    next1 exists and is on screen
//   use2    next2 is a different column and is on screen
//   tau     frames until next1's collision core reaches the bird's hitbox
//           (0 while overlapping, 127 when next1 is not on screen)
//   birdC   row of the bird hitbox centre
//
// Only what a human can see is used: off-screen columns are ignored.
// All outputs are registered on sample.

module feature_world
  import game_params_pkg::*, ml_pkg::*;
(
    input  logic                         clk,
    input  logic                         resetN,
    input  logic                         sample,
    input  logic signed [10:0]           birdY,
    input  logic signed [11:0]           birdVy,
    input  logic [NUM_COLUMNS-1:0]       colActive,
    input  logic [NUM_COLUMNS-1:0][10:0] colX,
    input  logic [2:0]                   speedLevel,
    output logic [1:0]                   next1,
    output logic [1:0]                   next2,
    output logic                         vis1,
    output logic                         use2,
    output logic [6:0]                   tau,
    output logic signed [10:0]           birdC,
    output logic signed [11:0]           birdVyOut
);

  int   x [NUM_COLUMNS];
  logic has1, has2;
  logic [1:0] n1, n2;

  always_comb begin
    for (int i = 0; i < NUM_COLUMNS; i++) x[i] = int'($signed(colX[i]));

    has1 = 1'b0;
    n1   = 2'd0;
    for (int i = 0; i < NUM_COLUMNS; i++)
      if (colActive[i] && x[i] >= NOT_PASSED_X && (!has1 || x[i] < x[n1])) begin
        has1 = 1'b1;
        n1   = 2'(i);
      end

    has2 = 1'b0;
    n2   = n1;
    for (int i = 0; i < NUM_COLUMNS; i++)
      if (has1 && colActive[i] && x[i] > x[n1] && (!has2 || x[i] < x[n2])) begin
        has2 = 1'b1;
        n2   = 2'(i);
      end
  end

  // ---------------------------------------------------------------- time to arrival
  logic [8:0]  recip;
  int          dx;
  logic        v1, v2;
  logic [17:0] scaled;
  logic [6:0]  tauNow;

  always_comb begin
    case (speedLevel)
      3'd0:    recip = TAU_RECIP_0;
      3'd1:    recip = TAU_RECIP_1;
      3'd2:    recip = TAU_RECIP_2;
      3'd3:    recip = TAU_RECIP_3;
      3'd4:    recip = TAU_RECIP_4;
      3'd5:    recip = TAU_RECIP_5;
      3'd6:    recip = TAU_RECIP_6;
      default: recip = TAU_RECIP_7;
    endcase
  end

  assign v1     = has1 && x[n1] < SCREEN_W;
  assign v2     = v1 && has2 && x[n2] < SCREEN_W;
  assign dx     = x[n1] + CORAL_CORE_INSET - HB_RIGHT;
  assign scaled = 18'(dx) * 18'(recip);          // only used when 0 < dx < SCREEN_W

  always_comb begin
    if (!v1)                          tauNow = 7'(TAU_MAX);
    else if (dx <= 0)                 tauNow = 7'd0;
    else if (scaled[17:8] > TAU_MAX)  tauNow = 7'(TAU_MAX);
    else                              tauNow = scaled[14:8];
  end

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      next1     <= '0;
      next2     <= '0;
      vis1      <= 1'b0;
      use2      <= 1'b0;
      tau       <= 7'(TAU_MAX);
      birdC     <= '0;
      birdVyOut <= '0;
    end else if (sample) begin
      next1     <= n1;
      next2     <= n2;
      vis1      <= v1;
      use2      <= v2;
      tau       <= tauNow;
      birdC     <= birdY + 11'(BIRD_HB_CENTRE);
      birdVyOut <= birdVy;
    end
  end

endmodule
