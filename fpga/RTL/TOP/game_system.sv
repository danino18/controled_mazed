// Everything that runs on the pixel clock: VGA timing, keyboard decoding,
// the game rules (game_logic) and the drawing layers. Kept separate from the
// board-specific top level (PLL, precompiled keyboard and codec blocks) so the
// whole game can be simulated.

module game_system
  import palette_pkg::*, game_params_pkg::*, game_state_pkg::*;
(
    input  logic        clk,
    input  logic        resetN,
    input  logic [8:0]  keyCode,      // from the keyboard block
    input  logic        keyMake,
    input  logic        keyBreak,
    input  logic        muteSw,       // SW0: 1 = mute (audio only; never gates gameplay)
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

  // ---------------------------------------------------------------- keyboard
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

  // ---------------------------------------------------------------- game rules
  logic [2:0]                   screen;
  logic [1:0]                   difficulty;
  logic [1:0]                   columnCount;
  logic [1:0]                   menuCursor;
  logic [7:0]                   stateFrames;
  logic signed [10:0]           birdY;
  logic signed [11:0]           birdVy;
  logic [7:0]                   birdTrajState;
  logic signed [9:0]            mazeOffset;
  logic [NUM_COLUMNS-1:0]       colActive;
  logic [NUM_COLUMNS-1:0][10:0] colX;
  logic [NUM_COLUMNS-1:0][9:0]  gapTop;
  logic [NUM_COLUMNS-1:0][9:0]  gapBottom;
  logic                         collision;
  logic [NUM_COLUMNS-1:0]       hitColumn;
  logic [2:0][3:0]              score;
  logic [2:0][3:0]              best;
  logic                         newBest;
  logic [2:0]                   speedLevel;
  logic                         scoreEvent, failEvent;

  game_logic gameLogic (
      .clk          (clk),
      .resetN       (resetN),
      .tickMove     (tickMove),
      .tickCheck    (tickCheck),
      .tickState    (tickState),
      .upHeld       (upHeld),
      .downHeld     (downHeld),
      .upPulse      (upPulse),
      .downPulse    (downPulse),
      .enterPulse   (enterPulse),
      .speedUpHeld  (speedUpHeld),
      .speedDownHeld(speedDownHeld),
      .aiMode       (1'b0),          // AI arrives in the ML phase
      .aiUp         (1'b0),
      .aiDown       (1'b0),
      .aiValid      (1'b0),
      .screen       (screen),
      .difficulty   (difficulty),
      .columnCount  (columnCount),
      .menuCursor   (menuCursor),
      .stateFrames  (stateFrames),
      .birdY        (birdY),
      .birdVy       (birdVy),
      .birdTrajState(birdTrajState),
      .mazeOffset   (mazeOffset),
      .colActive    (colActive),
      .colX         (colX),
      .gapTop       (gapTop),
      .gapBottom    (gapBottom),
      .collision    (collision),
      .hitColumn    (hitColumn),
      .score        (score),
      .best         (best),
      .newBest      (newBest),
      .speedLevel   (speedLevel),
      .scoreEvent   (scoreEvent),
      .failEvent    (failEvent)
  );

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

  assign coralShown = inMenu ? '0 : colActive;

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

  objects_mux_top mux (
      .clk                (clk),
      .resetN             (resetN),
      .speedDrawingRequest(speedDR),
      .speedRGB           (speedRGB),
      .textDrawingRequest (textDR),
      .textRGB            (textRGB),
      .panelDrawingRequest(panelDR),
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
  // LEDR[4:2] = game screen, LEDR[6:5] = difficulty, LEDR[8:7] = coral columns.
  assign LEDR = {blink, columnCount, difficulty, screen, resetN, 1'b0};

endmodule
