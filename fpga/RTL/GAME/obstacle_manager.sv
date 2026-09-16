// State of the coral columns (logic only, no drawing).
//
// Each column has a horizontal position and a random opening centre. All
// columns share one vertical offset (mazeOffset), which is what the player
// controls, so they move up and down together. Active columns are spaced
// CORAL_WRAP_W / count apart and re-enter on the right after leaving on the left.
//
// Since M9 this is a thin wrapper: column_track holds the player-independent
// part (shared by all on-chip training lanes) and gap_place applies the
// player's offset (one per lane). The visible game uses the same two modules
// through world_engine and lane_engine.

module obstacle_manager
  import game_params_pkg::*;
#(
    parameter int FIRST_X = CORAL_FIRST_X     // left edge of the first column when a round starts
) (
    input  logic                                clk,
    input  logic                                resetN,
    input  logic                                tickMove,
    input  logic                                tickCheck,
    input  logic                                run,          // world is moving
    input  logic                                restart,      // place the columns for a new round
    input  logic [1:0]                          columnCount,  // 1..3
    input  logic [11:0]                         worldStep,    // 1/64 px per frame
    input  logic signed [9:0]                   mazeOffset,   // pixels, shared by all columns
    input  logic [15:0]                         rnd,
    output logic [NUM_COLUMNS-1:0]              active,
    output logic [NUM_COLUMNS-1:0][10:0]        colX,         // left edge of the art (signed)
    output logic [NUM_COLUMNS-1:0][9:0]         gapTop,       // first row of the opening
    output logic [NUM_COLUMNS-1:0][9:0]         gapBottom,    // first row below the opening
    output logic                                scorePulse    // one column passed the bird
);

  logic [NUM_COLUMNS-1:0][8:0] gapBase;

  column_track #(.FIRST_X(FIRST_X)) track (
      .clk        (clk),
      .resetN     (resetN),
      .tickMove   (tickMove),
      .tickCheck  (tickCheck),
      .run        (run),
      .restart    (restart),
      .columnCount(columnCount),
      .worldStep  (worldStep),
      .rnd        (rnd),
      .active     (active),
      .colX       (colX),
      .gapBase    (gapBase),
      .passPulse  (scorePulse)
  );

  gap_place gaps (
      .gapBase   (gapBase),
      .mazeOffset(mazeOffset),
      .gapTop    (gapTop),
      .gapBottom (gapBottom)
  );

endmodule
