// Batch scheduler, fitness memory, top-8 list and display snapshot of the
// trainer (train_top), at MAX simulation speed with runs shortened to T_LIMIT
// steps. The genes are checked against the population memory, shadowed from
// the genetic algorithm's writes (the GA itself is checked in tb_ga).
//
// Checks, for three generations (training runs):
//   - every candidate is played exactly once per generation on world A_g and
//     once on world B_g, by the lane whose label shows it, with its own genes
//     in that lane (the lane weight memory is shadowed from its writes)
//   - A_g and B_g are training seeds (bit 15 = 0), A_g != B_g, and the worlds
//     change from one generation to the next
//   - all 8 lanes play every training run
//   - the fitness memory receives {gates, steps + centred steps} over both runs
//     for exactly the candidate the lane played
//   - the top-8 list equals a stable sort of the generation's 64 results, the
//     generation best is the first maximum, the mean survival equals
//     (sum of steps * 25) >> 17 and the evaluation counter adds up
//   - snapshots are granted only between steps, within STEP_CLOCKS clocks of the
//     request, and every displayed value equals the trainer's state at the grant
//     (a lane is shown DEAD exactly when it had died before the grant)
//   - at SIM x16 or slower, a finished run is followed by the visible pause
//   - KEY1 (abort) stops the run at once; a new start with a new RUN ID works
`timescale 1ns / 1ps

module tb_train_sched;
  import game_params_pkg::*, ml_pkg::*;

  localparam int TL = 200;
  localparam int HOLD_RUN = 3;
  localparam int HOLD_GEN = 2;
  localparam int FRAME_CLOCKS = 3000;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic        start = 1'b0, abort = 1'b0;
  logic [15:0] runIdIn = 16'h3F2C;
  logic [2:0]  simLevel = 3'd7;
  logic        frameTick;
  int          frameCount = 0;

  always @(posedge clk) frameCount <= (frameCount + 1) % FRAME_CLOCKS;
  assign frameTick = resetN && frameCount == 0;

  logic                         active, genPulse, snapTaken;
  logic [LANES-1:0]             liveAlive;
  logic [1:0]                   cfgDifficulty, cfgColumns;
  logic [2:0]                   cfgSpeed;
  logic [LANES-1:0][1:0]        sLaneState, sLaneAct;
  logic [LANES-1:0][5:0]        sLaneCand;
  logic [LANES-1:0][9:0]        sLaneGates;
  logic [LANES-1:0][25:0]       sLaneFit;
  logic [LANES-1:0][11:0]       sLaneSteps;
  logic [LANES-1:0][10:0]       sViewBirdY;
  logic [LANES-1:0][2:0]        sViewActive;
  logic [LANES-1:0][32:0]       sViewColX;
  logic [LANES-1:0][29:0]       sViewGapTop;
  logic [2:0]                   sStage, sRunState;
  logic [15:0]                  sRunId, sSeed;
  logic [7:0]                   sGen;
  logic [3:0]                   sBatch, sWorld;
  logic [11:0]                  sPlaySteps;
  logic [6:0]                   sReadySteps, sGenDone, sLastMean;
  logic [25:0]                  sGenBest;
  logic [5:0]                   sGenBestCand;
  logic                         sGenBestValid, sLastMeanValid;
  logic [31:0]                  sEvaluated;
  logic [19:0]                  sStepsPerSec;

  train_top #(.T_LIMIT(TL), .HOLD_RUN_FRAMES(HOLD_RUN), .HOLD_GEN_FRAMES(HOLD_GEN), .SECOND_CLOCKS(100000)) dut (
      .clk(clk), .resetN(resetN), .start(start), .stop(1'b0), .abort(abort), .hold(1'b0), .runIdIn(runIdIn),
      .difficultyIn(2'd1), .columnsIn(2'd3), .speedIn(3'd4), .simLevel(simLevel), .frameTick(frameTick),
      .active(active), .complete(), .liveAlive(liveAlive), .genPulse(genPulse),
      .watchWe(), .watchWa(), .watchWd(), .aiValid(), .aiDifficulty(), .aiColumns(), .aiSpeed(), .aiRunId(),
      .aiGen(), .aiValW(), .aiValGates(), .aiTestW(), .aiTestGates(), .aiTestValid(),
      .histWe(), .histWa(), .histWd(), .snapTaken(snapTaken),
      .cfgDifficulty(cfgDifficulty), .cfgColumns(cfgColumns), .cfgSpeed(cfgSpeed),
      .sLaneState(sLaneState), .sLaneCand(sLaneCand), .sLaneAct(sLaneAct), .sLaneGates(sLaneGates),
      .sLaneFit(sLaneFit), .sLaneSteps(sLaneSteps), .sViewBirdY(sViewBirdY), .sViewActive(sViewActive),
      .sViewColX(sViewColX), .sViewGapTop(sViewGapTop), .sStage(sStage), .sRunState(sRunState),
      .sWorld(sWorld), .sRunId(sRunId), .sGen(sGen), .sBatch(sBatch), .sSeed(sSeed),
      .sPlaySteps(sPlaySteps), .sReadySteps(sReadySteps), .sGenBest(sGenBest), .sGenBestCand(sGenBestCand),
      .sGenBestValid(sGenBestValid), .sPrevBest(), .sPrevBestValid(), .sGenDone(sGenDone),
      .sLastMean(sLastMean), .sLastMeanValid(sLastMeanValid),
      .sValTop(), .sValTopW(), .sValTopSurv(), .sValTopCand(), .sValTopValid(), .sChampExists(),
      .sChampScore(), .sChampW(), .sChampSurv(), .sChampGen(), .sChampCand(), .sStall(), .sMutLevel(),
      .sTestScore(), .sTestW(), .sTestSurv(), .sTestValid(), .sDoneReason(),
      .sEvaluated(sEvaluated), .sStepsPerSec(sStepsPerSec));

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 30) $display("FAIL: %s", msg);
  endtask

  // ---------------------------------------------------------------- memory shadows
  logic [7:0]  popA [4096];
  logic [7:0]  popB [4096];
  logic [63:0] laneMem [64];
  always @(posedge clk) begin
    if (dut.laneWe)    laneMem[dut.laneWa] <= dut.laneWd;
    if (dut.ctrl.weA)  popA[dut.ctrl.popWa] <= dut.ctrl.popWd;
    if (dut.ctrl.weB)  popB[dut.ctrl.popWa] <= dut.ctrl.popWd;
  end

  function automatic logic [7:0] cur_gene(input int c, input int g);
    return dut.ctrl.curIsA ? popA[c * 64 + g] : popB[c * 64 + g];
  endfunction

  // ---------------------------------------------------------------- per-generation log
  int          genIdx = 0;
  logic [15:0] genA, genB, prevA = 16'h0000;
  int          playedA [64];
  int          playedB [64];
  int          runsThisGen = 0;
  // results of the last finished run B, per candidate, in store order
  longint      storedFit [$];
  int          storedId  [$];
  longint      sumT = 0;
  int          evaluatedCount = 0;

  always @(posedge clk) begin
    if (dut.runStart && dut.ctrl.runKind == 2'd0) begin
      runsThisGen++;
      if (dut.laneEnable != '1) fail("a training run does not use all 8 lanes");
      for (int k = 0; k < LANES; k++) begin
        int c;
        c = int'(dut.ctrl.laneCand[k]);
        // lane k holds candidate c's genes
        for (int g = 0; g < NN_GENES; g++)
          if (laneMem[g][k * 8 +: 8] !== cur_gene(c, g)) begin
            fail($sformatf("gen %0d: lane %0d gene %0d = %02h, candidate %0d has %02h", genIdx, k, g,
                           laneMem[g][k * 8 +: 8], c, cur_gene(c, g)));
            break;
          end
        if (c != int'(dut.ctrl.batch) * 8 + k) fail($sformatf("lane %0d plays candidate %0d in batch %0d", k, c, dut.ctrl.batch));
        if (dut.runSeed == dut.ctrl.seedA && dut.ctrl.runIdx == 0) playedA[c]++;
        else if (dut.runSeed == dut.ctrl.seedB && dut.ctrl.runIdx == 1) playedB[c]++;
        else fail($sformatf("run with seed %04h is neither A (%04h) nor B (%04h)", dut.runSeed, dut.ctrl.seedA, dut.ctrl.seedB));
      end
    end
  end

  // fitness memory writes against the lane results
  always @(posedge clk) begin
    if (dut.ctrl.fitWe) begin
      int k;
      k = -1;
      for (int i = 0; i < LANES; i++) if (dut.ctrl.laneCand[i] == dut.ctrl.fitWa) k = i;
      if (k < 0) fail($sformatf("fitness written for candidate %0d, which no lane played", dut.ctrl.fitWa));
      else begin
        if (dut.ctrl.fitWd != {dut.lanes.accG[k], dut.lanes.accTA[k]})
          fail($sformatf("candidate %0d: fitness %0d, lane %0d has %0d", dut.ctrl.fitWa, dut.ctrl.fitWd, k,
                         {dut.lanes.accG[k], dut.lanes.accTA[k]}));
        storedFit.push_back(longint'(dut.ctrl.fitWd));
        storedId.push_back(int'(dut.ctrl.fitWa));
        sumT += dut.lanes.accT[k];
        evaluatedCount++;
      end
    end
  end

  // end of a generation
  always @(posedge clk) begin
    if (genPulse) begin
      longint sortedFit [$];
      int     sortedId [$];
      longint best;
      int     bestId;
      sortedFit.delete();
      sortedId.delete();
      // stable sort, best first
      for (int i = 0; i < storedFit.size(); i++) begin
        int pos;
        pos = 0;
        while (pos < sortedFit.size() && sortedFit[pos] >= storedFit[i]) pos++;
        sortedFit.insert(pos, storedFit[i]);
        sortedId.insert(pos, storedId[i]);
      end
      if (storedFit.size() != POP_SIZE) fail($sformatf("generation %0d stored %0d results", genIdx, storedFit.size()));
      for (int c = 0; c < POP_SIZE; c++)
        if (playedA[c] != 1 || playedB[c] != 1)
          fail($sformatf("generation %0d: candidate %0d played A %0d times and B %0d times", genIdx, c, playedA[c], playedB[c]));
      if (runsThisGen != 16) fail($sformatf("generation %0d had %0d runs", genIdx, runsThisGen));
      // the registers are read one clock later (genPulse and GEN_END updates share an edge)
      #1;
      for (int i = 0; i < 8; i++)
        if (dut.ctrl.topScores[i] != sortedFit[i] || dut.ctrl.topIds[i] != sortedId[i] || !dut.ctrl.topValid[i])
          fail($sformatf("generation %0d top-8 entry %0d: C%0d %0d, expected C%0d %0d", genIdx, i,
                         dut.ctrl.topIds[i], dut.ctrl.topScores[i], sortedId[i], sortedFit[i]));
      best = -1; bestId = -1;
      foreach (storedFit[i]) if (storedFit[i] > best) begin best = storedFit[i]; bestId = storedId[i]; end
      if (dut.ctrl.genBest != best || dut.ctrl.genBestCand != bestId)
        fail($sformatf("generation best C%0d %0d, expected C%0d %0d", dut.ctrl.genBestCand, dut.ctrl.genBest, bestId, best));
      if (dut.ctrl.lastMeanSurv != 7'((sumT * 25) >> 17))
        fail($sformatf("mean survival %0d, expected %0d", dut.ctrl.lastMeanSurv, (sumT * 25) >> 17));
      if (dut.ctrl.evaluated != evaluatedCount) fail("evaluation counter wrong");
      if (genA[15] || genB[15] || genA == genB || genA == prevA)
        fail($sformatf("generation %0d worlds A %04h B %04h (previous A %04h)", genIdx, genA, genB, prevA));
      $display("INFO: generation %0d: worlds %04h/%04h, best C%0d gates %0d, top-8 C%0d C%0d C%0d C%0d ..., mean survival %0d%%",
               genIdx, genA, genB, bestId, best >> 16, sortedId[0], sortedId[1], sortedId[2], sortedId[3], dut.ctrl.lastMeanSurv);
      prevA = genA;
      genIdx++;
      storedFit.delete();
      storedId.delete();
      sumT = 0;
      runsThisGen = 0;
      for (int c = 0; c < POP_SIZE; c++) begin playedA[c] = 0; playedB[c] = 0; end
    end
  end

  always @(posedge clk) if (dut.runStart && dut.ctrl.runKind == 2'd0) begin genA <= dut.ctrl.seedA; genB <= dut.ctrl.seedB; end

  // ---------------------------------------------------------------- snapshots
  int snapWait = 0, worstWait = 0, snaps = 0, deadShown = 0;
  logic [LANES-1:0] diedBefore;
  logic [LANES-1:0][1:0] expState;
  logic [LANES-1:0][25:0] expFit;
  logic [LANES-1:0][11:0] expSteps;
  logic [LANES-1:0][76:0] expView;
  logic [LANES-1:0][5:0]  expCand;
  logic [15:0] expSeed;
  logic [11:0] expPlay;
  logic [2:0]  expRunState;

  always @(posedge clk) begin
    if (dut.snapReq && !dut.snapGrant) snapWait++;
    if (dut.snapGrant) begin
      if (snapWait > worstWait) worstWait = snapWait;
      if (snapWait > STEP_CLOCKS + 3) fail($sformatf("snapshot granted %0d clocks after the request", snapWait));
      snapWait = 0;
      if (dut.lanes.busy) fail("snapshot granted in the middle of a step");
      for (int k = 0; k < LANES; k++) begin
        expState[k] = !dut.lanes.enabled[k] ? LANE_IDLE : dut.lanes.done[k] ? LANE_DONE :
                      dut.lanes.alive[k] ? LANE_ALIVE : LANE_DEAD;
        if (dut.lanes.running && dut.lanes.playing && (expState[k] == LANE_DEAD) != diedBefore[k])
          fail($sformatf("lane %0d: DEAD shown %0d, died before the grant %0d", k, expState[k] == LANE_DEAD, diedBefore[k]));
        expFit[k]   = {dut.lanes.accG[k], dut.lanes.accTA[k]};
        expSteps[k] = dut.lanes.runT[k];
        expView[k]  = {dut.lanes.viewBirdY[k], dut.lanes.viewActive[k], dut.lanes.viewColX[k], dut.lanes.viewGapTop[k]};
        expCand[k]  = dut.ctrl.laneCand[k];
      end
      expSeed = dut.ctrl.runSeed;
      expPlay = dut.lanes.playSteps;
      expRunState = (dut.ctrl.runState == RS_READY && dut.lanes.playing) ? RS_PLAYING : dut.ctrl.runState;
    end
    if (snapTaken) begin
      snaps++;
      for (int k = 0; k < LANES; k++) begin
        if (sLaneState[k] != expState[k]) fail($sformatf("snapshot lane %0d state %0d, expected %0d", k, sLaneState[k], expState[k]));
        if (sLaneFit[k] != expFit[k] || sLaneGates[k] != expFit[k][25:16]) fail($sformatf("snapshot lane %0d fitness", k));
        if (sLaneSteps[k] != expSteps[k]) fail($sformatf("snapshot lane %0d steps", k));
        if ({sViewBirdY[k], sViewActive[k], sViewColX[k], sViewGapTop[k]} != expView[k]) fail($sformatf("snapshot lane %0d picture", k));
        if (sLaneCand[k] != expCand[k]) fail($sformatf("snapshot lane %0d candidate", k));
        if (sLaneState[k] == LANE_DEAD) deadShown++;
      end
      if (sSeed != expSeed || sPlaySteps != expPlay || sRunState != expRunState)
        fail($sformatf("snapshot seed/step/run state %04h/%0d/%0d, expected %04h/%0d/%0d",
                       sSeed, sPlaySteps, sRunState, expSeed, expPlay, expRunState));
    end
  end

  // death log: a lane that stops being alive (not done) during a run
  always @(posedge clk) begin
    if (dut.lanes.restart) diedBefore <= '0;
    else
      for (int k = 0; k < LANES; k++)
        if (dut.lanes.tickState && dut.lanes.playing && dut.lanes.alive[k] && !dut.lanes.done[k] && dut.lanes.collision[k])
          diedBefore[k] <= 1'b1;
  end

  // ---------------------------------------------------------------- pauses
  task automatic measure_hold(input logic [2:0] level, output int clocks);
    @(posedge clk iff dut.runDone);
    simLevel = level;
    clocks = 0;
    while (!dut.runStart) begin
      @(posedge clk);
      clocks++;
    end
    simLevel = 3'd7;
  endtask

  initial begin
    int fastHold, slowHold;
    for (int c = 0; c < POP_SIZE; c++) begin playedA[c] = 0; playedB[c] = 0; end
    diedBefore = '0;
    repeat (3) @(negedge clk);
    resetN = 1'b1;
    repeat (10) @(negedge clk);
    if (active) fail("trainer active after reset");

    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    if (!active) fail("trainer did not start");
    if (cfgDifficulty != 2'd1 || cfgColumns != 2'd3 || cfgSpeed != 3'd4) fail("training world not latched");

    wait (genIdx == 1);
    measure_hold(3'd7, fastHold);
    measure_hold(3'd3, slowHold);
    $display("INFO: run end to next run: %0d clocks at MAX, %0d clocks at x16 (pause of %0d frames x %0d clocks)",
             fastHold, slowHold, HOLD_RUN, FRAME_CLOCKS);
    if (slowHold < HOLD_RUN * FRAME_CLOCKS - FRAME_CLOCKS || fastHold > 500) fail("pause after a run wrong");

    wait (genIdx == 3);
    repeat (2) @(posedge clk iff snapTaken);
    $display("INFO: %0d snapshots, longest wait %0d clocks, %0d dead lanes shown", snaps, worstWait, deadShown);
    if (deadShown == 0) fail("no dead lane was ever shown");
    if (sRunId != 16'h3F2C || sGen != 8'd3) fail("snapshot RUN ID / generation wrong");

    // abort in the middle of a run, then a new run with another RUN ID
    wait (dut.lanes.playing && dut.lanes.running);
    @(negedge clk);
    abort = 1'b1;
    @(negedge clk);
    abort = 1'b0;
    @(negedge clk);
    if (active || dut.lanes.running) fail("abort did not stop the trainer");
    repeat (FRAME_CLOCKS * 2) @(negedge clk);
    if (dut.lanes.running) fail("a run started after the abort");
    genIdx = 0;
    storedFit.delete(); storedId.delete(); sumT = 0; runsThisGen = 0; evaluatedCount = 0; prevA = 16'h0000;
    for (int c = 0; c < POP_SIZE; c++) begin playedA[c] = 0; playedB[c] = 0; end
    runIdIn = 16'h0B0B;
    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    wait (genIdx == 1);
    if (dut.ctrl.runId != 16'h0B0B) fail("new RUN ID not taken");

    if (errors == 0) $display("PASS: tb_train_sched");
    else             $display("FAIL: tb_train_sched (%0d errors)", errors);
    $finish;
  end

endmodule
