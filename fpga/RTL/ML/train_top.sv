// The on-chip trainer: scheduler (train_ctrl), parallel simulator
// (train_lanes), simulation-speed throttle, and the per-frame snapshot that
// the training screen shows.
//
// Snapshot: startOfFrame raises a request; the simulator grants it between
// two steps (at most STEP_CLOCKS clocks later) and every displayed value is
// copied on that one clock, so a frame shows all lanes and statistics at the
// same simulated step. The screen reads only the snapshot (the character
// writer starts SNAP_DELAY clocks after startOfFrame, after the grant).

module train_top
  import game_params_pkg::*, game_state_pkg::*, ml_pkg::*;
#(
    parameter int T_LIMIT         = T_MAX,
    parameter     POP_FILE        = "RTL/MIF/pop_init.mif",
    parameter int HOLD_RUN_FRAMES = 36,
    parameter int HOLD_GEN_FRAMES = 73,
    parameter int SECOND_CLOCKS   = CLOCKS_PER_SECOND
) (
    input  logic                                 clk,
    input  logic                                 resetN,

    input  logic                                 start,        // one clock: train on the world below
    input  logic                                 abort,        // one clock: stop and forget the run
    input  logic [15:0]                          runIdIn,
    input  logic [1:0]                           difficultyIn,
    input  logic [1:0]                           columnsIn,
    input  logic [2:0]                           speedIn,
    input  logic [2:0]                           simLevel,
    input  logic                                 frameTick,    // startOfFrame

    // live (for LEDs)
    output logic                                 active,
    output logic [LANES-1:0]                     liveAlive,
    output logic                                 genPulse,

    // snapshot (for the training screen)
    output logic                                 snapTaken,    // one clock after each snapshot
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
    output logic [15:0]                          sRunId,
    output logic [7:0]                           sGen,
    output logic [3:0]                           sBatch,
    output logic [3:0]                           sRunIdx,
    output logic [15:0]                          sSeed,
    output logic [11:0]                          sPlaySteps,
    output logic [6:0]                           sReadySteps,
    output logic [FIT_W-1:0]                     sGenBest,
    output logic [CAND_W-1:0]                    sGenBestCand,
    output logic                                 sGenBestValid,
    output logic [6:0]                           sGenDone,
    output logic [6:0]                           sLastMean,
    output logic                                 sLastMeanValid,
    output logic [7:0][FIT_W-1:0]                sTopScores,
    output logic [7:0][CAND_W-1:0]               sTopIds,
    output logic [7:0]                           sTopValid,
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
    end else if (start) begin
      difficulty <= difficultyIn;
      columns    <= columnsIn;
      speed      <= speedIn;
    end
  end

  assign cfgDifficulty = difficulty;
  assign cfgColumns    = columns;
  assign cfgSpeed      = speed;

  // ---------------------------------------------------------------- scheduler
  logic                         runStart, stageClear, runDone;
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
  logic [15:0]                  runId;
  logic [7:0]                   gen;
  logic [3:0]                   batch, runIdx;
  logic [15:0]                  seedA, seedB;
  logic [LANES-1:0][CAND_W-1:0] laneCand;
  logic [FIT_W-1:0]             genBest;
  logic [CAND_W-1:0]            genBestCand;
  logic                         genBestValid;
  logic [6:0]                   lastMeanSurv;
  logic [6:0]                   genDone;
  logic                         lastMeanValid;
  logic [7:0][FIT_W-1:0]        topScores;
  logic [7:0][CAND_W-1:0]       topIds;
  logic [7:0]                   topValid;
  logic [31:0]                  evaluated;

  train_ctrl #(
      .POP_FILE       (POP_FILE),
      .HOLD_RUN_FRAMES(HOLD_RUN_FRAMES),
      .HOLD_GEN_FRAMES(HOLD_GEN_FRAMES)
  ) ctrl (
      .clk          (clk),
      .resetN       (resetN),
      .start        (start),
      .abort        (abort),
      .runIdIn      (runIdIn),
      .frameTick    (frameTick),
      .simLevel     (simLevel),
      .runStart     (runStart),
      .runSeed      (runSeed),
      .laneEnable   (laneEnable),
      .stageClear   (stageClear),
      .runDone      (runDone),
      .accG         (accG),
      .accTA        (accTA),
      .accT         (accT),
      .laneWe       (laneWe),
      .laneWa       (laneWa),
      .laneWd       (laneWd),
      .active       (active),
      .stage        (stage),
      .runState     (runState),
      .runId        (runId),
      .gen          (gen),
      .batch        (batch),
      .runIdx       (runIdx),
      .seedA        (seedA),
      .seedB        (seedB),
      .laneCand     (laneCand),
      .genBest      (genBest),
      .genBestCand  (genBestCand),
      .genBestValid (genBestValid),
      .genSumT      (),
      .genDone      (genDone),
      .lastMeanSurv (lastMeanSurv),
      .lastMeanValid(lastMeanValid),
      .topScores    (topScores),
      .topIds       (topIds),
      .topValid     (topValid),
      .evaluated    (evaluated),
      .genPulse     (genPulse)
  );

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
      .abort       (abort),
      .stepGo      (stepGo),
      .hold        (1'b0),
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

  assign liveAlive = enabled & alive & ~done;

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
      sRunId         <= '0;
      sGen           <= '0;
      sBatch         <= '0;
      sRunIdx        <= '0;
      sSeed          <= '0;
      sPlaySteps     <= '0;
      sReadySteps    <= '0;
      sGenBest       <= '0;
      sGenBestCand   <= '0;
      sGenBestValid  <= 1'b0;
      sGenDone       <= '0;
      sLastMean      <= '0;
      sLastMeanValid <= 1'b0;
      sTopScores     <= '0;
      sTopIds        <= '0;
      sTopValid      <= '0;
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
        sRunId         <= runId;
        sGen           <= gen;
        sBatch         <= batch;
        sRunIdx        <= runIdx;
        sSeed          <= (runIdx == 4'd0) ? seedA : seedB;
        sPlaySteps     <= playSteps;
        sReadySteps    <= readySteps;
        sGenBest       <= genBest;
        sGenBestCand   <= genBestCand;
        sGenBestValid  <= genBestValid;
        sGenDone       <= genDone;
        sLastMean      <= lastMeanSurv;
        sLastMeanValid <= lastMeanValid;
        sTopScores     <= topScores;
        sTopIds        <= topIds;
        sTopValid      <= topValid;
        sEvaluated     <= evaluated;
        sStepsPerSec   <= stepsPerSec;
      end
    end
  end

endmodule
