// The part of the game that depends on the player's (or the AI's) steering:
// the shared maze offset, the resulting coral openings, and the collision
// check against the bird. It reads the world from a world_engine.
//
// The visible game uses one lane_engine; the on-chip trainer uses one per
// training lane, all reading the same world_engine.

module lane_engine
  import game_params_pkg::*;
(
    input  logic                         clk,
    input  logic                         resetN,
    input  logic                         tickMove,
    input  logic                         tickCheck,

    input  logic                         steerRun,     // the maze may move on tickMove
    input  logic                         restart,      // centre the maze for a new round
    input  logic                         moveUp,       // same inputs as Numpad 8 / 2
    input  logic                         moveDown,

    input  logic signed [10:0]           birdY,
    input  logic [NUM_COLUMNS-1:0]       colActive,
    input  logic [NUM_COLUMNS-1:0][10:0] colX,
    input  logic [NUM_COLUMNS-1:0][8:0]  gapBase,

    output logic signed [9:0]            mazeOffset,
    output logic signed [4:0]            mazeVy,
    output logic [NUM_COLUMNS-1:0][9:0]  gapTop,
    output logic [NUM_COLUMNS-1:0][9:0]  gapBottom,
    output logic                         collision,    // updated on tickCheck
    output logic [NUM_COLUMNS-1:0]       hitColumn
);

  maze_control maze (
      .clk       (clk),
      .resetN    (resetN),
      .tick      (tickMove),
      .run       (steerRun),
      .restart   (restart),
      .moveUp    (moveUp),
      .moveDown  (moveDown),
      .mazeOffset(mazeOffset),
      .mazeVy    (mazeVy)
  );

  gap_place gaps (
      .gapBase   (gapBase),
      .mazeOffset(mazeOffset),
      .gapTop    (gapTop),
      .gapBottom (gapBottom)
  );

  collision_detect collide (
      .clk      (clk),
      .resetN   (resetN),
      .tickCheck(tickCheck),
      .birdY    (birdY),
      .active   (colActive),
      .colX     (colX),
      .gapTop   (gapTop),
      .gapBottom(gapBottom),
      .collision(collision),
      .hitColumn(hitColumn)
  );

endmodule
