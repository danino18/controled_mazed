// The training lanes follow exactly the rules of the visible game.
//
// train_lanes (8 lanes, 8 different networks, one shared world) is compared
// with 8 separate copies of the visible game (game_logic) played by WATCH AI
// (ai_player) with the same networks, the same seed and the same settings,
// in all nine difficulty/column modes at world speeds 0, 3 and 7.
//
// For every lane and every PLAY step it began alive, the maze offset and the
// collision flag must equal the game's; the death step must be the game's
// crash frame; the gates must equal the game's score; the steps, centred
// steps and completed runs must equal a count taken from the game.
//
// Also checked:
//   - independence: lane 0 plays the same network in two runs whose other
//     lanes play different networks, and its trace is identical
//   - a dead lane is frozen: maze, action, counters and picture never change
//     again in that run; the run ends on the step the last lane dies
//   - idle lanes (not enabled) are never alive, keep zero counters and HOLD
//   - the accumulators add up over two runs and are cleared by stageClear
`timescale 1ns / 1ps

// One visible game played by WATCH AI, with its own frame ticks.
module lane_equiv_ref
  import game_params_pkg::*, game_state_pkg::*, ml_pkg::*;
#(
    parameter int CLOCKS_PER_FRAME = 64
) (
    input  logic                         clk,
    input  logic                         resetN,
    input  logic                         autoStart,
    input  logic [1:0]                   autoDifficulty,
    input  logic [1:0]                   autoColumns,
    input  logic                         abort,
    input  logic                         speedLoad,
    input  logic [2:0]                   speedLoadLevel,
    input  logic                         netWe,
    input  logic [5:0]                   netWa,
    input  logic [7:0]                   netWd,
    output logic                         tickState,
    output logic [2:0]                   screen,
    output logic signed [9:0]            mazeOffset,
    output logic                         collision,
    output logic [2:0][3:0]              score,
    output logic signed [10:0]           birdY,
    output logic [NUM_COLUMNS-1:0]       colActive,
    output logic [NUM_COLUMNS-1:0][10:0] colX,
    output logic [NUM_COLUMNS-1:0][9:0]  gapTop
);

  int   phase = 0;
  logic tickMove, tickCheck;
  always @(posedge clk) phase <= (phase + 1) % CLOCKS_PER_FRAME;
  assign tickMove  = resetN && (phase == 0);
  assign tickCheck = resetN && (phase == 1);
  assign tickState = resetN && (phase == 2);

  logic signed [11:0]           birdVy;
  logic signed [4:0]            mazeVy;
  logic [NUM_COLUMNS-1:0][8:0]  gapBase;
  logic [2:0]                   speedLevel;
  logic                         aiUp, aiDown, aiValid;

  game_logic #(.READY_FRAMES(READY_STEPS), .HIT_FRAMES(4), .OVER_LOCK_FRAMES(1)) game (
      .clk(clk), .resetN(resetN), .tickMove(tickMove), .tickCheck(tickCheck), .tickState(tickState),
      .upHeld(1'b0), .downHeld(1'b0), .upPulse(1'b0), .downPulse(1'b0),
      .enterPulse(1'b0), .speedUpHeld(1'b0), .speedDownHeld(1'b0), .entropyPulse(1'b0),
      .aiMode(1'b1), .aiUp(aiUp), .aiDown(aiDown), .aiValid(aiValid),
      .trainMode(1'b0), .autoStart(autoStart), .autoDifficulty(autoDifficulty),
      .autoColumns(autoColumns), .abort(abort),
      .speedLoad(speedLoad), .speedLoadLevel(speedLoadLevel), .trainStart(),
      .screen(screen), .difficulty(), .columnCount(), .menuCursor(), .stateFrames(),
      .birdY(birdY), .birdVy(birdVy), .birdTrajState(), .mazeOffset(mazeOffset), .mazeVy(mazeVy),
      .colActive(colActive), .colX(colX), .gapBase(gapBase), .gapTop(gapTop), .gapBottom(),
      .collision(collision), .hitColumn(), .score(score), .best(), .newBest(),
      .speedLevel(speedLevel), .scoreEvent(), .failEvent());

  ai_player #(.NET_FILE("RTL/MIF/nn_demo.mif")) ai (
      .clk(clk), .resetN(resetN), .enable(1'b1), .tickState(tickState),
      .birdY(birdY), .birdVy(birdVy), .colActive(colActive), .colX(colX), .gapTop(gapTop),
      .mazeVy(mazeVy), .speedLevel(speedLevel),
      .netWe(netWe), .netWa(netWa), .netWd(netWd),
      .aiUp(aiUp), .aiDown(aiDown), .aiValid(aiValid), .feat(), .y(), .h0());

endmodule

module tb_lane_equiv;
  import game_params_pkg::*, game_state_pkg::*, ml_pkg::*;

  localparam int TL = 1200;     // steps after which a run counts as completed (T_MAX on the board)

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------- trainer lanes
  logic [1:0]               difficulty = '0, columnCount = 2'd1;
  logic [2:0]               speedLevel = '0;
  logic                     runStart = 1'b0, stageClear = 1'b0, abortRun = 1'b0;
  logic [15:0]              runSeed = '0;
  logic [LANES-1:0]         laneEnable = '1;
  logic                     running, runDone, stepStart, playing, snapGrant, tickStateT;
  logic [11:0]              playSteps;
  logic [6:0]               readySteps;
  logic                     wWe = 1'b0;
  logic [5:0]               wAddr = '0;
  logic [LANES*8-1:0]       wData = '0;
  logic [LANES-1:0]         enabled, alive, done, collision;
  logic [LANES-1:0][1:0]    act;
  logic [LANES-1:0][11:0]   runT;
  logic [LANES-1:0][9:0]    accG;
  logic [LANES-1:0][15:0]   accTA;
  logic [LANES-1:0][14:0]   accT;
  logic [LANES-1:0][3:0]    accW;
  logic [LANES-1:0][10:0]   viewBirdY;
  logic [LANES-1:0][2:0]    viewActive;
  logic [LANES-1:0][32:0]   viewColX;
  logic [LANES-1:0][29:0]   viewGapTop;
  logic [LANES-1:0][9:0]    mazeOffset;

  train_lanes #(.T_LIMIT(TL)) dut (
      .clk(clk), .resetN(resetN), .difficulty(difficulty), .columnCount(columnCount),
      .speedLevel(speedLevel), .runStart(runStart), .runSeed(runSeed), .laneEnable(laneEnable),
      .stageClear(stageClear), .abort(abortRun), .stepGo(1'b1), .hold(1'b0), .snapReq(1'b0),
      .snapGrant(snapGrant), .running(running), .runDone(runDone), .stepStart(stepStart),
      .playing(playing), .playSteps(playSteps), .readySteps(readySteps),
      .wWe(wWe), .wAddr(wAddr), .wData(wData),
      .enabled(enabled), .alive(alive), .done(done), .act(act), .runT(runT),
      .accG(accG), .accTA(accTA), .accT(accT), .accW(accW),
      .viewBirdY(viewBirdY), .viewActive(viewActive), .viewColX(viewColX), .viewGapTop(viewGapTop),
      .mazeOffset(mazeOffset), .collision(collision), .tickStateOut(tickStateT),
      .worldBirdY(), .worldColX());

  // ---------------------------------------------------------------- reference games
  logic                    refStart = 1'b0, refAbort = 1'b0, refSpeedLoad = 1'b0, refWe = 1'b0;
  logic [5:0]              refWa = '0;
  logic [LANES-1:0][7:0]   refWd = '0;
  logic [LANES-1:0]        refTick;
  logic [LANES-1:0][2:0]   refScreen;
  logic [LANES-1:0][9:0]   refOffset;
  logic [LANES-1:0]        refCollision;
  logic [LANES-1:0][11:0]  refScore;
  logic [LANES-1:0][10:0]  refBirdY;
  logic [LANES-1:0][2:0]   refActive;
  logic [LANES-1:0][32:0]  refColX;
  logic [LANES-1:0][29:0]  refGapTop;
  logic [15:0]             forcedSeed = 16'h0001;

  genvar r;
  generate
    for (r = 0; r < LANES; r++) begin : ref_game
      logic signed [9:0]            off;
      logic [2:0][3:0]              sc;
      logic signed [10:0]           by;
      logic [NUM_COLUMNS-1:0][10:0] cx;
      logic [NUM_COLUMNS-1:0][9:0]  gt;

      lane_equiv_ref game (
          .clk(clk), .resetN(resetN), .autoStart(refStart), .autoDifficulty(difficulty),
          .autoColumns(columnCount), .abort(refAbort), .speedLoad(refSpeedLoad),
          .speedLoadLevel(speedLevel), .netWe(refWe), .netWa(refWa), .netWd(refWd[r]),
          .tickState(refTick[r]), .screen(refScreen[r]), .mazeOffset(off),
          .collision(refCollision[r]), .score(sc), .birdY(by), .colActive(refActive[r]),
          .colX(cx), .gapTop(gt));

      assign refOffset[r] = off;
      assign refScore[r]  = sc;
      assign refBirdY[r]  = by;
      assign refColX[r]   = cx;
      assign refGapTop[r] = gt;

      initial force game.game.entropy = forcedSeed;   // the round seed comes from the test
    end
  endgenerate

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 30) $display("FAIL: %s", msg);
  endtask

  // ---------------------------------------------------------------- networks
  logic [7:0] pop [4096];
  initial $readmemh("RTL/MIF/pop_init.hex", pop);

  int laneSlot [LANES];

  task automatic load_networks(input int slots [LANES]);
    laneSlot = slots;
    for (int g = 0; g < 64; g++) begin
      @(negedge clk);
      wWe   = 1'b1;
      refWe = 1'b1;
      wAddr = 6'(g);
      refWa = 6'(g);
      for (int k = 0; k < LANES; k++) begin
        wData[k * 8 +: 8] = (g < NN_GENES) ? pop[slots[k] * 64 + g] : 8'h00;
        refWd[k]          = (g < NN_GENES) ? pop[slots[k] * 64 + g] : 8'h00;
      end
    end
    @(negedge clk);
    wWe   = 1'b0;
    refWe = 1'b0;
  endtask

  // ---------------------------------------------------------------- traces
  // one entry per PLAY step begun alive: {collision, maze offset}
  int  trainTrace [LANES][$];
  int  refTrace   [LANES][$];
  int  refG [LANES], refA [LANES];
  logic [LANES-1:0] refRecording = '0;

  function automatic bit aligned_of(input int k);
    int n1, e1;
    int x [NUM_COLUMNS];
    for (int i = 0; i < NUM_COLUMNS; i++) x[i] = int'($signed(refColX[k][i * 11 +: 11]));
    n1 = -1;
    for (int i = 0; i < NUM_COLUMNS; i++)
      if (refActive[k][i] && x[i] >= NOT_PASSED_X && (n1 < 0 || x[i] < x[n1])) n1 = i;
    if (n1 < 0 || x[n1] >= SCREEN_W) return 0;
    e1 = int'(refGapTop[k][n1 * 10 +: 10]) + GAP_H / 2 - (int'($signed(refBirdY[k])) + BIRD_HB_CENTRE);
    return e1 <= ALIGN_TOL && e1 >= -ALIGN_TOL;
  endfunction

  function automatic int bcd3(input logic [11:0] d);
    return d[11:8] * 100 + d[7:4] * 10 + d[3:0];
  endfunction

  always @(posedge clk) begin
    for (int k = 0; k < LANES; k++) begin
      if (refRecording[k] && refTick[k] && refScreen[k] == ST_PLAY && refTrace[k].size() < TL) begin
        refTrace[k].push_back({21'd0, refCollision[k], refOffset[k]});
        if (!refCollision[k] && aligned_of(k)) refA[k]++;
        if (refCollision[k] || refTrace[k].size() == TL) refRecording[k] = 0;
      end
    end
  end

  // trainer trace, dead-lane freeze and idle checks
  logic [LANES-1:0]       deadSeen;
  int                     frozenOffset [LANES];
  logic [LANES-1:0][1:0]  frozenAct;
  logic [LANES-1:0][40:0] frozenAcc;
  logic [LANES-1:0][76:0] frozenView;

  function automatic logic [76:0] view_of(input int k);
    return {viewBirdY[k], viewActive[k], viewColX[k], viewGapTop[k]};
  endfunction

  always @(posedge clk) begin
    if (tickStateT && playing) begin
      for (int k = 0; k < LANES; k++)
        if (enabled[k] && alive[k] && !done[k])
          trainTrace[k].push_back({21'd0, collision[k], mazeOffset[k]});
    end
    for (int k = 0; k < LANES; k++) begin
      if (running && playing && enabled[k] && !alive[k]) begin
        if (!deadSeen[k]) begin
          deadSeen[k]     <= 1'b1;
          frozenOffset[k] <= int'($signed(mazeOffset[k]));
          frozenAct[k]    <= act[k];
          frozenAcc[k]    <= {accG[k], accTA[k], accT[k]};
          frozenView[k]   <= view_of(k);
        end else begin
          if (int'($signed(mazeOffset[k])) != frozenOffset[k]) fail($sformatf("dead lane %0d: maze moved", k));
          if (act[k] != frozenAct[k]) fail($sformatf("dead lane %0d: action changed", k));
          if ({accG[k], accTA[k], accT[k]} != frozenAcc[k]) fail($sformatf("dead lane %0d: counters changed", k));
          if (view_of(k) != frozenView[k]) fail($sformatf("dead lane %0d: picture changed", k));
        end
      end
      if (running && playing && !enabled[k]) begin
        if (alive[k] || done[k]) fail($sformatf("idle lane %0d is alive or done", k));
        if (act[k] != ACT_HOLD) fail($sformatf("idle lane %0d has action %b", k, act[k]));
        if (runT[k] != 0) fail($sformatf("idle lane %0d counted steps", k));
      end
    end
  end

  // the run ends on the step in which the last active lane stops
  always @(posedge clk) begin
    if (runDone) begin
      if (|(enabled & alive & ~done)) fail("run ended with an active lane");
    end
  end

  // ---------------------------------------------------------------- one run
  task automatic ref_menu();
    @(negedge clk);
    refAbort = 1'b1;
    @(negedge clk);
    refAbort = 1'b0;
    repeat (70) @(negedge clk);
  endtask

  task automatic play_run(input logic [15:0] seed, input logic [LANES-1:0] enable, input bit clearAcc,
                          output int traces [LANES][$]);
    int timeout;
    for (int k = 0; k < LANES; k++) begin
      trainTrace[k].delete();
      refTrace[k].delete();
      refA[k] = 0;
      refG[k] = 0;
    end
    deadSeen = '0;

    // references: speed, seed, start on a frame tick
    @(negedge clk);
    refSpeedLoad = 1'b1;
    @(negedge clk);
    refSpeedLoad = 1'b0;
    forcedSeed = seed;
    for (int k = 0; k < LANES; k++) refRecording[k] = enable[k];
    @(negedge clk);
    refStart = 1'b1;
    wait (refScreen[0] == ST_READY);
    @(negedge clk);
    refStart = 1'b0;

    // trainer
    @(negedge clk);
    runStart   = 1'b1;
    runSeed    = seed;
    laneEnable = enable;
    stageClear = clearAcc;
    @(negedge clk);
    runStart   = 1'b0;
    stageClear = 1'b0;
    wait (running);

    timeout = 0;
    while ((running || |refRecording) && timeout < 200 * TL * 64) begin
      @(negedge clk);
      timeout++;
    end
    if (running || |refRecording) fail("run did not finish");
    repeat (5) @(negedge clk);

    for (int k = 0; k < LANES; k++) begin
      if (!enable[k]) begin
        if (trainTrace[k].size() != 0) fail($sformatf("idle lane %0d has a trace", k));
        continue;
      end
      if (trainTrace[k].size() != refTrace[k].size())
        fail($sformatf("lane %0d (net %0d): %0d steps, game %0d", k, laneSlot[k],
                       trainTrace[k].size(), refTrace[k].size()));
      for (int t = 0; t < trainTrace[k].size() && t < refTrace[k].size(); t++)
        if (trainTrace[k][t] != refTrace[k][t]) begin
          fail($sformatf("lane %0d (net %0d) step %0d: offset/collision %h, game %h", k, laneSlot[k], t,
                         trainTrace[k][t], refTrace[k][t]));
          break;
        end
    end
    traces = trainTrace;
  endtask

  // run-level counters against the game
  task automatic check_counters(input logic [LANES-1:0] enable, input int prevG [LANES], input int prevTA [LANES],
                                input int prevT [LANES], input int prevW [LANES]);
    for (int k = 0; k < LANES; k++) begin
      int steps, completed;
      if (!enable[k]) continue;
      steps     = refTrace[k].size();
      completed = (steps == TL && refTrace[k][steps - 1][10] == 1'b0);
      if (runT[k] != steps) fail($sformatf("lane %0d: runT %0d, game %0d", k, runT[k], steps));
      if (accG[k] != prevG[k] + bcd3(refScore[k]))
        fail($sformatf("lane %0d: gates %0d, game score %0d (+%0d before)", k, accG[k], bcd3(refScore[k]), prevG[k]));
      if (accT[k] != prevT[k] + steps) fail($sformatf("lane %0d: accT %0d", k, accT[k]));
      if (accTA[k] != prevTA[k] + steps + refA[k])
        fail($sformatf("lane %0d: accTA %0d, expected %0d + %0d + %0d", k, accTA[k], prevTA[k], steps, refA[k]));
      if (accW[k] != prevW[k] + completed) fail($sformatf("lane %0d: accW %0d", k, accW[k]));
      if (done[k] != completed) fail($sformatf("lane %0d: done %0d, completed %0d", k, done[k], completed));
      if (alive[k] != completed) fail($sformatf("lane %0d: alive %0d after the run", k, alive[k]));
    end
  endtask

  // ---------------------------------------------------------------- scenario
  int setA [LANES] = '{0, 9, 18, 27, 36, 45, 54, 63};     // hand-set controllers
  int setB [LANES] = '{0, 1, 2, 36, 9, 10, 11, 27};       // lane 0 as in set A, random nets mixed in
  logic [15:0] seeds [9] = '{16'h1234, 16'h0F0F, 16'h7ACE, 16'h8A3C, 16'h0001, 16'h5A5A, 16'h3C3C, 16'hF5B7, 16'h6D2B};

  initial begin
    static int speeds [3] = '{0, 3, 7};
    int traceA [LANES][$];
    int traceB [LANES][$];
    static int zero [LANES] = '{default: 0};
    int g0 [LANES], ta0 [LANES], t0 [LANES], w0 [LANES];
    int deaths, completions, totalSteps;
    string report;

    repeat (3) @(negedge clk);
    resetN = 1'b1;
    repeat (200) @(negedge clk);
    deaths = 0; completions = 0; totalSteps = 0;

    for (int s = 0; s < 3; s++) begin
      report = $sformatf("INFO: speed %0d, steps per lane:", speeds[s]);
      for (int m = 0; m < 9; m++) begin
        difficulty  = 2'(m / 3);
        columnCount = 2'(m % 3 + 1);
        speedLevel  = 3'(speeds[s]);

        load_networks((m + s) % 2 == 0 ? setA : setB);
        play_run(seeds[(m + s) % 9], '1, 1'b1, traceA);
        check_counters('1, zero, zero, zero, zero);
        report = {report, $sformatf(" %s%0d[", m / 3 == 0 ? "E" : m / 3 == 1 ? "M" : "H", m % 3 + 1)};
        for (int k = 0; k < LANES; k++) begin
          report = {report, $sformatf("%0d%s", traceA[k].size(), k < LANES - 1 ? " " : "]")};
          totalSteps += traceA[k].size();
          if (traceA[k].size() == TL && traceA[k][TL - 1][10] == 1'b0) completions++;
          else deaths++;
        end
        ref_menu();
      end
      $display("%s", report);
    end

    // independence: lane 0 plays net 0 next to two different sets of networks
    difficulty = DIFF_HARD; columnCount = 2'd2; speedLevel = 3'd5;
    load_networks(setA);
    play_run(16'h2468, '1, 1'b1, traceA);
    ref_menu();
    load_networks(setB);
    play_run(16'h2468, '1, 1'b1, traceB);
    ref_menu();
    if (traceA[0] != traceB[0]) fail("lane 0 changed when the other lanes' networks changed");
    else $display("INFO: independence: lane 0 identical (%0d steps) next to two different network sets", traceA[0].size());

    // idle lanes, then accumulation over a second run without stageClear
    difficulty = DIFF_MEDIUM; columnCount = 2'd3; speedLevel = 3'd2;
    load_networks(setA);
    play_run(16'h1111, 8'b0101_0101, 1'b1, traceA);
    check_counters(8'b0101_0101, zero, zero, zero, zero);
    for (int k = 0; k < LANES; k++) begin
      g0[k] = accG[k]; ta0[k] = accTA[k]; t0[k] = accT[k]; w0[k] = accW[k];
      if (k % 2 == 1 && (accG[k] != 0 || accTA[k] != 0 || accT[k] != 0 || accW[k] != 0))
        fail($sformatf("idle lane %0d has non-zero counters", k));
    end
    ref_menu();
    play_run(16'h2222, 8'b0101_0101, 1'b0, traceB);
    check_counters(8'b0101_0101, g0, ta0, t0, w0);
    ref_menu();
    // stageClear alone clears the accumulators
    @(negedge clk);
    stageClear = 1'b1;
    @(negedge clk);
    stageClear = 1'b0;
    @(negedge clk);
    if (|accG || |accTA || |accT || |accW) fail("stageClear did not clear the accumulators");
    $display("INFO: idle lanes and accumulation over two runs checked");

    $display("INFO: %0d lane runs died, %0d completed %0d steps; %0d lane-steps compared", deaths, completions, TL, totalSteps);
    if (deaths == 0 || completions == 0) fail("need both deaths and completed runs");

    if (errors == 0) $display("PASS: tb_lane_equiv");
    else             $display("FAIL: tb_lane_equiv (%0d errors)", errors);
    $finish;
  end

endmodule
