// Training flow of train_top (M11): stop rules, final test, commit to the WATCH
// memory, and a replay of the committed champion in the visible game.
//
//   1. STOP before any champion exists: the trainer goes back to idle and
//      nothing is committed
//   2. a full run to MAX_GEN generations: final test, COMPLETE, the committed
//      AI (genes, settings, results)
//   3. replay: the committed genes play the visible game (game_logic +
//      ai_player, the WATCH AI path) on V1..V4 and on T1..T8; the scores
//      counted from those games equal the champion's validation score and the
//      final test score exactly
//   4. TRAIN AGAIN, stopped before the first validation: the old AI is kept
//   5. TRAIN AGAIN, stopped after a champion exists: reason STOPPED, the final
//      test still runs, the new champion replaces the old AI
//   6. KEY0 (reset) keeps the committed AI; a stop during the final test
//      skips the rest of the test and still commits
//   7. SOLVED: a trainer with SOLVE_STALL = 1 stops as soon as its champion
//      completed all four validation worlds and one generation passed
//   8. TRAIN AGAIN: a start while COMPLETE begins a new run at once; hold
//      (the pause menu) freezes the lanes between steps; abort keeps the AI
`timescale 1ns / 1ps

module tb_train_flow;
  import game_params_pkg::*, game_state_pkg::*, ml_pkg::*;

  localparam int TL = 400;
  localparam int FRAME_CLOCKS = 3000;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  int   frameCount = 0;
  logic frameTick;
  always @(posedge clk) frameCount <= (frameCount + 1) % FRAME_CLOCKS;
  assign frameTick = frameCount == 0;

  // ---------------------------------------------------------------- trainer under test
  logic        start = 1'b0, stop = 1'b0, abort = 1'b0, hold = 1'b0;
  logic [15:0] runIdIn = 16'h1D2E;
  logic        active, complete, aiValid, watchWe;
  logic [5:0]  watchWa;
  logic [7:0]  watchWd;
  logic [1:0]  aiDifficulty, aiColumns;
  logic [2:0]  aiSpeed;
  logic [15:0] aiRunId;
  logic [7:0]  aiGen;
  logic [3:0]  aiValW, aiTestW;
  logic [9:0]  aiValGates, aiTestGates;
  logic        aiTestValid;

  train_top #(.T_LIMIT(TL), .HOLD_RUN_FRAMES(1), .HOLD_GEN_FRAMES(1), .MAX_GEN(3), .SECOND_CLOCKS(100000)) dut (
      .clk(clk), .resetN(resetN), .start(start), .stop(stop), .abort(abort), .hold(hold), .runIdIn(runIdIn),
      .difficultyIn(2'd1), .columnsIn(2'd2), .speedIn(3'd4), .simLevel(3'd7), .frameTick(frameTick),
      .active(active), .complete(complete), .liveAlive(), .genPulse(),
      .watchWe(watchWe), .watchWa(watchWa), .watchWd(watchWd), .aiValid(aiValid),
      .aiDifficulty(aiDifficulty), .aiColumns(aiColumns), .aiSpeed(aiSpeed), .aiRunId(aiRunId), .aiGen(aiGen),
      .aiValW(aiValW), .aiValGates(aiValGates), .aiTestW(aiTestW), .aiTestGates(aiTestGates), .aiTestValid(aiTestValid),
      .histWe(), .histWa(), .histWd(), .snapTaken(), .cfgDifficulty(), .cfgColumns(), .cfgSpeed(),
      .sLaneState(), .sLaneCand(), .sLaneAct(), .sLaneGates(), .sLaneFit(), .sLaneSteps(), .sViewBirdY(),
      .sViewActive(), .sViewColX(), .sViewGapTop(), .sStage(), .sRunState(), .sWorld(), .sRunId(), .sGen(),
      .sBatch(), .sSeed(), .sPlaySteps(), .sReadySteps(), .sGenBest(), .sGenBestCand(), .sGenBestValid(),
      .sPrevBest(), .sPrevBestValid(), .sGenDone(), .sLastMean(), .sLastMeanValid(), .sValTop(), .sValTopW(),
      .sValTopSurv(), .sValTopCand(), .sValTopValid(), .sChampExists(), .sChampScore(), .sChampW(),
      .sChampSurv(), .sChampGen(), .sChampCand(), .sStall(), .sMutLevel(), .sTestScore(), .sTestW(),
      .sTestSurv(), .sTestValid(), .sDoneReason(), .sEvaluated(), .sStepsPerSec());

  // a second trainer that stops when solved
  logic solvedStart = 1'b0, solvedComplete;

  train_top #(.T_LIMIT(150), .HOLD_RUN_FRAMES(1), .HOLD_GEN_FRAMES(1), .MAX_GEN(40), .SOLVE_STALL(1),
              .SECOND_CLOCKS(100000)) solver (
      .clk(clk), .resetN(resetN), .start(solvedStart), .stop(1'b0), .abort(1'b0), .hold(1'b0), .runIdIn(16'h0707),
      .difficultyIn(2'd0), .columnsIn(2'd1), .speedIn(3'd7), .simLevel(3'd7), .frameTick(frameTick),
      .active(), .complete(solvedComplete), .liveAlive(), .genPulse(),
      .watchWe(), .watchWa(), .watchWd(), .aiValid(), .aiDifficulty(), .aiColumns(), .aiSpeed(), .aiRunId(),
      .aiGen(), .aiValW(), .aiValGates(), .aiTestW(), .aiTestGates(), .aiTestValid(),
      .histWe(), .histWa(), .histWd(), .snapTaken(), .cfgDifficulty(), .cfgColumns(), .cfgSpeed(),
      .sLaneState(), .sLaneCand(), .sLaneAct(), .sLaneGates(), .sLaneFit(), .sLaneSteps(), .sViewBirdY(),
      .sViewActive(), .sViewColX(), .sViewGapTop(), .sStage(), .sRunState(), .sWorld(), .sRunId(), .sGen(),
      .sBatch(), .sSeed(), .sPlaySteps(), .sReadySteps(), .sGenBest(), .sGenBestCand(), .sGenBestValid(),
      .sPrevBest(), .sPrevBestValid(), .sGenDone(), .sLastMean(), .sLastMeanValid(), .sValTop(), .sValTopW(),
      .sValTopSurv(), .sValTopCand(), .sValTopValid(), .sChampExists(), .sChampScore(), .sChampW(),
      .sChampSurv(), .sChampGen(), .sChampCand(), .sStall(), .sMutLevel(), .sTestScore(), .sTestW(),
      .sTestSurv(), .sTestValid(), .sDoneReason(), .sEvaluated(), .sStepsPerSec());

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 30) $display("FAIL: %s", msg);
  endtask

  logic [7:0] watchMem [64];
  int         commits = 0;
  always @(posedge clk) begin
    if (watchWe) watchMem[watchWa] <= watchWd;
    if (dut.commit) commits++;
  end

  task automatic pulse(ref logic sig);
    @(negedge clk);
    sig = 1'b1;
    @(negedge clk);
    sig = 1'b0;
  endtask

  // ---------------------------------------------------------------- replay games (the WATCH AI path)
  logic                    refStart = 1'b0, refAbort = 1'b0, refSpeedLoad = 1'b0, refWe = 1'b0;
  logic [5:0]              refWa = '0;
  logic [7:0]              refWd = '0;
  logic [7:0]              refTick;
  logic [7:0][2:0]         refScreen;
  logic [7:0]              refCollision;
  logic [7:0][11:0]        refScore;
  logic [7:0][10:0]        refBirdY;
  logic [7:0][2:0]         refActive;
  logic [7:0][32:0]        refColX;
  logic [7:0][29:0]        refGapTop;
  logic [7:0][15:0]        refSeed = '0;

  genvar r;
  generate
    for (r = 0; r < 8; r++) begin : replay
      logic [2:0][3:0]              sc;
      logic signed [10:0]           by;
      logic [NUM_COLUMNS-1:0][10:0] cx;
      logic [NUM_COLUMNS-1:0][9:0]  gt;

      lane_equiv_ref game (
          .clk(clk), .resetN(resetN), .autoStart(refStart), .autoDifficulty(aiDifficulty),
          .autoColumns(aiColumns), .abort(refAbort), .speedLoad(refSpeedLoad), .speedLoadLevel(aiSpeed),
          .netWe(refWe), .netWa(refWa), .netWd(refWd), .tickState(refTick[r]), .screen(refScreen[r]),
          .mazeOffset(), .collision(refCollision[r]), .score(sc), .birdY(by), .colActive(refActive[r]),
          .colX(cx), .gapTop(gt));

      assign refScore[r]  = sc;
      assign refBirdY[r]  = by;
      assign refColX[r]   = cx;
      assign refGapTop[r] = gt;

      initial force game.game.entropy = refSeed[r];
    end
  endgenerate

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

  // per game: PLAY frames begun (up to TL), centred frames, completion, and the
  // score taken one clock after the last counted frame (the game keeps going)
  int  refT [8], refA [8], refG [8];
  bit  refDone [8];
  logic [7:0] refRunning = '0, refCapture = '0;

  always @(posedge clk) begin
    for (int k = 0; k < 8; k++) begin
      if (refCapture[k]) begin
        refG[k] = refScore[k][11:8] * 100 + refScore[k][7:4] * 10 + refScore[k][3:0];
        refCapture[k] <= 1'b0;
      end
      if (refRunning[k] && refTick[k] && refScreen[k] == ST_PLAY) begin
        refT[k]++;
        if (!refCollision[k] && aligned_of(k)) refA[k]++;
        if (refCollision[k] || refT[k] == TL) begin
          refRunning[k] <= 1'b0;
          refCapture[k] <= 1'b1;
          refDone[k]    = !refCollision[k];
        end
      end
    end
  end

  // plays the committed genes on up to 8 seeds at once; returns {gates, T + A} summed and worlds completed
  task automatic replay_net(input logic [15:0] seeds [], output longint score, output int worlds);
    int n;
    n = seeds.size();
    for (int g = 0; g < 64; g++) begin
      @(negedge clk);
      refWe = 1'b1;
      refWa = 6'(g);
      refWd = (g < NN_GENES) ? watchMem[g] : 8'h00;
    end
    @(negedge clk);
    refWe = 1'b0;
    refSpeedLoad = 1'b1;
    for (int k = 0; k < 8; k++) refSeed[k] = (k < n) ? seeds[k] : 16'h0001;
    @(negedge clk);
    refSpeedLoad = 1'b0;
    for (int k = 0; k < 8; k++) begin refT[k] = 0; refA[k] = 0; refG[k] = 0; refDone[k] = 0; end
    refRunning = 8'hFF;
    refStart = 1'b1;
    wait (refScreen[0] == ST_READY);
    @(negedge clk);
    refStart = 1'b0;
    wait (refRunning == 8'h00);
    repeat (5) @(negedge clk);
    score = 0;
    worlds = 0;
    for (int k = 0; k < n; k++) begin
      score += longint'(refG[k]) * 65536 + refT[k] + refA[k];
      if (refDone[k]) worlds++;
    end
    // back to the first menu
    @(negedge clk);
    refAbort = 1'b1;
    @(negedge clk);
    refAbort = 1'b0;
    repeat (70) @(negedge clk);
  endtask

  initial begin
    logic [15:0] valSeeds [] = new[4];
    logic [15:0] testA [] = new[8];
    longint      score;
    int          worlds;
    logic [7:0]  savedGenes [64];
    logic [15:0] savedRun;
    int          savedGen;

    for (int i = 0; i < 4; i++) valSeeds[i] = FIXED_SEEDS[16 * i +: 16];
    for (int i = 0; i < 8; i++) testA[i] = FIXED_SEEDS[16 * (4 + i) +: 16];

    repeat (3) @(negedge clk);
    resetN = 1'b1;
    repeat (10) @(negedge clk);
    if (aiValid) fail("an AI is committed after configuration");

    // ---- 1. STOP before any champion
    pulse(start);
    repeat (2000) @(negedge clk);
    pulse(stop);
    repeat (FRAME_CLOCKS * 3) @(negedge clk);
    if (active || complete || aiValid || commits != 0) fail("stop before any champion: not idle, or something committed");
    else $display("INFO: 1. STOP before the first validation: back to idle, nothing committed");

    // ---- 2. full run to MAX_GEN
    pulse(start);
    wait (complete);
    repeat (5) @(negedge clk);
    if (commits != 1 || !aiValid) fail("run to MAX_GEN did not commit");
    if (dut.ctrl.doneReason != 2'd0 || aiGen != 8'd3) fail("reason / generations wrong");
    if (aiDifficulty != 2'd1 || aiColumns != 2'd2 || aiSpeed != 3'd4 || aiRunId != 16'h1D2E) fail("committed settings wrong");
    if (aiValGates != dut.ctrl.champScore[25:16] || aiValW != dut.ctrl.champW) fail("committed validation result wrong");
    if (!aiTestValid || aiTestGates != dut.ctrl.testScore[25:16] || aiTestW != dut.ctrl.testW) fail("committed test result wrong");
    $display("INFO: 2. MAX_GEN: champion from generation %0d: validation %0d (%0d gates, %0d/4); test %0d (%0d gates, %0d/8)",
             dut.ctrl.champGen, dut.ctrl.champScore, dut.ctrl.champScore >> 16, dut.ctrl.champW,
             dut.ctrl.testScore, dut.ctrl.testScore >> 16, dut.ctrl.testW);

    // ---- 3. replay in the visible game
    replay_net(valSeeds, score, worlds);
    if (score != dut.ctrl.champScore || worlds != dut.ctrl.champW)
      fail($sformatf("replay on V1..V4: %0d (%0d worlds), champion's validation score %0d (%0d)", score, worlds, dut.ctrl.champScore, dut.ctrl.champW));
    else $display("INFO: 3. WATCH replay on V1..V4 reproduces the validation score %0d exactly", score);
    replay_net(testA, score, worlds);
    if (score != dut.ctrl.testScore || worlds != dut.ctrl.testW)
      fail($sformatf("replay on T1..T8: %0d (%0d worlds), test score %0d (%0d)", score, worlds, dut.ctrl.testScore, dut.ctrl.testW));
    else $display("INFO: 3. WATCH replay on T1..T8 reproduces the final test score %0d exactly", score);

    // ---- 4. TRAIN AGAIN, stopped before the first validation: the old AI stays
    savedGenes = watchMem;
    savedRun = aiRunId;
    savedGen = aiGen;
    pulse(abort);
    runIdIn = 16'h2B2B;
    pulse(start);
    repeat (3000) @(negedge clk);
    pulse(stop);
    repeat (FRAME_CLOCKS * 3) @(negedge clk);
    if (active || commits != 1 || !aiValid || aiRunId != savedRun || watchMem != savedGenes)
      fail("an early stop of a new training run changed the committed AI");
    else $display("INFO: 4. TRAIN AGAIN stopped early: the previous AI (RUN %04h) is kept", aiRunId);

    // ---- 5. TRAIN AGAIN, stopped after a champion exists
    pulse(start);
    wait (dut.ctrl.champExists && dut.ctrl.runKind == 2'd0 && dut.lanes.running);
    pulse(stop);
    wait (complete);
    repeat (5) @(negedge clk);
    if (dut.ctrl.doneReason != 2'd2 || !dut.ctrl.testValid) fail("STOP: reason or test wrong");
    if (commits != 2 || aiRunId != 16'h2B2B) fail("STOP after a champion: the new AI was not committed");
    replay_net(valSeeds, score, worlds);
    if (score != dut.ctrl.champScore) fail("replay of the stopped run's champion differs");
    else $display("INFO: 5. STOP after %0d generation(s): final test ran, new AI committed and replayed", dut.ctrl.gen);

    // ---- 6. KEY0 keeps the AI; a stop during the final test skips it
    savedGenes = watchMem;
    @(negedge clk);
    resetN = 1'b0;
    repeat (20) @(negedge clk);
    resetN = 1'b1;
    repeat (10) @(negedge clk);
    if (!aiValid || aiRunId != 16'h2B2B || active) fail("KEY0 lost the committed AI or left the trainer running");
    runIdIn = 16'h3C3C;
    pulse(start);
    wait (dut.ctrl.runKind == 2'd2 && dut.lanes.running);
    pulse(stop);
    wait (complete);
    repeat (5) @(negedge clk);
    if (dut.ctrl.testValid || aiTestValid || commits != 3 || aiRunId != 16'h3C3C)
      fail("a stop during the final test: test not skipped or AI not committed");
    else $display("INFO: 6. KEY0 kept the AI; a STOP during the final test skipped it and still committed");

    // ---- 8. TRAIN AGAIN straight from COMPLETE, and the pause (hold)
    runIdIn = 16'h4D4D;
    pulse(start);
    repeat (3) @(negedge clk);
    if (complete || !active || dut.ctrl.runId != 16'h4D4D || dut.ctrl.gen != 0)
      fail("a start in COMPLETE did not begin a new run");
    wait (dut.ctrl.champExists && dut.ctrl.runKind == 2'd0 && dut.lanes.running && dut.lanes.playing);
    begin
      int steps, genBefore;
      logic [11:0] playBefore;
      @(negedge clk);
      hold = 1'b1;
      repeat (STEP_CLOCKS + 2) @(negedge clk);       // a step already started finishes
      playBefore = dut.lanes.playSteps;
      genBefore  = dut.ctrl.gen;
      steps = 0;
      repeat (FRAME_CLOCKS * 20) begin
        @(negedge clk);
        if (dut.lanes.stepStart) steps++;
      end
      if (steps != 0 || dut.lanes.playSteps != playBefore || dut.ctrl.gen != genBefore)
        fail($sformatf("hold: %0d steps started while paused", steps));
      if (dut.ctrl.runState != RS_PAUSED) fail("run state is not PAUSED");
      @(negedge clk);
      hold = 1'b0;
      repeat (STEP_CLOCKS * 4) @(negedge clk);
      if (dut.lanes.playSteps == playBefore && dut.lanes.running) fail("training did not resume after the hold");
    end
    pulse(abort);
    repeat (5) @(negedge clk);
    if (active || commits != 3 || aiRunId != 16'h3C3C) fail("abort of TRAIN AGAIN changed the committed AI");
    else $display("INFO: 8. TRAIN AGAIN from COMPLETE started a new run; the hold froze it; abort kept the AI");

    // ---- 7. SOLVED
    pulse(solvedStart);
    wait (solvedComplete);
    if (solver.ctrl.doneReason != 2'd1) fail($sformatf("solver stopped with reason %0d", solver.ctrl.doneReason));
    if (solver.ctrl.champW != 4'd4 || solver.ctrl.stall < 1) fail("SOLVED without a complete champion");
    $display("INFO: 7. SOLVED after %0d generations (champion from generation %0d completed V1..V4)",
             solver.ctrl.gen, solver.ctrl.champGen);

    if (errors == 0) $display("PASS: tb_train_flow");
    else             $display("FAIL: tb_train_flow (%0d errors)", errors);
    $finish;
  end

endmodule
