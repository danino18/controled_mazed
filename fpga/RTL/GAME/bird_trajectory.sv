// Autonomous vertical motion of the bird. The bird never moves horizontally.
//
// EASY: smooth sine bob using the supplied sintable (RTL/AUDIO/SinTable.sv).
// MEDIUM and HARD are added in M8; until then every mode behaves as EASY.
//
// Positions are fixed point (1/64 px). Outputs change only on tick.

module bird_trajectory
  import game_params_pkg::*;
(
    input  logic               clk,
    input  logic               resetN,
    input  logic               tick,        // once per frame
    input  logic               run,         // advance the motion on tick
    input  logic               restart,     // return to the centre (one clock)
    input  logic [1:0]         mode,        // 0 EASY, 1 MEDIUM, 2 HARD
    input  logic [15:0]        rnd,         // random bits, sampled on tick
    output logic signed [10:0] birdY,       // top edge of the sprite, pixels
    output logic signed [11:0] birdVy,      // vertical speed, 1/64 px per frame
    output logic [7:0]         trajState    // mode-specific progress (for debug / ML)
);

  localparam int FX = 1 << FIXED_SHIFT;

  // ---------------------------------------------------------------- sine source
  logic [11:0] phase;                 // 1/16 table entries
  logic [15:0] sineQ;
  logic signed [7:0] sine;

  sintable #(.COUNT_SIZE(8)) sineTable (
      .clk   (clk),
      .resetN(resetN),
      .ADDR  (phase[11:4]),
      .volume(1'b1),                  // keeps the table at full scale
      .Q     (sineQ)
  );

  // At full volume Q = {s, table[7:0], {7{s}}}, so Q[14:7] is the signed sample (+-127).
  assign sine = sineQ[14:7];

  // ---------------------------------------------------------------- state
  logic signed [17:0] posFx;
  logic signed [17:0] nextPosFx;

  assign nextPosFx = (18'(BIRD_Y_CENTER) + 18'(sine)) <<< FIXED_SHIFT;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      phase  <= '0;
      posFx  <= 18'(BIRD_Y_CENTER * FX);
      birdVy <= '0;
    end else if (restart) begin
      phase  <= '0;
      posFx  <= 18'(BIRD_Y_CENTER * FX);
      birdVy <= '0;
    end else if (tick && run) begin
      phase  <= phase + 12'(EASY_PHASE_STEP);
      posFx  <= nextPosFx;
      birdVy <= 12'(nextPosFx - posFx);
    end else if (tick) begin
      birdVy <= '0;
    end
  end

  assign birdY     = 11'(posFx >>> FIXED_SHIFT);
  assign trajState = phase[11:4];

endmodule
