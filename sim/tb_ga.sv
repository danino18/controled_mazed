// The genetic algorithm and the training flow of train_top (M11), checked
// against a reference model, over MAX_GEN generations with runs cut at TL steps.
//
// Every memory of the trainer is shadowed from its write ports. Checked:
//   - INIT_POP: 64 x 37 random genes -64..63 into the current population,
//     each equal to the GA random word of its clock
//   - every run loads the right genes into every lane: training batches
//     (candidates 8b..8b+7), validation (this generation's top 8 by training
//     fitness, a stable sort of the fitness writes), final test (the champion
//     in lane 0, lanes 1..7 idle)
//   - seeds: training A_g/B_g (bit 15 = 0, new every generation), validation
//     V1..V4 and test T1..T8 in order; the fitness memory is written only by
//     training runs (validation never feeds selection)
//   - validation: generation top = first best lane; the champion changes only
//     on a strictly better score and then equals that candidate's genes; its
//     score never decreases; stall and mutation level follow the champion only
//   - evolution: slots 0/1 = the two best by training fitness; every child
//     gene equals the reference tournament (4 random candidates, first best),
//     neuron-block crossover and mutation computed from the same random words
//   - commit: the populations swap, the history entry and the mean survival
//     are right, the generation counter advances
//   - after MAX_GEN generations: the final test runs, its result is stored,
//     the WATCH memory receives exactly the champion's genes, `commit` pulses
//     once and the trainer stays COMPLETE until it is sent back to idle
`timescale 1ns / 1ps

module tb_ga;
  import game_params_pkg::*, ml_pkg::*;

  localparam int TL = 300;
  localparam int GENS = 6;
  localparam int FRAME_CLOCKS = 3000;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic        start = 1'b0, stop = 1'b0, abort = 1'b0;
  logic [15:0] runIdIn = 16'h5EED;
  int          frameCount = 0;
  logic        frameTick;

  always @(posedge clk) frameCount <= (frameCount + 1) % FRAME_CLOCKS;
  assign frameTick = resetN && frameCount == 0;

  logic active, complete, genPulse, watchWe, aiValid, histWe;
  logic [5:0]  watchWa;
  logic [7:0]  watchWd;
  logic [6:0]  histWa;
  logic [20:0] histWd;

  train_top #(.T_LIMIT(TL), .HOLD_RUN_FRAMES(2), .HOLD_GEN_FRAMES(2), .MAX_GEN(GENS), .SECOND_CLOCKS(100000)) dut (
      .clk(clk), .resetN(resetN), .start(start), .stop(stop), .abort(abort), .hold(1'b0), .runIdIn(runIdIn),
      .difficultyIn(2'd2), .columnsIn(2'd2), .speedIn(3'd5), .simLevel(3'd7), .frameTick(frameTick),
      .active(active), .complete(complete), .liveAlive(), .genPulse(genPulse),
      .watchWe(watchWe), .watchWa(watchWa), .watchWd(watchWd), .aiValid(aiValid),
      .aiDifficulty(), .aiColumns(), .aiSpeed(), .aiRunId(), .aiGen(), .aiValW(), .aiValGates(),
      .aiTestW(), .aiTestGates(), .aiTestValid(),
      .histWe(histWe), .histWa(histWa), .histWd(histWd),
      .snapTaken(), .cfgDifficulty(), .cfgColumns(), .cfgSpeed(), .sLaneState(), .sLaneCand(), .sLaneAct(),
      .sLaneGates(), .sLaneFit(), .sLaneSteps(), .sViewBirdY(), .sViewActive(), .sViewColX(), .sViewGapTop(),
      .sStage(), .sRunState(), .sWorld(), .sRunId(), .sGen(), .sBatch(), .sSeed(), .sPlaySteps(), .sReadySteps(),
      .sGenBest(), .sGenBestCand(), .sGenBestValid(), .sPrevBest(), .sPrevBestValid(), .sGenDone(), .sLastMean(),
      .sLastMeanValid(), .sValTop(), .sValTopW(), .sValTopSurv(), .sValTopCand(), .sValTopValid(), .sChampExists(),
      .sChampScore(), .sChampW(), .sChampSurv(), .sChampGen(), .sChampCand(), .sStall(), .sMutLevel(),
      .sTestScore(), .sTestW(), .sTestSurv(), .sTestValid(), .sDoneReason(), .sEvaluated(), .sStepsPerSec());

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 40) $display("FAIL: %s", msg);
  endtask

  // ---------------------------------------------------------------- shadows of every memory
  logic [7:0]  popA [4096];
  logic [7:0]  popB [4096];
  logic [25:0] fitMem [64];
  logic [7:0]  chmp [64];
  logic [7:0]  watchMem [64];
  logic [63:0] laneMem [64];

  function automatic logic [7:0] cur_gene(input int c, input int g);
    return dut.ctrl.curIsA ? popA[c * 64 + g] : popB[c * 64 + g];
  endfunction

  always @(posedge clk) begin
    if (dut.ctrl.weA) popA[dut.ctrl.popWa] <= dut.ctrl.popWd;
    if (dut.ctrl.weB) popB[dut.ctrl.popWa] <= dut.ctrl.popWd;
    if (dut.ctrl.fitWe) fitMem[dut.ctrl.fitWa] <= dut.ctrl.fitWd;
    if (dut.ctrl.chmpWe) chmp[dut.ctrl.chmpA] <= dut.ctrl.chmpWd;
    if (watchWe) watchMem[watchWa] <= watchWd;
    if (dut.laneWe) laneMem[dut.laneWa] <= dut.laneWd;
  end

  // ---------------------------------------------------------------- reference helpers
  function automatic logic [7:0] mutate_ref(input logic [7:0] gene, input logic [31:0] r, input int level,
                                            ref int mutated);
    bit hit;
    int d, v;
    hit = (level == 0) ? (r[3:0] == 0) : (level == 1) ? (r[2:0] == 0) : (r[1:0] == 0);
    if (!hit) return gene;
    mutated++;
    if (r[7:5] == 0) return 8'(int'(r[22:16]) - 64);
    d = (int'(r[11:8]) - int'(r[15:12])) * (1 << level);
    v = int'($signed(gene)) + d;
    if (v > 127) v = 127;
    if (v < -128) v = -128;
    return 8'(v);
  endfunction

  function automatic int block_ref(input int g);
    return (g < 30) ? g / 5 : 6;
  endfunction

  function automatic int surv_ref(input int t, input int w, input int runs);
    if (w == runs) return 100;
    return (t * 25) >> (runs == 2 ? 11 : runs == 4 ? 12 : 13);     // t * 100 / (runs * 4095), rounded down
  endfunction

  // ---------------------------------------------------------------- per-generation reference state
  int     genIdx = 0;
  longint storedFit [$];
  int     storedId [$];
  int     top8 [8];
  longint sumT = 0;
  logic [15:0] prevA = 16'h0000, seedA, seedB;
  int     valRun = 0, testRun = 0;
  longint champScoreRef = -1;
  int     champGenRef = -1;
  int     stallRef = 0;
  int     levelRef = 0;
  int     initWrites = 0;
  int     mutated = 0, childGenes = 0, crossovers = 0;
  int     commits = 0;

  // INIT_POP
  always @(posedge clk) begin
    if (dut.ctrl.state == dut.ctrl.S_INIT_POP) begin
      initWrites++;
      if (!dut.ctrl.popWe || dut.ctrl.popWriteCur != 1'b1) fail("INIT_POP does not write the current population");
      if (dut.ctrl.popWd != 8'(int'(dut.ctrl.rnd[6:0]) - 64)) fail("INIT_POP gene is not the random word");
      if ($signed(dut.ctrl.popWd) < -64 || $signed(dut.ctrl.popWd) > 63) fail("INIT_POP gene out of range");
    end
  end

  // runs: seeds and lane genes
  always @(posedge clk) begin
    if (dut.runStart) begin
      case (dut.ctrl.runKind)
        2'd0: begin
          if (dut.ctrl.runIdx == 0 && dut.runSeed != dut.ctrl.seedA) fail("training run 0 does not use A");
          if (dut.ctrl.runIdx == 1 && dut.runSeed != dut.ctrl.seedB) fail("training run 1 does not use B");
          if (dut.runSeed[15]) fail("training seed with bit 15 set");
          if (dut.laneEnable != '1) fail("training run without all lanes");
          for (int k = 0; k < LANES; k++) begin
            if (dut.ctrl.laneCand[k] != dut.ctrl.batch * 8 + k) fail("training lane plays the wrong candidate");
            for (int g = 0; g < NN_GENES; g++)
              if (laneMem[g][k * 8 +: 8] !== cur_gene(dut.ctrl.laneCand[k], g)) begin
                fail($sformatf("gen %0d training lane %0d gene %0d wrong", genIdx, k, g));
                break;
              end
          end
        end
        2'd1: begin
          if (dut.runSeed != FIXED_SEEDS[16 * valRun +: 16]) fail($sformatf("validation run %0d seed %04h", valRun, dut.runSeed));
          if (dut.ctrl.runIdx != valRun) fail("validation run index wrong");
          valRun++;
          for (int k = 0; k < LANES; k++) begin
            if (dut.ctrl.laneCand[k] != top8[k]) fail($sformatf("validation lane %0d plays C%0d, top-8 entry is C%0d", k, dut.ctrl.laneCand[k], top8[k]));
            for (int g = 0; g < NN_GENES; g++)
              if (laneMem[g][k * 8 +: 8] !== cur_gene(top8[k], g)) begin
                fail($sformatf("validation lane %0d gene %0d wrong", k, g));
                break;
              end
          end
        end
        default: begin
          if (dut.runSeed != FIXED_SEEDS[16 * (4 + testRun) +: 16]) fail($sformatf("test run %0d seed %04h", testRun, dut.runSeed));
          testRun++;
          if (dut.laneEnable != 8'b0000_0001) fail("final test does not use lane 0 alone");
          for (int g = 0; g < NN_GENES; g++)
            if (laneMem[g][7:0] !== chmp[g]) begin
              fail($sformatf("test lane gene %0d = %02h, champion %02h", g, laneMem[g][7:0], chmp[g]));
              break;
            end
        end
      endcase
    end
  end

  // fitness writes: training only; collect this generation's results
  always @(posedge clk) begin
    if (dut.ctrl.fitWe) begin
      int k;
      if (dut.ctrl.runKind != 2'd0) fail("fitness memory written outside training");
      k = -1;
      for (int i = 0; i < LANES; i++) if (dut.ctrl.laneCand[i] == dut.ctrl.fitWa) k = i;
      if (k < 0 || dut.ctrl.fitWd != {dut.lanes.accG[k], dut.lanes.accTA[k]}) fail("fitness write wrong");
      else begin
        storedFit.push_back(longint'(dut.ctrl.fitWd));
        storedId.push_back(int'(dut.ctrl.fitWa));
        sumT += dut.lanes.accT[k];
      end
    end
  end

  // stable sort when the last training result is in
  always @(posedge clk) begin
    if (dut.ctrl.state == dut.ctrl.S_NEXT_BATCH && dut.ctrl.batch == 7) begin
      longint sf [$];
      int     si [$];
      sf.delete(); si.delete();
      for (int i = 0; i < storedFit.size(); i++) begin
        int pos;
        pos = 0;
        while (pos < sf.size() && sf[pos] >= storedFit[i]) pos++;
        sf.insert(pos, storedFit[i]);
        si.insert(pos, storedId[i]);
      end
      if (storedFit.size() != 64) fail($sformatf("generation %0d stored %0d results", genIdx, storedFit.size()));
      for (int i = 0; i < 8; i++) top8[i] = si[i];
      valRun = 0;
    end
  end

  // validation decision
  longint valTopRef;
  int     valTopLane;
  always @(posedge clk) begin
    if (dut.ctrl.state == dut.ctrl.S_VAL_DECIDE) begin
      valTopRef = -1;
      valTopLane = -1;
      for (int k = 0; k < LANES; k++)
        if (longint'({dut.lanes.accG[k], dut.lanes.accTA[k]}) > valTopRef) begin
          valTopRef = longint'({dut.lanes.accG[k], dut.lanes.accTA[k]});
          valTopLane = k;
        end
      if (dut.ctrl.valTop != valTopRef || dut.ctrl.valTopCand != top8[valTopLane])
        fail($sformatf("generation top %0d C%0d, expected %0d C%0d", dut.ctrl.valTop, dut.ctrl.valTopCand, valTopRef, top8[valTopLane]));
      if (dut.ctrl.valTopW != dut.lanes.accW[valTopLane]) fail("generation top worlds wrong");
      if (dut.ctrl.valTopSurv != 7'(surv_ref(dut.lanes.accT[valTopLane], dut.lanes.accW[valTopLane], 4)))
        fail("generation top survival wrong");
      #1;
      if (champScoreRef < 0 || valTopRef > champScoreRef) begin
        if (champScoreRef >= 0 && valTopRef <= champScoreRef) fail("champion replaced without improvement");
        champScoreRef = valTopRef;
        champGenRef   = genIdx;
        stallRef      = 0;
        if (dut.ctrl.state != dut.ctrl.S_CHAMP_COPY) fail("better generation top not copied");
      end else begin
        stallRef++;
        if (dut.ctrl.state == dut.ctrl.S_CHAMP_COPY) fail("champion copied without improvement");
      end
      if (dut.ctrl.champScore != champScoreRef) fail($sformatf("champion score %0d, expected %0d", dut.ctrl.champScore, champScoreRef));
      if (dut.ctrl.stall != stallRef) fail($sformatf("stall %0d, expected %0d", dut.ctrl.stall, stallRef));
    end
  end

  // champion memory after the copy
  always @(posedge clk) begin
    if (dut.ctrl.state == dut.ctrl.S_CHAMP_COPY && dut.ctrl.cp && dut.ctrl.g == NN_GENES - 1) begin
      #1;
      for (int g = 0; g < NN_GENES; g++)
        if (chmp[g] !== cur_gene(dut.ctrl.champCand, g)) begin
          fail($sformatf("champion gene %0d = %02h, candidate C%0d has %02h", g, chmp[g], dut.ctrl.champCand, cur_gene(dut.ctrl.champCand, g)));
          break;
        end
    end
  end

  // evolution
  int tids [4];
  int parA, parB;
  bit doX;
  logic [6:0] xmask;
  int child = 0;

  function automatic int tournament(input int ids [4]);
    int best;
    best = ids[0];
    for (int i = 1; i < 4; i++) if (fitMem[ids[i]] > fitMem[best]) best = ids[i];
    return best;
  endfunction

  always @(posedge clk) begin
    // elites
    if (dut.ctrl.state == dut.ctrl.S_EVO_ELITE && dut.ctrl.cp) begin
      int e, g;
      e = dut.ctrl.eliteIdx;
      g = dut.ctrl.g;
      if (!dut.ctrl.popWe || dut.ctrl.popWriteCur) fail("elite not written to the next population");
      if (dut.ctrl.popWa != (e * 64 + g)) fail("elite written to the wrong slot");
      if (dut.ctrl.popWd != cur_gene(top8[e], g)) fail($sformatf("elite %0d gene %0d wrong", e, g));
    end
    // tournaments
    if (dut.ctrl.state == dut.ctrl.S_SELECT && dut.ctrl.tsel == 0) begin
      for (int i = 0; i < 4; i++) tids[i] = int'(dut.ctrl.rnd[6 * i +: 6]);
      if (!dut.ctrl.tour) parA = tournament(tids);
      else                parB = tournament(tids);
    end
    if (dut.ctrl.state == dut.ctrl.S_SELECT && dut.ctrl.tsel == 4 && dut.ctrl.tour) begin
      doX   = (dut.ctrl.rnd[1:0] != 0);
      xmask = dut.ctrl.rnd[8:2];
      if (doX) crossovers++;
      #1;
      if (dut.ctrl.parA != parA || dut.ctrl.parB != parB)
        fail($sformatf("parents C%0d C%0d, reference C%0d C%0d", dut.ctrl.parA, dut.ctrl.parB, parA, parB));
    end
    // children
    if (dut.ctrl.state == dut.ctrl.S_BREED && dut.ctrl.cp) begin
      int g, src;
      logic [7:0] expected;
      g   = dut.ctrl.g;
      src = (doX && xmask[block_ref(g)]) ? parB : parA;
      expected = mutate_ref(cur_gene(src, g), dut.ctrl.rnd, levelRef, mutated);
      childGenes++;
      if (!dut.ctrl.popWe || dut.ctrl.popWriteCur) fail("child not written to the next population");
      if (dut.ctrl.popWa != (dut.ctrl.child * 64 + g)) fail("child written to the wrong slot");
      if (dut.ctrl.popWd != expected)
        fail($sformatf("gen %0d child %0d gene %0d = %02h, reference %02h (parent C%0d gene %02h)", genIdx,
                       dut.ctrl.child, g, dut.ctrl.popWd, expected, src, cur_gene(src, g)));
    end
  end

  // commit
  always @(posedge clk) begin
    if (histWe) begin
      int meanRef;
      logic curBefore;
      meanRef = int'((sumT * 25) >> 17);
      if (histWa != genIdx) fail("history address wrong");
      if (histWd != {dut.ctrl.champSurv, dut.ctrl.valTopSurv, 7'(meanRef)})
        fail($sformatf("history entry %h, expected champion %0d top %0d mean %0d", histWd, dut.ctrl.champSurv, dut.ctrl.valTopSurv, meanRef));
      curBefore = dut.ctrl.curIsA;
      #1;
      if (dut.ctrl.curIsA == curBefore) fail("populations did not swap");
      if (dut.ctrl.gen != genIdx + 1) fail("generation counter wrong");
      levelRef = (stallRef >= 16) ? 2 : (stallRef >= 8) ? 1 : 0;
      if (dut.ctrl.mutLevel != levelRef) fail("mutation level wrong");
      $display("INFO: generation %0d: mean survival %0d%%, generation top %0d gates %0d/4 worlds (%0d%%), champion from gen %0d: %0d gates, %0d/4 worlds, %0d%%; stall %0d",
               genIdx, meanRef, dut.ctrl.valTop >> 16, dut.ctrl.valTopW, dut.ctrl.valTopSurv, dut.ctrl.champGen,
               dut.ctrl.champScore >> 16, dut.ctrl.champW, dut.ctrl.champSurv, dut.ctrl.stall);
      if (dut.ctrl.champGen != champGenRef) fail("champion generation wrong");
      genIdx++;
      commits++;
      storedFit.delete();
      storedId.delete();
      sumT = 0;
    end
  end

  int watchWrites = 0, commitPulses = 0;
  always @(posedge clk) begin
    if (watchWe) watchWrites++;
    if (dut.commit) commitPulses++;
  end

  initial begin
    repeat (3) @(negedge clk);
    resetN = 1'b1;
    repeat (10) @(negedge clk);
    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;

    wait (complete);
    repeat (5) @(negedge clk);
    if (initWrites != 64 * NN_GENES) fail($sformatf("INIT_POP wrote %0d genes", initWrites));
    if (commits != GENS) fail($sformatf("%0d generations committed, expected %0d", commits, GENS));
    if (testRun != 8) fail($sformatf("final test had %0d runs", testRun));
    if (dut.ctrl.doneReason != 2'd0) fail("stop reason is not MAX GENERATIONS");
    if (!dut.ctrl.testValid) fail("test result not valid");
    if (dut.ctrl.testScore != {dut.lanes.accG[0], dut.lanes.accTA[0]}) fail("test score wrong");
    if (dut.ctrl.testSurv != 7'(surv_ref(dut.lanes.accT[0], dut.lanes.accW[0], 8))) fail("test survival wrong");
    if (watchWrites != NN_GENES || commitPulses != 1) fail($sformatf("%0d WATCH writes, %0d commit pulses", watchWrites, commitPulses));
    for (int g = 0; g < NN_GENES; g++)
      if (watchMem[g] !== chmp[g]) begin
        fail($sformatf("WATCH gene %0d = %02h, champion %02h", g, watchMem[g], chmp[g]));
        break;
      end
    if (!aiValid) fail("committed AI flag not set");
    if (dut.aiGen != GENS || dut.aiValGates != champScoreRef >> 16 || dut.aiValW != dut.ctrl.champW)
      fail("committed AI information wrong");
    $display("INFO: final test: %0d gates, %0d/8 worlds, %0d%% survival; %0d child genes, %0d mutated (%0d%%), %0d of %0d children crossed over",
             dut.ctrl.testScore >> 16, dut.ctrl.testW, dut.ctrl.testSurv, childGenes, mutated,
             childGenes ? mutated * 100 / childGenes : 0, crossovers, GENS * 62);
    repeat (FRAME_CLOCKS * 3) @(negedge clk);
    if (!complete || !active) fail("trainer left COMPLETE by itself");
    @(negedge clk);
    abort = 1'b1;
    @(negedge clk);
    abort = 1'b0;
    @(negedge clk);
    if (active || !aiValid) fail("abort after completion: trainer not idle or AI lost");

    if (errors == 0) $display("PASS: tb_ga");
    else             $display("FAIL: tb_ga (%0d errors)", errors);
    $finish;
  end

endmodule
