// One training lane: one candidate network playing the shared world.
//
// It is the player half of the game (lane_engine: maze, openings, collision),
// the player half of the network inputs (feature_lane), its own network
// datapath and the counters the fitness is built from. The world (bird and
// columns) and the network scheduler are shared by all lanes (train_lanes).
//
// Per PLAY step, if the lane is alive and not done (on tickState):
//   runT, accT, accTA += 1           a step begun alive (the death step counts)
//   accG += 1 on a pass              a pass on the death step counts, as in the game
//   collision -> alive = 0           the maze, the network and the counters freeze
//   runT reaches T_LIMIT -> done     the run is completed (accW += 1)
// and on countA, if the step ended alive with the next column on screen and
// the bird within ALIGN_TOL of its opening centre: accTA += 1.
//
// fitness = {accG, accTA}: one more gate always beats any amount of survival.
// The acc* counters add up over the runs of a stage and are cleared by stageClear.
//
// The view registers follow the lane's picture (bird, columns, openings) at
// every step while the lane is alive, so after a death they hold exactly the
// picture of the death step.

module train_lane
  import game_params_pkg::*, ml_pkg::*;
#(
    parameter int T_LIMIT = T_MAX
) (
    input  logic                         clk,
    input  logic                         resetN,

    // run control (train_lanes)
    input  logic                         restart,      // new run: centre the maze, clear the run counters
    input  logic                         enableIn,     // this lane plays the run (taken on restart)
    input  logic                         stageClear,   // new batch or stage: clear the accumulators
    input  logic                         viewUpdate,   // copy the picture (if alive)
    input  logic                         tickMove,
    input  logic                         tickCheck,
    input  logic                         tickState,
    input  logic                         sampleL,
    input  logic                         countA,
    input  logic                         playing,      // PLAY step (otherwise GET READY)

    // shared world
    input  logic signed [10:0]           birdY,
    input  logic [NUM_COLUMNS-1:0]       colActive,
    input  logic [NUM_COLUMNS-1:0][10:0] colX,
    input  logic [NUM_COLUMNS-1:0][8:0]  gapBase,
    input  logic                         passPulse,

    // shared world features
    input  logic [1:0]                   next1,
    input  logic [1:0]                   next2,
    input  logic                         vis1,
    input  logic                         use2,
    input  logic [6:0]                   tau,
    input  logic signed [10:0]           birdC,
    input  logic signed [11:0]           birdVyW,

    // network: this lane's gene and the shared scheduler's controls
    input  logic [7:0]                   gene,
    input  logic                         opLoad,
    input  logic                         opAdd,
    input  logic [3:0]                   inSel,
    input  logic                         latchH,
    input  logic [2:0]                   hIdx,
    input  logic                         decide,

    output logic                         enabled,
    output logic                         alive,
    output logic                         done,
    output logic [1:0]                   act,
    output logic [11:0]                  runT,
    output logic [9:0]                   accG,
    output logic [15:0]                  accTA,
    output logic [14:0]                  accT,
    output logic [3:0]                   accW,

    output logic signed [10:0]           viewBirdY,
    output logic [NUM_COLUMNS-1:0]       viewActive,
    output logic [NUM_COLUMNS-1:0][10:0] viewColX,
    output logic [NUM_COLUMNS-1:0][9:0]  viewGapTop,

    // for tests
    output logic signed [9:0]            mazeOffset,
    output logic                         collision,
    output logic [NN_INPUTS-1:0][7:0]    feat
);

  logic steering;
  assign steering = playing && alive && !done;

  // ---------------------------------------------------------------- game rules (the player's part)
  logic signed [4:0]            mazeVy;
  logic [NUM_COLUMNS-1:0][9:0]  gapTop;

  lane_engine rules (
      .clk       (clk),
      .resetN    (resetN),
      .tickMove  (tickMove),
      .tickCheck (tickCheck),
      .steerRun  (steering),
      .restart   (restart),
      .moveUp    (steering && act[1]),
      .moveDown  (steering && act[0]),
      .birdY     (birdY),
      .colActive (colActive),
      .colX      (colX),
      .gapBase   (gapBase),
      .mazeOffset(mazeOffset),
      .mazeVy    (mazeVy),
      .gapTop    (gapTop),
      .gapBottom (),
      .collision (collision),
      .hitColumn ()
  );

  // ---------------------------------------------------------------- network
  logic aligned;

  feature_lane features (
      .clk(clk), .resetN(resetN), .sample(sampleL),
      .next1(next1), .next2(next2), .vis1(vis1), .use2(use2), .tau(tau),
      .birdC(birdC), .birdVy(birdVyW), .gapTop(gapTop), .mazeVy(mazeVy),
      .feat(feat), .aligned(aligned), .eNext());

  nn_datapath network (
      .clk(clk), .resetN(resetN), .enable(alive && !done), .clear(restart),
      .gene(gene), .feat(feat),
      .opLoad(opLoad), .opAdd(opAdd), .inSel(inSel), .latchH(latchH), .hIdx(hIdx), .decide(decide),
      .act(act), .y(), .hidden());

  // ---------------------------------------------------------------- life and fitness counters
  logic counted;     // this PLAY step began alive
  logic endedAlive;  // ... and ended alive (may count as centred)

  assign counted = tickState && playing && alive && !done;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      enabled    <= 1'b0;
      alive      <= 1'b0;
      done       <= 1'b0;
      runT       <= '0;
      accG       <= '0;
      accTA      <= '0;
      accT       <= '0;
      accW       <= '0;
      endedAlive <= 1'b0;
    end else begin
      if (stageClear) begin
        accG  <= '0;
        accTA <= '0;
        accT  <= '0;
        accW  <= '0;
      end

      if (restart) begin
        enabled    <= enableIn;
        alive      <= enableIn;
        done       <= 1'b0;
        runT       <= '0;
        endedAlive <= 1'b0;
      end else begin
        if (tickState) endedAlive <= counted && !collision;

        if (counted) begin
          runT  <= runT + 12'd1;
          accT  <= accT + 15'd1;
          accTA <= accTA + 16'd1;
          if (passPulse) accG <= accG + 10'd1;
          if (collision) begin
            alive <= 1'b0;
          end else if (runT == 12'(T_LIMIT - 1)) begin
            done <= 1'b1;
            accW <= accW + 4'd1;
          end
        end

        if (countA && endedAlive && aligned) accTA <= accTA + 16'd1;
      end
    end
  end

  // ---------------------------------------------------------------- picture
  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      viewBirdY  <= 11'(BIRD_Y_CENTER);
      viewActive <= '0;
      viewColX   <= '0;
      viewGapTop <= '0;
    end else if (viewUpdate && alive) begin
      viewBirdY  <= birdY;
      viewActive <= colActive;
      viewColX   <= colX;
      viewGapTop <= gapTop;
    end
  end

endmodule
