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
  logic [2:0] page;
  logic [2:0] screen;
  logic       menuStartGame;   // not exported by game_logic; see below
  logic       trainStart;
  logic       watchValid;

  assign watchValid = DEMO_NET;

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
      .watchValid (watchValid),
      .screen     (screen),
      .menuStart  (menuStartGame),
      .trainStart (trainStart),
      .mode       (mode),
      .cursor     (modeCursor),
      .aiMode     (aiMode),
      .trainMode  (trainMode),
      .gameKeys   (gameKeys),
      .gameVisible(gameVisible),
      .abortGame  (abortGame),
      .page       (page)
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
      .autoStart     (1'b0),            // WATCH AI of a trained network: M12
      .autoDifficulty(2'd0),
      .autoColumns   (2'd1),
      .abort         (abortGame),
      .speedLoad     (1'b0),
      .speedLoadLevel(3'd0),
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

  ai_player ai (
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
      .netWe     (1'b0),                // committed training results: M12
      .netWa     ('0),
      .netWd     ('0),
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

  // ---------------------------------------------------------------- training setup (engine: M10)
  logic [1:0] trainDifficulty, trainColumns;
  logic [2:0] trainSpeed;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      trainDifficulty <= DIFF_EASY;
      trainColumns    <= 2'd1;
      trainSpeed      <= '0;
    end else if (trainStart) begin
      trainDifficulty <= difficulty;
      trainColumns    <= columnCount;
      trainSpeed      <= speedLevel;
    end
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
  end

  logic   charDR;
  color_t charRGB;

  char_screen textScreens (
      .clk           (clk),
      .resetN        (resetN),
      .pixelX        (pixelX),
      .pixelY        (pixelY),
      .startOfFrame  (startOfFrame),
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
  // HEX2..HEX0 = current score, HEX5..HEX3 = best score, leading zeros blanked.
  logic [2:0] scoreOn, bestOn;

  leading_zero_blank #(.DIGITS(3)) scoreBlank (.digits(score), .digitOn(scoreOn));
  leading_zero_blank #(.DIGITS(3)) bestBlank  (.digits(best),  .digitOn(bestOn));

  hex_display_top hex (
      .clk    (clk),
      .resetN (resetN),
      .digits ({best, score}),
      .digitOn({bestOn, scoreOn}),
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
  always_comb begin
    LEDR = {blink, columnCount, difficulty, screen, resetN, 1'b0};
    if (aiMode) LEDR[9:8] = {appliedAction == ACT_UP, appliedAction == ACT_DOWN};
  end

endmodule
