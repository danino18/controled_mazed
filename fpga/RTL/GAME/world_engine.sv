// The part of the game world that does not depend on the player: the bird's
// autonomous motion, the coral columns' horizontal motion and their random
// openings, and the two random streams behind them.
//
// Given the same seed, settings and tick sequence it always produces the same
// world. The visible game (game_logic) uses one world_engine; the on-chip
// trainer uses one world_engine shared by all of its lanes, so every candidate
// in a run sees exactly the same world.

module world_engine
  import game_params_pkg::*;
#(
    parameter int FIRST_X = CORAL_FIRST_X
) (
    input  logic                         clk,
    input  logic                         resetN,
    input  logic                         tickMove,
    input  logic                         tickCheck,

    input  logic                         seedLoad,     // load the round seed (one clock before restart)
    input  logic [15:0]                  seed,
    input  logic                         restart,      // new round: place the bird and the columns
    input  logic                         birdReset,    // return only the bird to its start
    input  logic                         birdRun,      // bird advances on tickMove
    input  logic                         worldRun,     // columns advance on tickMove, passes count
    input  logic [1:0]                   birdMode,     // DIFF_EASY / DIFF_MEDIUM / DIFF_HARD
    input  logic [1:0]                   columnCount,  // 1..3
    input  logic [11:0]                  worldStep,    // 1/64 px per frame

    output logic signed [10:0]           birdY,
    output logic signed [11:0]           birdVy,
    output logic [7:0]                   birdTrajState,
    output logic [NUM_COLUMNS-1:0]       colActive,
    output logic [NUM_COLUMNS-1:0][10:0] colX,
    output logic [NUM_COLUMNS-1:0][8:0]  gapBase,
    output logic                         passPulse     // one column passed the bird
);

  // The coral and the bird use separate streams derived from the one seed.
  logic [15:0] worldRnd;
  logic [15:0] birdRnd;

  lfsr_rng worldRng (
      .clk     (clk),
      .resetN  (resetN),
      .step    (tickMove),
      .seedLoad(seedLoad),
      .seed    (seed),
      .rnd     (worldRnd)
  );

  lfsr_rng birdRng (
      .clk     (clk),
      .resetN  (resetN),
      .step    (tickMove),
      .seedLoad(seedLoad),
      .seed    ({seed[7:0], seed[15:8]} ^ 16'h5A5A),
      .rnd     (birdRnd)
  );

  bird_trajectory bird (
      .clk      (clk),
      .resetN   (resetN),
      .tick     (tickMove),
      .run      (birdRun),
      .restart  (restart || birdReset),
      .mode     (birdMode),
      .rnd      (birdRnd),
      .birdY    (birdY),
      .birdVy   (birdVy),
      .trajState(birdTrajState)
  );

  column_track #(.FIRST_X(FIRST_X)) columns (
      .clk        (clk),
      .resetN     (resetN),
      .tickMove   (tickMove),
      .tickCheck  (tickCheck),
      .run        (worldRun),
      .restart    (restart),
      .columnCount(columnCount),
      .worldStep  (worldStep),
      .rnd        (worldRnd),
      .active     (colActive),
      .colX       (colX),
      .gapBase    (gapBase),
      .passPulse  (passPulse)
  );

endmodule
