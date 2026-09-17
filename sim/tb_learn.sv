// Learning measurement (not part of the default regression; long):
// the real trainer (train_top, full 4,095-step runs, SIM MAX) from a fixed
// RUN ID, one line per generation, then the final test.
//
//   sh sim/run_tests.sh tb_learn +gens=30 +diff=1 +cols=2 +speed=2 +run=3F2C
//
// Board time = simulated clocks / 31,500,000. A training run is a
// deterministic function of its RUN ID and settings; on the board the RUN ID
// comes from the key press that starts training, so board runs differ.
`timescale 1ns / 1ps

module tb_learn;
  import game_params_pkg::*, ml_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  int gens, diff, cols, speed, runId;
  initial begin
    if (!$value$plusargs("gens=%d", gens))   gens = 30;
    if (!$value$plusargs("diff=%d", diff))   diff = 1;
    if (!$value$plusargs("cols=%d", cols))   cols = 2;
    if (!$value$plusargs("speed=%d", speed)) speed = 2;
    if (!$value$plusargs("run=%h", runId))   runId = 16'h3F2C;
  end

  logic        start = 1'b0, stop = 1'b0;
  logic        complete, genPulse;
  longint      clocks = 0;
  int          frameCount = 0;
  logic        frameTick;

  always @(posedge clk) begin
    clocks++;
    frameCount <= (frameCount + 1) % 433993;
  end
  assign frameTick = resetN && frameCount == 0;

  train_top #(.MAX_GEN(255)) dut (
      .clk(clk), .resetN(resetN), .start(start), .stop(stop), .abort(1'b0), .hold(1'b0),
      .runIdIn(16'(runId)), .difficultyIn(2'(diff)), .columnsIn(2'(cols)), .speedIn(3'(speed)),
      .simLevel(3'd7), .frameTick(frameTick),
      .active(), .complete(complete), .liveAlive(), .genPulse(genPulse),
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

  longint lastClocks = 0;
  int     done = 0;

  always @(posedge clk) begin
    if (genPulse) begin
      $display("INFO: gen %3d  t=%7.2f s (+%5.2f)  mean %3d%%  top %3d gates %0d/4 %3d%%  champion(gen %3d) %3d gates %0d/4 %3d%%  stall %2d  best train %3d gates",
               done, real'(clocks) / 31.5e6, real'(clocks - lastClocks) / 31.5e6,
               dut.ctrl.lastMeanSurv, dut.ctrl.valTop >> 16, dut.ctrl.valTopW, dut.ctrl.valTopSurv,
               dut.ctrl.champGen, dut.ctrl.champScore >> 16, dut.ctrl.champW, dut.ctrl.champSurv,
               dut.ctrl.stall, dut.ctrl.genBest >> 16);
      lastClocks = clocks;
      done++;
    end
  end

  initial begin
    repeat (3) @(negedge clk);
    resetN = 1'b1;
    repeat (10) @(negedge clk);
    $display("INFO: RUN %04h, difficulty %0d, %0d columns, world speed %0d, %0d generations", runId, diff, cols, speed, gens);
    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    wait (done == gens || complete);
    if (!complete) begin
      @(negedge clk);
      stop = 1'b1;
      @(negedge clk);
      stop = 1'b0;
      wait (complete);
    end
    $display("INFO: stopped after %0d generations (reason %0d) at t=%.2f s; final test %0d gates, %0d/8 worlds, %0d%% survival; %0d evaluations",
             dut.ctrl.gen, dut.ctrl.doneReason, real'(clocks) / 31.5e6, dut.ctrl.testScore >> 16, dut.ctrl.testW,
             dut.ctrl.testSurv, dut.ctrl.evaluated);
    $display("PASS: tb_learn");
    $finish;
  end

endmodule
