// The on-chip trainer: scheduler and genetic algorithm (train_ctrl), parallel
// simulator (train_lanes), simulation-speed throttle, the committed AI, and the
// per-frame snapshot that the training screen shows.
//
// Snapshot: startOfFrame raises a request; the simulator grants it between
// two steps (at most STEP_CLOCKS clocks later) and every displayed value is
// copied on that one clock, so a frame shows all lanes and statistics at the
// same simulated step. The screen reads only the snapshot (the character
// writer starts after the grant).
//
// Committed AI (decision D2): when a training run finishes, the champion's
// genes are written into the WATCH AI memory and its settings and results
// into the registers below. Those registers have no reset (they start at 0
// when the FPGA is configured), so KEY0 keeps a committed AI.

module train_top
  import game_params_pkg::*, game_state_pkg::*, ml_pkg::*;
#(
    parameter int T_LIMIT         = T_MAX,
    parameter int HOLD_RUN_FRAMES = 36,
    parameter int HOLD_GEN_FRAMES = 73,
    parameter int MAX_GEN         = 100,
    parameter int SOLVE_STALL     = 10,
    parameter int SECOND_CLOCKS   = CLOCKS_PER_SECOND
) (
    input  logic                                 clk,
    input  logic                                 resetN,

    input  logic                                 start,        // one clock: train on the world below
    input  logic                                 stop,         // one clock: stop, test and keep the champion
    input  logic                                 abort,        // one clock: back to idle
    input  logic                                 hold,         // pause
    input  logic [15:0]                          runIdIn,
    input  logic [1:0]                           difficultyIn,
    input  logic [1:0]                           columnsIn,
    input  logic [2:0]                           speedIn,
    input  logic [2:0]                           simLevel,
    input  logic                                 frameTick,    // startOfFrame

    // live
    output logic                                 active,
    output logic                                 complete,
    output logic [LANES-1:0]                     liveAlive,
    output logic                                 genPulse,

    // WATCH AI memory and the committed AI
    output logic                                 watchWe,
    output logic [GENE_ADDR_W-1:0]               watchWa,
    output logic [7:0]                           watchWd,
    output logic                                 aiValid,      // a trained AI has been committed
    output logic [1:0]                           aiDifficulty,
    output logic [1:0]                           aiColumns,
    output logic [2:0]                           aiSpeed,
    output logic [15:0]                          aiRunId,
    output logic [7:0]                           aiGen,        // generations trained
    output logic [3:0]                           aiValW,       // validation worlds completed (of 4)
    output logic [9:0]                           aiValGates,
    output logic [3:0]                           aiTestW,      // test worlds completed (of 8)
    output logic [9:0]                           aiTestGates,
    output logic                                 aiTestValid,

    // learning chart memory
    output logic                                 histWe,
    output logic [6:0]                           histWa,
    output logic [20:0]                          histWd,

    // snapshot (for the training screen)
    output logic                                 snapTaken,
    output logic [1:0]                           cfgDifficulty,
    output logic [1:0]                           cfgColumns,
    output logic [2:0]                           cfgSpeed,
    output logic [LANES-1:0][1:0]                sLaneState,
    output logic [LANES-1:0][CAND_W-1:0]         sLaneCand,
    output logic [LANES-1:0][1:0]                sLaneAct,
    output logic [LANES-1:0][9:0]                sLaneGates,
    output logic [LANES-1:0][FIT_W-1:0]          sLaneFit,
    output logic [LANES-1:0][11:0]               sLaneSteps,
    output logic [LANES-1:0][10:0]               sViewBirdY,
    output logic [LANES-1:0][NUM_COLUMNS-1:0]    sViewActive,
    output logic [LANES-1:0][NUM_COLUMNS*11-1:0] sViewColX,
    output logic [LANES-1:0][NUM_COLUMNS*10-1:0] sViewGapTop,
    output logic [2:0]                           sStage,
    output logic [2:0]                           sRunState,
    output logic [3:0]                           sWorld,
    output logic [15:0]                          sRunId,
    output logic [7:0]                           sGen,
    output logic [3:0]                           sBatch,
    output logic [15:0]                          sSeed,
    output logic [11:0]                          sPlaySteps,
    output logic [6:0]                           sReadySteps,
    output logic [FIT_W-1:0]                     sGenBest,
    output logic [CAND_W-1:0]                    sGenBestCand,
    output logic                                 sGenBestValid,
    output logic [FIT_W-1:0]                     sPrevBest,
    output logic                                 sPrevBestValid,
    output logic [6:0]                           sGenDone,
    output logic [6:0]                           sLastMean,
    output logic                                 sLastMeanValid,
    output logic [FIT_W-1:0]                     sValTop,
    output logic [3:0]                           sValTopW,
    output logic [6:0]                           sValTopSurv,
    output logic [CAND_W-1:0]                    sValTopCand,
    output logic                                 sValTopValid,
    output logic                                 sChampExists,
    output logic [FIT_W-1:0]                     sChampScore,
    output logic [3:0]                           sChampW,
    output logic [6:0]                           sChampSurv,
    output logic [7:0]                           sChampGen,
    output logic [CAND_W-1:0]                    sChampCand,
    output logic [5:0]                           sStall,
    output logic [1:0]                           sMutLevel,
    output logic [FIT_W-1:0]                     sTestScore,
    output logic [3:0]                           sTestW,
    output logic [6:0]                           sTestSurv,
    output logic                                 sTestValid,
    output logic [1:0]                           sDoneReason,
    output logic [31:0]                          sEvaluated,
    output logic [19:0]                          sStepsPerSec
);

  // ---------------------------------------------------------------- training world
  logic [1:0] difficulty, columns;
  logic [2:0] speed;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      difficulty <= DIFF_EASY;
      columns    <= 2'd1;
      speed      <= '0;
    end else if (start && (!active || complete)) begin
      difficulty <= difficultyIn;
      columns    <= columnsIn;
      speed      <= speedIn;
    end
  end

  assign cfgDifficulty = difficulty;
  assign cfgColumns    = columns;
  assign cfgSpeed      = speed;

  // ---------------------------------------------------------------- scheduler and genetic algorithm
  logic                         runStart, stageClear, lanesAbort, runDone, commit;
  logic [15:0]                  runSeed;
  logic [LANES-1:0]             laneEnable;
  logic                         laneWe;
  logic [GENE_ADDR_W-1:0]       laneWa;
  logic [LANES*8-1:0]           laneWd;
  logic [LANES-1:0][9:0]        accG;
  logic [LANES-1:0][15:0]       accTA;
  logic [LANES-1:0][14:0]       accT;
  logic [LANES-1:0][3:0]        accW;

  logic [2:0]                   stage, runState;
  logic [3:0]                   worldCode;
  logic [15:0]                  runId;
  logic [7:0]                   gen;
  logic [3:0]                   batch, runIdx;
  logic [LANES-1:0][CAND_W-1:0] laneCand;
  logic [FIT_W-1:0]             genBest, prevBest, valTop, champScore, testScore;
  logic [CAND_W-1:0]            genBestCand, valTopCand, champCand;
  logic                         genBestValid, prevBestValid, lastMeanValid, valTopValid, champExists, testValid;
  logic [6:0]                   genDone, lastMeanSurv, valTopSurv, champSurv, testSurv;
  logic [3:0]                   valTopW, champW, testW;
  logic [7:0]                   champGen;
  logic [5:0]                   stall;
  logic [1:0]                   mutLevel, doneReason;
  logic [31:0]                  evaluated;

  train_ctrl #(
      .HOLD_RUN_FRAMES(HOLD_RUN_FRAMES),
      .HOLD_GEN_FRAMES(HOLD_GEN_FRAMES),
      .MAX_GEN        (MAX_GEN),
      .SOLVE_STALL    (SOLVE_STALL)
  ) ctrl (
      .clk          (clk),
      .resetN       (resetN),
      .start        (start),
      .stop         (stop),
      .abort        (abort),
      .hold         (hold),
      .runIdIn      (runIdIn),
      .frameTick    (frameTick),
      .simLevel     (simLevel),
      .runStart     (runStart),
      .runSeed      (runSeed),
      .laneEnable   (laneEnable),
      .stageClear   (stageClear),
      .lanesAbort   (lanesAbort),
      .runDone      (runDone),
      .accG         (accG),
      .accTA        (accTA),
      .accT         (accT),
      .accW         (accW),
      .laneWe       (laneWe),
      .laneWa       (laneWa),
      .laneWd       (laneWd),
      .watchWe      (watchWe),
      .watchWa      (watchWa),
      .watchWd      (watchWd),
      .commit       (commit),
      .histWe       (histWe),
      .histWa       (histWa),
      .histWd       (histWd),
      .active       (active),
      .complete     (complete),
      .stage        (stage),
      .runState     (runState),
      .worldCode    (worldCode),
      .runId        (runId),
      .gen          (gen),
      .batch        (batch),
      .runIdx       (runIdx),
      .laneCand     (laneCand),
      .genBest      (genBest),
      .genBestCand  (genBestCand),
      .genBestValid (genBestValid),
      .prevBest     (prevBest),
      .prevBestValid(prevBestValid),
      .genDone      (genDone),
      .lastMeanSurv (lastMeanSurv),
      .lastMeanValid(lastMeanValid),
      .valTop       (valTop),
      .valTopW      (valTopW),
      .valTopSurv   (valTopSurv),
      .valTopCand   (valTopCand),
      .valTopValid  (valTopValid),
      .champExists  (champExists),
      .champScore   (champScore),
      .champW       (champW),
      .champSurv    (champSurv),
      .champGen     (champGen),
      .champCand    (champCand),
      .stall        (stall),
      .mutLevel     (mutLevel),
      .testScore    (testScore),
      .testW        (testW),
      .testSurv     (testSurv),
      .testValid    (testValid),
      .doneReason   (doneReason),
      .evaluated    (evaluated),
      .genPulse     (genPulse)
  );

  // ---------------------------------------------------------------- committed AI (no reset: KEY0 keeps it)
  logic        aiValidReg = 1'b0;
  logic [1:0]  aiDifficultyReg = 2'd0;
  logic [1:0]  aiColumnsReg = 2'd1;
  logic [2:0]  aiSpeedReg = 3'd0;
  logic [15:0] aiRunIdReg = 16'd0;
  logic [7:0]  aiGenReg = 8'd0;
  logic [3:0]  aiValWReg = 4'd0;
  logic [9:0]  aiValGatesReg = 10'd0;
  logic [3:0]  aiTestWReg = 4'd0;
  logic [9:0]  aiTestGatesReg = 10'd0;
  logic        aiTestValidReg = 1'b0;

  always_ff @(posedge clk) begin
    if (commit) begin
      aiValidReg      <= 1'b1;
      aiDifficultyReg <= difficulty;
      aiColumnsReg    <= columns;
      aiSpeedReg      <= speed;
      aiRunIdReg      <= runId;
      aiGenReg        <= gen;
      aiValWReg       <= champW;
      aiValGatesReg   <= champScore[FIT_W-1:16];
      aiTestWReg      <= testW;
      aiTestGatesReg  <= testScore[FIT_W-1:16];
      aiTestValidReg  <= testValid;
    end
  end

  assign aiValid      = aiValidReg;
  assign aiDifficulty = aiDifficultyReg;
  assign aiColumns    = aiColumnsReg;
  assign aiSpeed      = aiSpeedReg;
  assign aiRunId      = aiRunIdReg;
  assign aiGen        = aiGenReg;
  assign aiValW       = aiValWReg;
  assign aiValGates   = aiValGatesReg;
  assign aiTestW      = aiTestWReg;
  assign aiTestGates  = aiTestGatesReg;
  assign aiTestValid  = aiTestValidReg;

  // ---------------------------------------------------------------- simulator and throttle
  logic                                 stepGo, stepStart, snapReq, snapGrant;
  logic                                 running, playing;
  logic [11:0]                          playSteps;
  logic [6:0]                           readySteps;
  logic [LANES-1:0]                     enabled, alive, done;
  logic [LANES-1:0][1:0]                act;
  logic [LANES-1:0][11:0]               runT;
  logic [LANES-1:0][10:0]               viewBirdY;
  logic [LANES-1:0][NUM_COLUMNS-1:0]    viewActive;
  logic [LANES-1:0][NUM_COLUMNS*11-1:0] viewColX;
  logic [LANES-1:0][NUM_COLUMNS*10-1:0] viewGapTop;

  sim_throttle throttle (
      .clk      (clk),
      .resetN   (resetN),
      .level    (simLevel),
      .stepTaken(stepStart),
      .stepGo   (stepGo)
  );

  train_lanes #(.T_LIMIT(T_LIMIT)) lanes (
      .clk         (clk),
      .resetN      (resetN),
      .difficulty  (difficulty),
      .columnCount (columns),
      .speedLevel  (speed),
      .runStart    (runStart),
      .runSeed     (runSeed),
      .laneEnable  (laneEnable),
      .stageClear  (stageClear),
      .abort       (lanesAbort),
      .stepGo      (stepGo),
      .hold        (hold),
      .snapReq     (snapReq),
      .snapGrant   (snapGrant),
      .running     (running),
      .runDone     (runDone),
      .stepStart   (stepStart),
      .playing     (playing),
      .playSteps   (playSteps),
      .readySteps  (readySteps),
      .wWe         (laneWe),
      .wAddr       (laneWa),
      .wData       (laneWd),
      .enabled     (enabled),
      .alive       (alive),
      .done        (done),
      .act         (act),
      .runT        (runT),
      .accG        (accG),
      .accTA       (accTA),
      .accT        (accT),
      .accW        (accW),
      .viewBirdY   (viewBirdY),
      .viewActive  (viewActive),
      .viewColX    (viewColX),
      .viewGapTop  (viewGapTop),
      .mazeOffset  (),
      .collision   (),
      .tickStateOut(),
      .worldBirdY  (),
      .worldColX   ()
  );

  assign liveAlive = enabled & alive & ~done & {LANES{running}};

  // ---------------------------------------------------------------- throughput (steps per second)
  logic [24:0] secondCount;
  logic [19:0] stepCount;
  logic [19:0] stepsPerSec;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      secondCount <= '0;
      stepCount   <= '0;
      stepsPerSec <= '0;
    end else if (secondCount == 25'(SECOND_CLOCKS - 1)) begin
      secondCount <= '0;
      stepCount   <= 20'(stepStart);
      stepsPerSec <= stepCount;
    end else begin
      secondCount <= secondCount + 25'd1;
      if (stepStart) stepCount <= stepCount + 20'd1;
    end
  end

  // ---------------------------------------------------------------- snapshot
  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN)        snapReq <= 1'b0;
    else if (frameTick) snapReq <= 1'b1;
    else if (snapGrant) snapReq <= 1'b0;
  end

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      snapTaken      <= 1'b0;
      sLaneState     <= '0;
      sLaneCand      <= '0;
      sLaneAct       <= '0;
      sLaneGates     <= '0;
      sLaneFit       <= '0;
      sLaneSteps     <= '0;
      sViewBirdY     <= '0;
      sViewActive    <= '0;
      sViewColX      <= '0;
      sViewGapTop    <= '0;
      sStage         <= STG_IDLE;
      sRunState      <= RS_NONE;
      sWorld         <= '0;
      sRunId         <= '0;
      sGen           <= '0;
      sBatch         <= '0;
      sSeed          <= '0;
      sPlaySteps     <= '0;
      sReadySteps    <= '0;
      sGenBest       <= '0;
      sGenBestCand   <= '0;
      sGenBestValid  <= 1'b0;
      sPrevBest      <= '0;
      sPrevBestValid <= 1'b0;
      sGenDone       <= '0;
      sLastMean      <= '0;
      sLastMeanValid <= 1'b0;
      sValTop        <= '0;
      sValTopW       <= '0;
      sValTopSurv    <= '0;
      sValTopCand    <= '0;
      sValTopValid   <= 1'b0;
      sChampExists   <= 1'b0;
      sChampScore    <= '0;
      sChampW        <= '0;
      sChampSurv     <= '0;
      sChampGen      <= '0;
      sChampCand     <= '0;
      sStall         <= '0;
      sMutLevel      <= '0;
      sTestScore     <= '0;
      sTestW         <= '0;
      sTestSurv      <= '0;
      sTestValid     <= 1'b0;
      sDoneReason    <= '0;
      sEvaluated     <= '0;
      sStepsPerSec   <= '0;
    end else begin
      snapTaken <= snapGrant;
      if (snapGrant) begin
        for (int i = 0; i < LANES; i++) begin
          if (!enabled[i])   sLaneState[i] <= LANE_IDLE;
          else if (done[i])  sLaneState[i] <= LANE_DONE;
          else if (alive[i]) sLaneState[i] <= LANE_ALIVE;
          else               sLaneState[i] <= LANE_DEAD;
          sLaneGates[i] <= accG[i];
          sLaneFit[i]   <= {accG[i], accTA[i]};
          sLaneSteps[i] <= runT[i];
        end
        sLaneCand      <= laneCand;
        sLaneAct       <= act;
        sViewBirdY     <= viewBirdY;
        sViewActive    <= viewActive;
        sViewColX      <= viewColX;
        sViewGapTop    <= viewGapTop;
        sStage         <= stage;
        sRunState      <= (runState == RS_READY && playing) ? RS_PLAYING : runState;
        sWorld         <= worldCode;
        sRunId         <= runId;
        sGen           <= gen;
        sBatch         <= batch;
        sSeed          <= runSeed;
        sPlaySteps     <= playSteps;
        sReadySteps    <= readySteps;
        sGenBest       <= genBest;
        sGenBestCand   <= genBestCand;
        sGenBestValid  <= genBestValid;
        sPrevBest      <= prevBest;
        sPrevBestValid <= prevBestValid;
        sGenDone       <= genDone;
        sLastMean      <= lastMeanSurv;
        sLastMeanValid <= lastMeanValid;
        sValTop        <= valTop;
        sValTopW       <= valTopW;
        sValTopSurv    <= valTopSurv;
        sValTopCand    <= valTopCand;
        sValTopValid   <= valTopValid;
        sChampExists   <= champExists;
        sChampScore    <= champScore;
        sChampW        <= champW;
        sChampSurv     <= champSurv;
        sChampGen      <= champGen;
        sChampCand     <= champCand;
        sStall         <= stall;
        sMutLevel      <= mutLevel;
        sTestScore     <= testScore;
        sTestW         <= testW;
        sTestSurv      <= testSurv;
        sTestValid     <= testValid;
        sDoneReason    <= doneReason;
        sEvaluated     <= evaluated;
        sStepsPerSec   <= stepsPerSec;
      end
    end
  end

endmodule
