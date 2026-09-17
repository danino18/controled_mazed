// Everything that runs on the pixel clock: VGA timing, keyboard decoding,
// mode selection (HUMAN PLAY / TRAIN AI / WATCH AI), the game rules
// (game_logic), the AI player and the drawing layers. Kept separate from the
// board-specific top level (PLL, precompiled keyboard and codec blocks) so the
// whole system can be simulated.

module game_system
  import palette_pkg::*, game_params_pkg::*, game_state_pkg::*, ml_pkg::*, ui_pkg::*;
#(
    parameter int BUTTON_STABLE_CLOCKS = 630_000,   // KEY1 debounce (~20 ms)
    parameter bit DEMO_NET             = 1'b1       // M9: the hand-set network may be watched
) (
    input  logic        clk,
    input  logic        resetN,
    input  logic [8:0]  keyCode,      // from the keyboard block
    input  logic        keyMake,
    input  logic        keyBreak,
    input  logic        muteSw,       // SW0: 1 = mute (audio only; never gates gameplay)
    input  logic        debugSw,      // SW1: AI debug overlay in WATCH AI
    input  logic        backN,        // KEY1 (active low): back / pause
    output logic [28:0] OVGA,
    output logic [6:0]  HEX0,
    output logic [6:0]  HEX1,
    output logic [6:0]  HEX2,
    output logic [6:0]  HEX3,
    output logic [6:0]  HEX4,
    output logic [6:0]  HEX5,
    output logic [9:0]  LEDR,
    output logic [15:0] audioSample   // signed PCM; controlled_maze_top feeds this to the codec
);

  // ---------------------------------------------------------------- VGA timing
  logic [10:0] pixelX;
  logic [10:0] pixelY;
  logic        startOfFrame;
  color_t      screenRGB;

  VGA_Controller vga (
      .RGBIn       (screenRGB),
      .PixelX      (pixelX),
      .PixelY      (pixelY),
      .startOfFrame(startOfFrame),
      .oVGA        (OVGA),
      .address     (),
      .clk         (clk),
      .resetN      (resetN)
  );

  logic tickMove, tickCheck, tickState;

  frame_sequencer sequencer (
      .clk         (clk),
      .resetN      (resetN),
      .startOfFrame(startOfFrame),
      .tickMove    (tickMove),
      .tickCheck   (tickCheck),
      .tickState   (tickState)
  );

  logic [5:0] frameCount;
  logic       blink;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN)           frameCount <= '0;
    else if (startOfFrame) frameCount <= frameCount + 6'd1;
  end

  assign blink = frameCount[5];

  // ---------------------------------------------------------------- keyboard, KEY1, SW1
  logic upHeld, downHeld, upPulse, downPulse, enterPulse;
  logic speedUpHeld, speedDownHeld;

  key_input keys (
      .clk          (clk),
      .resetN       (resetN),
      .keyCode      (keyCode),
      .keyMake      (keyMake),
      .keyBreak     (keyBreak),
      .upHeld       (upHeld),
      .downHeld     (downHeld),
      .upPulse      (upPulse),
      .downPulse    (downPulse),
      .enterPulse   (enterPulse),
      .speedUpHeld  (speedUpHeld),
      .speedDownHeld(speedDownHeld)
  );

  logic backPulse;

  button_pulse #(.STABLE_CLOCKS(BUTTON_STABLE_CLOCKS)) backButton (
      .clk    (clk),
      .resetN (resetN),
      .buttonN(backN),
      .pressed(),
      .pulse  (backPulse)
  );

  logic debugSync1, debugOn;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      debugSync1 <= 1'b0;
      debugOn    <= 1'b0;
    end else begin
      debugSync1 <= debugSw;
      debugOn    <= debugSync1;
    end
  end

  // ---------------------------------------------------------------- modes
  logic [2:0] mode;
  logic [1:0] modeCursor;
  logic       aiMode, trainMode, gameKeys, gameVisible, abortGame;
  logic       trainGo, trainStop, trainAbort, trainScreen, watchAuto, watchLoad;
  logic [3:0] page;
  logic [2:0] screen;
  logic       menuStartGame;   // not exported by game_logic; see below
  logic       trainStart;
  logic       watchValid;

  // committed AI (train_top) and JTAG requests (train_probe), declared here for mode_fsm
  logic       trainActive, trainComplete, aiCommitted;
  logic [1:0] aiDifficulty, aiColumns;
  logic [2:0] aiSpeed;
  logic       remoteStart, remoteStop, remoteExit;

  assign watchValid = aiCommitted || DEMO_NET;

  // game_fsm's first menu comes back after MAIN MENU on GAME OVER
  logic [2:0] screenD;
  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) screenD <= ST_MENU_DIFF;
    else         screenD <= screen;
  end
  assign menuStartGame = (screen == ST_MENU_DIFF) && (screenD == ST_GAME_OVER);

  mode_fsm modes (
      .clk        (clk),
      .resetN     (resetN),
      .upPulse    (upPulse),
      .downPulse  (downPulse),
      .enterPulse (enterPulse),
      .backPulse  (backPulse),
      .debugSw    (debugOn),
      .watchValid   (watchValid),
      .watchTrained (aiCommitted),
      .screen       (screen),
      .menuStart    (menuStartGame),
      .trainStart   (trainStart),
      .trainActive  (trainActive),
      .trainComplete(trainComplete),
      .remoteStart  (remoteStart),
      .remoteStop   (remoteStop),
      .remoteExit   (remoteExit),
      .mode         (mode),
      .cursor       (modeCursor),
      .aiMode       (aiMode),
      .trainMode    (trainMode),
      .gameKeys     (gameKeys),
      .gameVisible  (gameVisible),
      .abortGame    (abortGame),
      .trainGo      (trainGo),
      .trainStop    (trainStop),
      .trainAbort   (trainAbort),
      .trainScreen  (trainScreen),
      .watchAuto    (watchAuto),
      .watchLoad    (watchLoad),
      .page         (page)
  );

  // ---------------------------------------------------------------- game rules
  logic [1:0]                   difficulty;
  logic [1:0]                   columnCount;
  logic [1:0]                   menuCursor;
  logic [7:0]                   stateFrames;
  logic signed [10:0]           birdY;
  logic signed [11:0]           birdVy;
  logic [7:0]                   birdTrajState;
  logic signed [9:0]            mazeOffset;
  logic signed [4:0]            mazeVy;
  logic [NUM_COLUMNS-1:0]       colActive;
  logic [NUM_COLUMNS-1:0][10:0] colX;
  logic [NUM_COLUMNS-1:0][8:0]  gapBase;
  logic [NUM_COLUMNS-1:0][9:0]  gapTop;
  logic [NUM_COLUMNS-1:0][9:0]  gapBottom;
  logic                         collision;
  logic [NUM_COLUMNS-1:0]       hitColumn;
  logic [2:0][3:0]              score;
  logic [2:0][3:0]              best;
  logic                         newBest;
  logic [2:0]                   speedLevel;
  logic                         scoreEvent, failEvent;
  logic                         aiUp, aiDown, aiValid;

  game_logic gameLogic (
      .clk           (clk),
      .resetN        (resetN),
      .tickMove      (tickMove),
      .tickCheck     (tickCheck),
      .tickState     (tickState),
      // keys reach the game only in its own modes; the AI replaces the maze keys
      .upHeld        (gameKeys && !aiMode && upHeld),
      .downHeld      (gameKeys && !aiMode && downHeld),
      .upPulse       (gameKeys && upPulse),
      .downPulse     (gameKeys && downPulse),
      .enterPulse    (gameKeys && enterPulse),
      .speedUpHeld   (gameKeys && speedUpHeld),
      .speedDownHeld (gameKeys && speedDownHeld),
      .entropyPulse  (upPulse || downPulse || enterPulse || backPulse),
      .aiMode        (aiMode),
      .aiUp          (aiUp),
      .aiDown        (aiDown),
      .aiValid       (aiValid),
      .trainMode     (trainMode),
      .autoStart     (watchAuto),       // WATCH AI of a trained network: its training world
      .autoDifficulty(aiDifficulty),
      .autoColumns   (aiColumns),
      .abort         (abortGame),
      .speedLoad     (watchLoad),
      .speedLoadLevel(aiSpeed),
      .trainStart    (trainStart),
      .screen        (screen),
      .difficulty    (difficulty),
      .columnCount   (columnCount),
      .menuCursor    (menuCursor),
      .stateFrames   (stateFrames),
      .birdY         (birdY),
      .birdVy        (birdVy),
      .birdTrajState (birdTrajState),
      .mazeOffset    (mazeOffset),
      .mazeVy        (mazeVy),
      .colActive     (colActive),
      .colX          (colX),
      .gapBase       (gapBase),
      .gapTop        (gapTop),
      .gapBottom     (gapBottom),
      .collision     (collision),
      .hitColumn     (hitColumn),
      .score         (score),
      .best          (best),
      .newBest       (newBest),
      .speedLevel    (speedLevel),
      .scoreEvent    (scoreEvent),
      .failEvent     (failEvent)
  );

  // ---------------------------------------------------------------- AI player (WATCH AI)
  logic [NN_INPUTS-1:0][7:0] aiFeat;
  logic signed [ACC_W-1:0]   aiY;
  logic signed [7:0]         aiH0;

  // the WATCH memory is written by the trainer when a training run completes
  logic                   watchWe;
  logic [GENE_ADDR_W-1:0] watchWa;
  logic [7:0]             watchWd;

  ai_player #(.NET_FILE(DEMO_NET ? "RTL/MIF/nn_demo.mif" : "UNUSED")) ai (
      .clk       (clk),
      .resetN    (resetN),
      .enable    (aiMode),
      .tickState (tickState),
      .birdY     (birdY),
      .birdVy    (birdVy),
      .colActive (colActive),
      .colX      (colX),
      .gapTop    (gapTop),
      .mazeVy    (mazeVy),
      .speedLevel(speedLevel),
      .netWe     (watchWe),
      .netWa     (watchWa),
      .netWd     (watchWd),
      .aiUp      (aiUp),
      .aiDown    (aiDown),
      .aiValid   (aiValid),
      .feat      (aiFeat),
      .y         (aiY),
      .h0        (aiH0)
  );

  // the maze action actually applied on the last move (for the overlay and LEDs)
  logic [1:0] appliedAction;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN)
      appliedAction <= ACT_HOLD;
    else if (tickMove)
      appliedAction <= (aiValid && screen == ST_PLAY) ? {aiUp, aiDown} : ACT_HOLD;
  end

  // ---------------------------------------------------------------- on-chip training (TRAIN AI)
  // Numpad 4/6 set the simulation speed while the training screen is shown
  // (the same stepping rules as the world speed, level 2 = x4 after reset);
  // game_logic does not see those keys then, so the world speed to train on
  // cannot change.
  logic [2:0] simKeyLevel, simLevel;

  world_speed_control simSpeed (
      .clk          (clk),
      .resetN       (resetN),
      .tick         (startOfFrame),
      .speedUpHeld  (trainScreen && speedUpHeld),
      .speedDownHeld(trainScreen && speedDownHeld),
      .load         (1'b0),
      .loadLevel    (3'd0),
      .speedLevel   (simKeyLevel),
      .worldStep    ()
  );

  // RUN ID: the supplied random.sv latched by the Enter press (or the JTAG
  // request) that starts training
  logic [15:0] runEntropy;

  random #(.SIZE_BITS(16), .MIN_VAL(16'h0000), .MAX_VAL(16'hFFFF)) runIdSource (
      .clk   (clk),
      .resetN(resetN),
      .rise  (enterPulse || remoteStart),
      .dout  (runEntropy)
  );

  // JTAG measurement and control (In-System Sources and Probes "TRNP")
  logic [191:0] probeData;
  logic [1:0]   remoteDifficulty, remoteColumns;
  logic [2:0]   remoteSpeed, remoteSimLevel;
  logic         remoteSim;

  train_probe probe (
      .clk        (clk),
      .resetN     (resetN),
      .probe      (probeData),
      .startReq   (remoteStart),
      .stopReq    (remoteStop),
      .exitReq    (remoteExit),
      .difficulty (remoteDifficulty),
      .columns    (remoteColumns),
      .speed      (remoteSpeed),
      .simOverride(remoteSim),
      .simLevel   (remoteSimLevel),
      .marker     ()
  );

  assign simLevel = remoteSim ? remoteSimLevel : simKeyLevel;

  logic                                 trainGenPulse;
  logic [LANES-1:0]                     trainAlive;
  logic [1:0]                           trainDifficulty, trainColumns;
  logic [2:0]                           trainSpeed;
  logic [15:0]                          aiRunId;
  logic [7:0]                           aiGen;
  logic [3:0]                           aiValW, aiTestW;
  logic [9:0]                           aiValGates, aiTestGates;
  logic                                 aiTestValid;
  logic                                 histWe;
  logic [6:0]                           histWa;
  logic [20:0]                          histWd;
  logic [LANES-1:0][1:0]                sLaneState, sLaneAct;
  logic [LANES-1:0][CAND_W-1:0]         sLaneCand;
  logic [LANES-1:0][9:0]                sLaneGates;
  logic [LANES-1:0][FIT_W-1:0]          sLaneFit;
  logic [LANES-1:0][11:0]               sLaneSteps;
  logic [LANES-1:0][10:0]               sViewBirdY;
  logic [LANES-1:0][NUM_COLUMNS-1:0]    sViewActive;
  logic [LANES-1:0][NUM_COLUMNS*11-1:0] sViewColX;
  logic [LANES-1:0][NUM_COLUMNS*10-1:0] sViewGapTop;
  logic [2:0]                           sStage, sRunState;
  logic [3:0]                           sWorld, sBatch;
  logic [15:0]                          sRunId, sSeed;
  logic [7:0]                           sGen, sChampGen;
  logic [11:0]                          sPlaySteps;
  logic [6:0]                           sReadySteps, sGenDone, sLastMean, sValTopSurv, sChampSurv, sTestSurv;
  logic [FIT_W-1:0]                     sGenBest, sPrevBest, sValTop, sChampScore, sTestScore;
  logic [CAND_W-1:0]                    sGenBestCand, sValTopCand, sChampCand;
  logic                                 sGenBestValid, sPrevBestValid, sLastMeanValid, sValTopValid;
  logic                                 sChampExists, sTestValid;
  logic [3:0]                           sValTopW, sChampW, sTestW;
  logic [5:0]                           sStall;
  logic [1:0]                           sMutLevel, sDoneReason;
  logic [31:0]                          sEvaluated;
  logic [19:0]                          sStepsPerSec;

  train_top trainer (
      .clk           (clk),
      .resetN        (resetN),
      .start         (trainStart || trainGo),
      .stop          (trainStop),
      .abort         (trainAbort),
      .hold          (1'b0),
      .runIdIn       (runEntropy),
      .difficultyIn  (trainGo ? remoteDifficulty : difficulty),
      .columnsIn     (trainGo ? remoteColumns : columnCount),
      .speedIn       (trainGo ? remoteSpeed : speedLevel),
      .simLevel      (simLevel),
      .frameTick     (startOfFrame),
      .active        (trainActive),
      .complete      (trainComplete),
      .liveAlive     (trainAlive),
      .genPulse      (trainGenPulse),
      .watchWe       (watchWe),
      .watchWa       (watchWa),
      .watchWd       (watchWd),
      .aiValid       (aiCommitted),
      .aiDifficulty  (aiDifficulty),
      .aiColumns     (aiColumns),
      .aiSpeed       (aiSpeed),
      .aiRunId       (aiRunId),
      .aiGen         (aiGen),
      .aiValW        (aiValW),
      .aiValGates    (aiValGates),
      .aiTestW       (aiTestW),
      .aiTestGates   (aiTestGates),
      .aiTestValid   (aiTestValid),
      .histWe        (histWe),
      .histWa        (histWa),
      .histWd        (histWd),
      .snapTaken     (),
      .cfgDifficulty (trainDifficulty),
      .cfgColumns    (trainColumns),
      .cfgSpeed      (trainSpeed),
      .sLaneState    (sLaneState),
      .sLaneCand     (sLaneCand),
      .sLaneAct      (sLaneAct),
      .sLaneGates    (sLaneGates),
      .sLaneFit      (sLaneFit),
      .sLaneSteps    (sLaneSteps),
      .sViewBirdY    (sViewBirdY),
      .sViewActive   (sViewActive),
      .sViewColX     (sViewColX),
      .sViewGapTop   (sViewGapTop),
      .sStage        (sStage),
      .sRunState     (sRunState),
      .sWorld        (sWorld),
      .sRunId        (sRunId),
      .sGen          (sGen),
      .sBatch        (sBatch),
      .sSeed         (sSeed),
      .sPlaySteps    (sPlaySteps),
      .sReadySteps   (sReadySteps),
      .sGenBest      (sGenBest),
      .sGenBestCand  (sGenBestCand),
      .sGenBestValid (sGenBestValid),
      .sPrevBest     (sPrevBest),
      .sPrevBestValid(sPrevBestValid),
      .sGenDone      (sGenDone),
      .sLastMean     (sLastMean),
      .sLastMeanValid(sLastMeanValid),
      .sValTop       (sValTop),
      .sValTopW      (sValTopW),
      .sValTopSurv   (sValTopSurv),
      .sValTopCand   (sValTopCand),
      .sValTopValid  (sValTopValid),
      .sChampExists  (sChampExists),
      .sChampScore   (sChampScore),
      .sChampW       (sChampW),
      .sChampSurv    (sChampSurv),
      .sChampGen     (sChampGen),
      .sChampCand    (sChampCand),
      .sStall        (sStall),
      .sMutLevel     (sMutLevel),
      .sTestScore    (sTestScore),
      .sTestW        (sTestW),
      .sTestSurv     (sTestSurv),
      .sTestValid    (sTestValid),
      .sDoneReason   (sDoneReason),
      .sEvaluated    (sEvaluated),
      .sStepsPerSec  (sStepsPerSec)
  );

  // what the JTAG probe reports (layout: tools/train_probe.tcl)
  assign probeData = {
      1'b0,                       // 191
      trainActive,                // 190
      sDoneReason,                // 189:188
      sEvaluated,                 // 187:156
      sRunId,                     // 155:140
      sTestValid,                 // 139
      sTestSurv,                  // 138:132
      sTestW,                     // 131:128
      sTestScore,                 // 127:102
      sChampExists,               // 101
      sStepsPerSec,               // 100:81
      aiCommitted,                // 80
      trainComplete,              // 79
      sRunState,                  // 78:76
      sStage,                     // 75:73
      sStall,                     // 72:67
      sLastMean,                  // 66:60
      sValTopSurv,                // 59:53
      sChampSurv,                 // 52:46
      sChampW,                    // 45:42
      sChampScore,                // 41:16
      sChampGen,                  // 15:8
      sGen                        // 7:0
  };

  logic trainBeat;     // LEDR9 in TRAIN AI: toggles once per generation

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN)            trainBeat <= 1'b0;
    else if (trainGenPulse) trainBeat <= !trainBeat;
  end

  // ---------------------------------------------------------------- sound
  sound_engine sound (
      .clk         (clk),
      .resetN      (resetN),
      .scoreTrigger(scoreEvent),
      .failTrigger (failEvent),
      .mute        (muteSw),
      .audioSample (audioSample),
      .playingScore(),   // test-only debug outputs; tb_sound.sv instantiates sound_engine directly
      .playingFail ()
  );

  logic inMenu, crashed, flash;

  assign inMenu  = (screen == ST_MENU_DIFF) || (screen == ST_MENU_OBST);
  assign crashed = (screen == ST_HIT) || (screen == ST_GAME_OVER);
  assign flash   = (screen == ST_HIT) && (stateFrames < 8'd8);

  // ---------------------------------------------------------------- drawing
  color_t waterRGB;

  water_background water (
      .clk   (clk),
      .resetN(resetN),
      .pixelX(pixelX),
      .pixelY(pixelY),
      .RGBout(waterRGB)
  );

  logic                   coralDR;
  color_t                 coralRGB;
  logic [NUM_COLUMNS-1:0] coralShown;

  assign coralShown = (inMenu || !gameVisible) ? '0 : colActive;

  coral_draw coralDraw (
      .clk           (clk),
      .resetN        (resetN),
      .pixelX        (pixelX),
      .pixelY        (pixelY),
      .active        (coralShown),
      .colX          (colX),
      .gapTop        (gapTop),
      .gapBottom     (gapBottom),
      .drawingRequest(coralDR),
      .RGBout        (coralRGB)
  );

  logic   birdDR;
  color_t birdRGB;

  bird_draw birdDraw (
      .clk           (clk),
      .resetN        (resetN),
      .pixelX        (pixelX),
      .pixelY        (pixelY),
      .birdY         (birdY),
      .tick          (tickMove),
      .animate       (!crashed),
      .blink         (screen == ST_HIT),
      .drawingRequest(birdDR),
      .RGBout        (birdRGB)
  );

  logic   textDR;
  color_t textRGB;

  text_draw text (
      .clk           (clk),
      .resetN        (resetN),
      .pixelX        (pixelX),
      .pixelY        (pixelY),
      .screen        (screen),
      .menuCursor    (menuCursor),
      .scoreDigits   (score),
      .bestDigits    (best),
      .newBest       (newBest),
      .blink         (blink),
      .drawingRequest(textDR),
      .RGBout        (textRGB)
  );

  logic   speedDR;
  color_t speedRGB;

  speed_readout speedReadout (
      .clk           (clk),
      .resetN        (resetN),
      .pixelX        (pixelX),
      .pixelY        (pixelY),
      .screen        (screen),
      .speedLevel    (speedLevel),
      .drawingRequest(speedDR),
      .RGBout        (speedRGB)
  );

  logic   panelDR;
  color_t panelRGB;

  ui_panels panels (
      .clk           (clk),
      .resetN        (resetN),
      .pixelX        (pixelX),
      .pixelY        (pixelY),
      .screen        (screen),
      .menuCursor    (menuCursor),
      .flash         (flash),
      .drawingRequest(panelDR),
      .RGBout        (panelRGB)
  );

  // text screens: menus, AI overlay
  logic [NUM_SOURCES-1:0][31:0] uiSources;

  always_comb begin
    uiSources = '0;
    uiSources[SRC_MODE_CURSOR]  = 32'(modeCursor);
    uiSources[SRC_NOAI_CURSOR]  = 32'(modeCursor);
    uiSources[SRC_AI_ACTION]    = (appliedAction == ACT_UP) ? 32'd2 : (appliedAction == ACT_DOWN) ? 32'd1 : 32'd0;
    uiSources[SRC_AI_F0]        = 32'($signed(aiFeat[0]));
    uiSources[SRC_AI_F1]        = 32'($signed(aiFeat[1]));
    uiSources[SRC_AI_F2]        = 32'($signed(aiFeat[2]));
    uiSources[SRC_AI_F3]        = 32'($signed(aiFeat[3]));
    uiSources[SRC_AI_H0]        = 32'(aiH0);
    uiSources[SRC_AI_Y]         = 32'(aiY);
    uiSources[SRC_WORLD_SPEED]  = 32'(speedLevel);
    uiSources[SRC_TRAIN_DIFF]   = 32'(trainDifficulty);
    uiSources[SRC_TRAIN_CORALS] = 32'(trainColumns);
    uiSources[SRC_TRAIN_SPEED]  = 32'(trainSpeed);

    // training screen: everything below comes from the trainer's per-frame snapshot
    uiSources[SRC_TR_RUNID]      = 32'(sRunId);
    uiSources[SRC_TR_GEN]        = 32'(sGen);
    uiSources[SRC_TR_BATCH]      = 32'(sBatch) + 32'd1;
    uiSources[SRC_TR_SIM]        = 32'(simLevel);
    uiSources[SRC_TR_STAGE]      = 32'(sStage);
    uiSources[SRC_TR_RUNSTATE]   = 32'(sRunState);
    uiSources[SRC_TR_WORLD]      = 32'(sWorld);
    uiSources[SRC_TR_SEED]       = 32'(sSeed);
    uiSources[SRC_TR_STEP]       = 32'(sPlaySteps);
    uiSources[SRC_TR_READY]      = 32'(sReadySteps);
    uiSources[SRC_TR_SPS]        = 32'(sStepsPerSec);
    uiSources[SRC_TR_EVALS]      = sEvaluated;
    uiSources[SRC_TR_BEST]       = sGenBestValid ? 32'(sGenBest) : 32'd0;
    uiSources[SRC_TR_BEST_GATES] = sGenBestValid ? 32'(sGenBest[FIT_W-1:16]) : 32'd0;
    uiSources[SRC_TR_BEST_CAND]  = sGenBestValid ? 32'(sGenBestCand) : 32'd0;
    uiSources[SRC_TR_BATCHES]    = 32'(sGenDone) >> 3;
    uiSources[SRC_TR_DONE_CANDS] = 32'(sGenDone);
    uiSources[SRC_TR_LAST_MEAN]  = 32'(sLastMean);
    for (int k = 0; k < LANES; k++) begin
      uiSources[SRC_L0_CAND  + 6 * k] = 32'(sLaneCand[k]);
      uiSources[SRC_L0_STATE + 6 * k] = 32'(sLaneState[k]);
      uiSources[SRC_L0_ACT   + 6 * k] = (sLaneAct[k] == ACT_UP) ? 32'd2 : (sLaneAct[k] == ACT_DOWN) ? 32'd1 : 32'd0;
      uiSources[SRC_L0_GATES + 6 * k] = 32'(sLaneGates[k]);
      uiSources[SRC_L0_FIT   + 6 * k] = 32'(sLaneFit[k]);
      uiSources[SRC_L0_STEPS + 6 * k] = 32'(sLaneSteps[k]);
    end
    uiSources[SRC_TR_PREV_BEST]  = sPrevBestValid ? 32'(sPrevBest) : 32'd0;
    uiSources[SRC_VAL_TOP]       = sValTopValid ? 32'(sValTop) : 32'd0;
    uiSources[SRC_VAL_TOP_GATES] = sValTopValid ? 32'(sValTop[FIT_W-1:16]) : 32'd0;
    uiSources[SRC_VAL_TOP_W]     = sValTopValid ? 32'(sValTopW) : 32'd0;
    uiSources[SRC_VAL_TOP_CAND]  = sValTopValid ? 32'(sValTopCand) : 32'd0;
    uiSources[SRC_CH_SCORE]      = sChampExists ? 32'(sChampScore) : 32'd0;
    uiSources[SRC_CH_GATES]      = sChampExists ? 32'(sChampScore[FIT_W-1:16]) : 32'd0;
    uiSources[SRC_CH_W]          = sChampExists ? 32'(sChampW) : 32'd0;
    uiSources[SRC_CH_SURV]       = sChampExists ? 32'(sChampSurv) : 32'd0;
    uiSources[SRC_CH_GEN]        = sChampExists ? 32'(sChampGen) : 32'd0;
    uiSources[SRC_CH_CAND]       = sChampExists ? 32'(sChampCand) : 32'd0;
    uiSources[SRC_TR_STALL]      = 32'(sStall);
    uiSources[SRC_TR_MUT]        = 32'(sMutLevel);
    uiSources[SRC_TEST_SCORE]    = sTestValid ? 32'(sTestScore) : 32'd0;
    uiSources[SRC_TEST_GATES]    = sTestValid ? 32'(sTestScore[FIT_W-1:16]) : 32'd0;
    uiSources[SRC_TEST_W]        = sTestValid ? 32'(sTestW) : 32'd0;
    uiSources[SRC_TEST_SURV]     = sTestValid ? 32'(sTestSurv) : 32'd0;
    uiSources[SRC_TR_RESULT]     = (sStage == STG_COMPLETE) ? 32'(sDoneReason) + 32'd1 : 32'd0;

    // WATCH overlays: which network is playing
    uiSources[SRC_AI_KIND]       = aiCommitted ? 32'd1 : 32'd0;
    uiSources[SRC_AI_RUNID]      = aiCommitted ? 32'(aiRunId) : 32'd0;
    uiSources[SRC_AI_GENS]       = aiCommitted ? 32'(aiGen) : 32'd0;
    uiSources[SRC_AI_VALW]       = aiCommitted ? 32'(aiValW) : 32'd0;
    uiSources[SRC_AI_TESTW]      = aiCommitted ? 32'(aiTestW) : 32'd0;
  end

  // The text writer starts SNAP_DELAY clocks after the frame starts, after the
  // trainer has granted its snapshot (at most STEP_CLOCKS clocks), so every
  // value of a frame comes from the same simulated step.
  localparam int SNAP_DELAY = 64;
  logic [6:0] snapDelay;
  logic       textFrame;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      snapDelay <= '0;
      textFrame <= 1'b0;
    end else begin
      textFrame <= (snapDelay == 7'(SNAP_DELAY));
      if (startOfFrame)          snapDelay <= 7'd1;
      else if (snapDelay != 7'd0) snapDelay <= (snapDelay == 7'(SNAP_DELAY)) ? 7'd0 : snapDelay + 7'd1;
    end
  end

  // training screen graphics: learning chart over the lane windows and backdrop
  logic   trainDR, laneDR, chartDR;
  color_t trainRGB, laneRGB, chartRGB;

  chart_draw chart (
      .clk           (clk),
      .resetN        (resetN),
      .pixelX        (pixelX),
      .pixelY        (pixelY),
      .enable        (trainScreen),
      .count         (sGen),
      .histWe        (histWe),
      .histWa        (histWa),
      .histWd        (histWd),
      .drawingRequest(chartDR),
      .RGBout        (chartRGB)
  );

  assign trainDR  = chartDR || laneDR;
  assign trainRGB = chartDR ? chartRGB : laneRGB;

  lane_view_draw laneViews (
      .clk           (clk),
      .resetN        (resetN),
      .pixelX        (pixelX),
      .pixelY        (pixelY),
      .enable        (trainScreen),
      .laneState     (sLaneState),
      .viewBirdY     (sViewBirdY),
      .viewActive    (sViewActive),
      .viewColX      (sViewColX),
      .viewGapTop    (sViewGapTop),
      .drawingRequest(laneDR),
      .RGBout        (laneRGB)
  );

  logic   charDR;
  color_t charRGB;

  char_screen textScreens (
      .clk           (clk),
      .resetN        (resetN),
      .pixelX        (pixelX),
      .pixelY        (pixelY),
      .startOfFrame  (textFrame),
      .page          (page),
      .sources       (uiSources),
      .drawingRequest(charDR),
      .RGBout        (charRGB),
      .shown         (),
      .writerIdle    ()
  );

  objects_mux_top mux (
      .clk                (clk),
      .resetN             (resetN),
      .charDrawingRequest (charDR),
      .charRGB            (charRGB),
      .trainDrawingRequest(trainDR),
      .trainRGB           (trainRGB),
      .speedDrawingRequest(speedDR && gameVisible),
      .speedRGB           (speedRGB),
      .textDrawingRequest (textDR && gameVisible),
      .textRGB            (textRGB),
      .panelDrawingRequest(panelDR && gameVisible),
      .panelRGB           (panelRGB),
      .birdDrawingRequest (birdDR),
      .birdRGB            (birdRGB),
      .coralDrawingRequest(coralDR),
      .coralRGB           (coralRGB),
      .backgroundRGB      (waterRGB),
      .RGBOut             (screenRGB)
  );

  // ---------------------------------------------------------------- indicators
  // Game modes: HEX2..HEX0 = current score, HEX5..HEX3 = best score.
  // TRAIN AI:   HEX5..HEX3 = generation, HEX2..HEX0 = champion's validation gates.
  // Leading zeros are blanked.
  function automatic logic [2:0][3:0] bcd3(input logic [9:0] v);
    int n;
    n = (int'(v) > 999) ? 999 : int'(v);
    return {4'(n / 100), 4'((n / 10) % 10), 4'(n % 10)};
  endfunction

  logic [2:0][3:0] hexLow, hexHigh;
  logic [2:0]      lowOn, highOn;

  always_comb begin
    if (trainScreen) begin
      hexHigh = bcd3(10'(sGen));
      hexLow  = bcd3(sChampExists ? sChampScore[FIT_W-1:16] : 10'd0);
    end else begin
      hexHigh = best;
      hexLow  = score;
    end
  end

  leading_zero_blank #(.DIGITS(3)) lowBlank  (.digits(hexLow),  .digitOn(lowOn));
  leading_zero_blank #(.DIGITS(3)) highBlank (.digits(hexHigh), .digitOn(highOn));

  hex_display_top hex (
      .clk    (clk),
      .resetN (resetN),
      .digits ({hexHigh, hexLow}),
      .digitOn({highOn, lowOn}),
      .HEX0   (HEX0),
      .HEX1   (HEX1),
      .HEX2   (HEX2),
      .HEX3   (HEX3),
      .HEX4   (HEX4),
      .HEX5   (HEX5)
  );

  // LEDR[0] is driven by the board top level (PLL locked).
  // LEDR[4:2] = game screen, LEDR[6:5] = difficulty, LEDR[8:7] = coral columns,
  // LEDR[9] = heartbeat. In WATCH AI: LEDR[9] = maze up, LEDR[8] = maze down.
  // In TRAIN AI: LEDR[8:1] = lanes 7..0 alive, LEDR[9] toggles once per generation.
  always_comb begin
    LEDR = {blink, columnCount, difficulty, screen, resetN, 1'b0};
    if (aiMode) LEDR[9:8] = {appliedAction == ACT_UP, appliedAction == ACT_DOWN};
    if (trainScreen) LEDR = {trainBeat, trainAlive, 1'b0};
  end

endmodule
