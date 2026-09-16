// All game rules, with no knowledge of pixels: game flow, bird motion, maze
// steering, coral columns, collision and score. Driven by the three per-frame
// ticks, so the same module can run behind the VGA display or be stepped much
// faster than real time by a testbench (and later by an on-chip simulator).

module game_logic
  import game_params_pkg::*, game_state_pkg::*;
#(
    parameter int READY_FRAMES     = 88,
    parameter int HIT_FRAMES       = 51,
    parameter int OVER_LOCK_FRAMES = 36,
    parameter int FIRST_X          = CORAL_FIRST_X
) (
    input  logic                         clk,
    input  logic                         resetN,
    input  logic                         tickMove,
    input  logic                         tickCheck,
    input  logic                         tickState,

    // keyboard
    input  logic                         upHeld,
    input  logic                         downHeld,
    input  logic                         upPulse,
    input  logic                         downPulse,
    input  logic                         enterPulse,

    // future AI steering (see control_mux)
    input  logic                         aiMode,
    input  logic                         aiUp,
    input  logic                         aiDown,
    input  logic                         aiValid,

    // game flow
    output logic [2:0]                   screen,
    output logic [1:0]                   difficulty,
    output logic [1:0]                   columnCount,
    output logic [1:0]                   menuCursor,
    output logic [7:0]                   stateFrames,

    // world state
    output logic signed [10:0]           birdY,
    output logic signed [11:0]           birdVy,
    output logic [7:0]                   birdTrajState,
    output logic signed [9:0]            mazeOffset,
    output logic [NUM_COLUMNS-1:0]       colActive,
    output logic [NUM_COLUMNS-1:0][10:0] colX,
    output logic [NUM_COLUMNS-1:0][9:0]  gapTop,
    output logic [NUM_COLUMNS-1:0][9:0]  gapBottom,
    output logic                         collision,
    output logic [NUM_COLUMNS-1:0]       hitColumn,

    // score
    output logic [2:0][3:0]              score,
    output logic [2:0][3:0]              best,
    output logic                         newBest
);

  // ---------------------------------------------------------------- game flow
  logic roundStart;
  logic roundOver;
  logic menuStart;

  game_fsm #(
      .READY_FRAMES    (READY_FRAMES),
      .HIT_FRAMES      (HIT_FRAMES),
      .OVER_LOCK_FRAMES(OVER_LOCK_FRAMES)
  ) fsm (
      .clk        (clk),
      .resetN     (resetN),
      .tick       (tickState),
      .upPulse    (upPulse),
      .downPulse  (downPulse),
      .enterPulse (enterPulse),
      .collision  (collision),
      .state      (screen),
      .difficulty (difficulty),
      .columnCount(columnCount),
      .menuCursor (menuCursor),
      .stateFrames(stateFrames),
      .roundStart (roundStart),
      .roundOver  (roundOver),
      .menuStart  (menuStart)
  );

  logic inMenu, worldRun, steerRun, birdRun;

  assign inMenu   = (screen == ST_MENU_DIFF) || (screen == ST_MENU_OBST);
  assign worldRun = (screen == ST_PLAY);
  assign steerRun = (screen == ST_PLAY) || (screen == ST_READY);   // the player may line up the coral while getting ready
  assign birdRun  = worldRun || inMenu;                               // the bird bobs behind the menus

  // ---------------------------------------------------------------- randomness
  logic [15:0] rnd;

  lfsr_rng rng (
      .clk     (clk),
      .resetN  (resetN),
      .step    (tickMove),
      .seedLoad(1'b0),
      .seed    (16'h0000),
      .rnd     (rnd)
  );

  // ---------------------------------------------------------------- bird
  bird_trajectory bird (
      .clk      (clk),
      .resetN   (resetN),
      .tick     (tickMove),
      .run      (birdRun),
      .restart  (roundStart || menuStart),
      .mode     (inMenu ? DIFF_EASY : difficulty),
      .rnd      (rnd),
      .birdY    (birdY),
      .birdVy   (birdVy),
      .trajState(birdTrajState)
  );

  // ---------------------------------------------------------------- maze steering
  logic ctrlUp, ctrlDown;
  logic signed [4:0] mazeVy;

  control_mux steering (
      .aiMode  (aiMode),
      .kbdUp   (upHeld),
      .kbdDown (downHeld),
      .aiUp    (aiUp),
      .aiDown  (aiDown),
      .aiValid (aiValid),
      .ctrlUp  (ctrlUp),
      .ctrlDown(ctrlDown)
  );

  maze_control maze (
      .clk       (clk),
      .resetN    (resetN),
      .tick      (tickMove),
      .run       (steerRun),
      .restart   (roundStart),
      .moveUp    (ctrlUp),
      .moveDown  (ctrlDown),
      .mazeOffset(mazeOffset),
      .mazeVy    (mazeVy)
  );

  // ---------------------------------------------------------------- coral, collision, score
  logic scorePulse;

  obstacle_manager #(.FIRST_X(FIRST_X)) obstacles (
      .clk        (clk),
      .resetN     (resetN),
      .tickMove   (tickMove),
      .tickCheck  (tickCheck),
      .run        (worldRun),
      .restart    (roundStart),
      .columnCount(columnCount),
      .worldStep  (12'(WORLD_STEP_DEFAULT)),
      .mazeOffset (mazeOffset),
      .rnd        (rnd),
      .active     (colActive),
      .colX       (colX),
      .gapTop     (gapTop),
      .gapBottom  (gapBottom),
      .scorePulse (scorePulse)
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

  score_bcd scoring (
      .clk       (clk),
      .resetN    (resetN),
      .clearScore(roundStart),
      .addPoint  (scorePulse),
      .commitBest(roundOver),
      .score     (score),
      .best      (best),
      .newBest   (newBest)
  );

endmodule
