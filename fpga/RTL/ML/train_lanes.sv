// The parallel training simulator: one shared world and LANES candidate lanes.
//
// The world (bird and columns) does not depend on the player, so every lane
// reads the same world_engine: all candidates of a run play exactly the same
// world, which is the fairness of a batch by construction. Each lane has its
// own maze, collision, network datapath and counters (train_lane). One
// nn_sched drives every lane's datapath, and one weight memory word holds
// gene g of all lanes (8 bits per lane), so one read serves them all.
//
// A run: runStart loads the seed; one clock later the world and the lanes
// restart; then READY_STEPS frozen GET READY steps (only the random streams
// advance, the networks already evaluate), then PLAY steps until no enabled
// lane is alive and not done. This is the sequence game_logic follows in
// WATCH AI, and every step is ordered as the game's frame:
//
//   ph 0      tickMove    world and mazes move (the mazes by the last action)
//   ph 1      tickCheck   collisions and passes
//   ph 2      tickState   alive, gates, steps, death picture
//   ph 3      world features
//   ph 4      lane features
//   ph 5      network start; centred-step counter
//   ph 44     new actions
//   ph 47     end of step: run end / READY -> PLAY
//
// A step starts only when the throttle allows it (stepGo). Between steps the
// display may take its snapshot (snapGrant, at most STEP_CLOCKS clocks after
// the request); the simulator never waits for the video otherwise.

module train_lanes
  import game_params_pkg::*, ml_pkg::*;
#(
    parameter int T_LIMIT = T_MAX
) (
    input  logic                                 clk,
    input  logic                                 resetN,

    // training world (latched when training starts)
    input  logic [1:0]                           difficulty,
    input  logic [1:0]                           columnCount,
    input  logic [2:0]                           speedLevel,

    // run control
    input  logic                                 runStart,     // one clock: load runSeed and start a run
    input  logic [15:0]                          runSeed,
    input  logic [LANES-1:0]                     laneEnable,   // lanes playing the run (taken on runStart)
    input  logic                                 stageClear,   // clear the lane accumulators
    input  logic                                 abort,        // stop the run at once (no runDone)
    input  logic                                 stepGo,       // throttle: a step may start
    input  logic                                 hold,         // do not start new steps
    input  logic                                 snapReq,
    output logic                                 snapGrant,    // one clock, between steps
    output logic                                 running,
    output logic                                 runDone,      // one clock: the run has ended
    output logic                                 stepStart,    // one clock per started step
    output logic                                 playing,
    output logic [11:0]                          playSteps,    // PLAY steps of this run
    output logic [6:0]                           readySteps,   // GET READY steps done

    // lane weight memory: word g = gene g of lanes 7..0
    input  logic                                 wWe,
    input  logic [GENE_ADDR_W-1:0]               wAddr,
    input  logic [LANES*8-1:0]                   wData,

    // lanes
    output logic [LANES-1:0]                     enabled,
    output logic [LANES-1:0]                     alive,
    output logic [LANES-1:0]                     done,
    output logic [LANES-1:0][1:0]                act,
    output logic [LANES-1:0][11:0]               runT,
    output logic [LANES-1:0][9:0]                accG,
    output logic [LANES-1:0][15:0]               accTA,
    output logic [LANES-1:0][14:0]               accT,
    output logic [LANES-1:0][3:0]                accW,
    output logic [LANES-1:0][10:0]               viewBirdY,
    output logic [LANES-1:0][NUM_COLUMNS-1:0]    viewActive,
    output logic [LANES-1:0][NUM_COLUMNS*11-1:0] viewColX,
    output logic [LANES-1:0][NUM_COLUMNS*10-1:0] viewGapTop,

    // for tests
    output logic [LANES-1:0][9:0]                mazeOffset,
    output logic [LANES-1:0]                     collision,
    output logic                                 tickStateOut,
    output logic signed [10:0]                   worldBirdY,
    output logic [NUM_COLUMNS-1:0][10:0]         worldColX
);

  // ---------------------------------------------------------------- step sequencer
  logic       busy;
  logic [5:0] ph;
  logic       restart;
  logic       restartD;
  logic       anyActive;

  // no snapshot while a run is being set up (new seed, restart, first picture)
  assign snapGrant = snapReq && !busy && !runStart && !restart && !restartD;
  assign stepStart = !busy && running && stepGo && !hold && !snapReq && !restart;

  logic tickMove, tickCheck, tickState, sampleW, sampleL, nnStart, stepEnd;

  assign tickMove  = busy && ph == 6'd0;
  assign tickCheck = busy && ph == 6'd1;
  assign tickState = busy && ph == 6'd2;
  assign sampleW   = busy && ph == 6'd3;
  assign sampleL   = busy && ph == 6'd4;
  assign nnStart   = busy && ph == 6'd5;
  assign stepEnd   = busy && ph == 6'(STEP_CLOCKS - 1);

  assign tickStateOut = tickState;
  assign anyActive    = |(enabled & alive & ~done);

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      busy       <= 1'b0;
      ph         <= '0;
      running    <= 1'b0;
      restart    <= 1'b0;
      restartD   <= 1'b0;
      runDone    <= 1'b0;
      playing    <= 1'b0;
      playSteps  <= '0;
      readySteps <= '0;
    end else begin
      restart  <= runStart;
      restartD <= restart;
      runDone  <= 1'b0;

      if (abort) begin
        busy    <= 1'b0;
        ph      <= '0;
        running <= 1'b0;
        restart <= 1'b0;
      end else if (runStart) begin
        busy       <= 1'b0;
        ph         <= '0;
        running    <= 1'b1;
        playing    <= 1'b0;
        playSteps  <= '0;
        readySteps <= '0;
      end else if (stepStart) begin
        busy <= 1'b1;
        ph   <= '0;
      end else if (busy) begin
        ph <= ph + 6'd1;
        if (tickMove && playing) playSteps <= playSteps + 12'd1;
        if (stepEnd) begin
          busy <= 1'b0;
          if (!playing) begin
            readySteps <= readySteps + 7'd1;
            if (readySteps == 7'(READY_STEPS - 1)) playing <= 1'b1;
          end else if (!anyActive || playSteps == 12'(T_LIMIT)) begin
            running <= 1'b0;
            runDone <= 1'b1;
          end
        end
      end
    end
  end

  // ---------------------------------------------------------------- shared world
  logic signed [10:0]           birdY;
  logic signed [11:0]           birdVy;
  logic [NUM_COLUMNS-1:0]       colActive;
  logic [NUM_COLUMNS-1:0][10:0] colX;
  logic [NUM_COLUMNS-1:0][8:0]  gapBase;
  logic                         passPulse;
  logic [11:0]                  worldStep;

  assign worldStep  = 12'(WORLD_STEP_BASE) + 12'(WORLD_STEP_INCREMENT) * 12'(speedLevel);
  assign worldBirdY = birdY;
  assign worldColX  = colX;

  world_engine world (
      .clk          (clk),
      .resetN       (resetN),
      .tickMove     (tickMove),
      .tickCheck    (tickCheck),
      .seedLoad     (runStart),
      .seed         (runSeed),
      .restart      (restart),
      .birdReset    (1'b0),
      .birdRun      (playing),
      .worldRun     (playing),
      .birdMode     (difficulty),
      .columnCount  (columnCount),
      .worldStep    (worldStep),
      .birdY        (birdY),
      .birdVy       (birdVy),
      .birdTrajState(),
      .colActive    (colActive),
      .colX         (colX),
      .gapBase      (gapBase),
      .passPulse    (passPulse)
  );

  logic [1:0]         next1, next2;
  logic               vis1, use2;
  logic [6:0]         tau;
  logic signed [10:0] birdC;
  logic signed [11:0] birdVyW;

  feature_world worldFeatures (
      .clk(clk), .resetN(resetN), .sample(sampleW),
      .birdY(birdY), .birdVy(birdVy), .colActive(colActive), .colX(colX), .speedLevel(speedLevel),
      .next1(next1), .next2(next2), .vis1(vis1), .use2(use2), .tau(tau),
      .birdC(birdC), .birdVyOut(birdVyW));

  // ---------------------------------------------------------------- shared network schedule and weights
  logic [GENE_ADDR_W-1:0] geneAddr;
  logic                   opLoad, opAdd, latchH, decide;
  logic [3:0]             inSel;
  logic [2:0]             hIdx;
  logic [LANES*8-1:0]     genes;

  nn_sched sched (
      .clk(clk), .resetN(resetN), .start(nnStart), .geneAddr(geneAddr),
      .opLoad(opLoad), .opAdd(opAdd), .inSel(inSel), .latchH(latchH), .hIdx(hIdx),
      .decide(decide), .busy());

  altsyncram #(
      .operation_mode        ("DUAL_PORT"),
      .width_a               (LANES * 8),
      .widthad_a             (GENE_ADDR_W),
      .numwords_a            (1 << GENE_ADDR_W),
      .width_b               (LANES * 8),
      .widthad_b             (GENE_ADDR_W),
      .numwords_b            (1 << GENE_ADDR_W),
      .address_reg_b         ("CLOCK0"),
      .outdata_reg_b         ("UNREGISTERED"),
      .outdata_aclr_b        ("NONE"),
      .intended_device_family("Cyclone V"),
      .lpm_type              ("altsyncram"),
      .power_up_uninitialized("FALSE"),
      .read_during_write_mode_mixed_ports("DONT_CARE"),
      .ram_block_type        ("M10K")
  ) laneWeights (
      .clock0        (clk),
      .wren_a        (wWe),
      .address_a     (wAddr),
      .data_a        (wData),
      .address_b     (geneAddr),
      .q_b           (genes),
      .aclr0         (1'b0),
      .aclr1         (1'b0),
      .addressstall_a(1'b0),
      .addressstall_b(1'b0),
      .byteena_a     (1'b1),
      .byteena_b     (1'b1),
      .clock1        (1'b1),
      .clocken0      (1'b1),
      .clocken1      (1'b1),
      .clocken2      (1'b1),
      .clocken3      (1'b1),
      .data_b        ({(LANES * 8){1'b1}}),
      .eccstatus     (),
      .q_a           (),
      .rden_a        (1'b1),
      .rden_b        (1'b1),
      .wren_b        (1'b0)
  );

  // ---------------------------------------------------------------- lanes
  // laneEnable is taken with the seed, one clock before the lanes restart
  logic [LANES-1:0] laneEnableHeld;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN)       laneEnableHeld <= '0;
    else if (runStart) laneEnableHeld <= laneEnable;
  end

  genvar k;
  generate
    for (k = 0; k < LANES; k++) begin : lane
      logic signed [10:0]           vBirdY;
      logic [NUM_COLUMNS-1:0][10:0] vColX;
      logic [NUM_COLUMNS-1:0][9:0]  vGapTop;
      logic signed [9:0]            offset;

      train_lane #(.T_LIMIT(T_LIMIT)) unit (
          .clk       (clk),
          .resetN    (resetN),
          .restart   (restart),
          .enableIn  (laneEnableHeld[k]),
          .stageClear(stageClear),
          .viewUpdate(tickState || restartD),
          .tickMove  (tickMove),
          .tickCheck (tickCheck),
          .tickState (tickState),
          .sampleL   (sampleL),
          .countA    (nnStart),
          .playing   (playing),
          .birdY     (birdY),
          .colActive (colActive),
          .colX      (colX),
          .gapBase   (gapBase),
          .passPulse (passPulse),
          .next1     (next1),
          .next2     (next2),
          .vis1      (vis1),
          .use2      (use2),
          .tau       (tau),
          .birdC     (birdC),
          .birdVyW   (birdVyW),
          .gene      (genes[k * 8 +: 8]),
          .opLoad    (opLoad),
          .opAdd     (opAdd),
          .inSel     (inSel),
          .latchH    (latchH),
          .hIdx      (hIdx),
          .decide    (decide),
          .enabled   (enabled[k]),
          .alive     (alive[k]),
          .done      (done[k]),
          .act       (act[k]),
          .runT      (runT[k]),
          .accG      (accG[k]),
          .accTA     (accTA[k]),
          .accT      (accT[k]),
          .accW      (accW[k]),
          .viewBirdY (vBirdY),
          .viewActive(viewActive[k]),
          .viewColX  (vColX),
          .viewGapTop(vGapTop),
          .mazeOffset(offset),
          .collision (collision[k]),
          .feat      ()
      );

      assign viewBirdY[k]  = vBirdY;
      assign viewColX[k]   = vColX;
      assign viewGapTop[k] = vGapTop;
      assign mazeOffset[k] = offset;
    end
  endgenerate

endmodule
