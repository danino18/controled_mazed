// Everything that runs on the pixel clock: VGA timing, game logic and drawing.
// Kept separate from the board-specific top level (PLL, precompiled keyboard
// and codec blocks) so the whole game can be simulated.

module game_system
  import palette_pkg::*, game_params_pkg::*, game_state_pkg::*;
(
    input  logic        clk,
    input  logic        resetN,
    input  logic [8:0]  keyCode,      // from the keyboard block
    input  logic        keyMake,
    input  logic        keyBreak,
    output logic [28:0] OVGA,
    output logic [6:0]  HEX0,
    output logic [6:0]  HEX1,
    output logic [6:0]  HEX2,
    output logic [6:0]  HEX3,
    output logic [6:0]  HEX4,
    output logic [6:0]  HEX5,
    output logic [9:0]  LEDR
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

  key_input keys (
      .clk       (clk),
      .resetN    (resetN),
      .keyCode   (keyCode),
      .keyMake   (keyMake),
      .keyBreak  (keyBreak),
      .upHeld    (upHeld),
      .downHeld  (downHeld),
      .upPulse   (upPulse),
      .downPulse (downPulse),
      .enterPulse(enterPulse)
  );

  // ---------------------------------------------------------------- round control (temporary until game_fsm, M6)
  // A round starts after reset; a collision freezes the world; Enter restarts.
  logic roundStart;
  logic roundOver;
  logic started;
  logic frozen;
  logic collision;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      started    <= 1'b0;
      frozen     <= 1'b0;
      roundStart <= 1'b0;
      roundOver  <= 1'b0;
    end else begin
      roundStart <= 1'b0;
      roundOver  <= 1'b0;
      if ((tickState && !started) || (frozen && enterPulse)) begin
        started    <= 1'b1;
        roundStart <= 1'b1;
        frozen     <= 1'b0;
      end else if (tickState && collision && !frozen) begin
        frozen    <= 1'b1;
        roundOver <= 1'b1;
      end
    end
  end

  logic       worldRun;
  logic [2:0] screen;

  assign worldRun = started && !frozen;
  assign screen   = frozen ? ST_HIT : ST_PLAY;

  // ---------------------------------------------------------------- game logic
  logic [15:0] rnd;

  lfsr_rng rng (
      .clk     (clk),
      .resetN  (resetN),
      .step    (tickMove),
      .seedLoad(1'b0),
      .seed    (16'h0000),
      .rnd     (rnd)
  );

  logic signed [10:0] birdY;
  logic signed [11:0] birdVy;
  logic [7:0]         birdTrajState;

  bird_trajectory bird (
      .clk      (clk),
      .resetN   (resetN),
      .tick     (tickMove),
      .run      (worldRun),
      .restart  (roundStart),
      .mode     (DIFF_EASY),
      .rnd      (rnd),
      .birdY    (birdY),
      .birdVy   (birdVy),
      .trajState(birdTrajState)
  );

  logic ctrlUp, ctrlDown;
  logic signed [9:0] mazeOffset;
  logic signed [4:0] mazeVy;

  control_mux steering (
      .aiMode  (1'b0),          // AI arrives in the ML phase
      .kbdUp   (upHeld),
      .kbdDown (downHeld),
      .aiUp    (1'b0),
      .aiDown  (1'b0),
      .aiValid (1'b0),
      .ctrlUp  (ctrlUp),
      .ctrlDown(ctrlDown)
  );

  maze_control maze (
      .clk       (clk),
      .resetN    (resetN),
      .tick      (tickMove),
      .run       (worldRun),
      .restart   (roundStart),
      .moveUp    (ctrlUp),
      .moveDown  (ctrlDown),
      .mazeOffset(mazeOffset),
      .mazeVy    (mazeVy)
  );

  logic [NUM_COLUMNS-1:0]       colActive;
  logic [NUM_COLUMNS-1:0][10:0] colX;
  logic [NUM_COLUMNS-1:0][9:0]  gapTop;
  logic [NUM_COLUMNS-1:0][9:0]  gapBottom;
  logic                         scorePulse;
  logic [NUM_COLUMNS-1:0]       hitColumn;

  obstacle_manager obstacles (
      .clk        (clk),
      .resetN     (resetN),
      .tickMove   (tickMove),
      .tickCheck  (tickCheck),
      .run        (worldRun),
      .restart    (roundStart),
      .columnCount(2'd1),
      .worldStep  (12'(WORLD_STEP_DEFAULT)),
      .mazeOffset (mazeOffset),
      .rnd        (rnd),
      .active     (colActive),
      .colX       (colX),
      .gapTop     (gapTop),
      .gapBottom  (gapBottom),
      .scorePulse (scorePulse)
  );

  collision_detect collide (
      .clk      (clk),
      .resetN   (resetN),
      .tickCheck(tickCheck),
      .birdY    (birdY),
      .active   (colActive),
      .colX     (colX),
      .gapTop   (gapTop),
      .gapBottom(gapBottom),
      .collision(collision),
      .hitColumn(hitColumn)
  );

  logic [2:0][3:0] score;
  logic [2:0][3:0] best;
  logic            newBest;

  score_bcd scoring (
      .clk       (clk),
      .resetN    (resetN),
      .clearScore(roundStart),
      .addPoint  (scorePulse),
      .commitBest(roundOver),
      .score     (score),
      .best      (best),
      .newBest   (newBest)
  );

  // ---------------------------------------------------------------- drawing
  color_t waterRGB;

  water_background water (
      .clk   (clk),
      .resetN(resetN),
      .pixelX(pixelX),
      .pixelY(pixelY),
      .RGBout(waterRGB)
  );

  logic   coralDR;
  color_t coralRGB;

  coral_draw coralDraw (
      .clk           (clk),
      .resetN        (resetN),
      .pixelX        (pixelX),
      .pixelY        (pixelY),
      .active        (colActive),
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
      .animate       (!frozen),
      .blink         (frozen),
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
      .menuCursor    (2'd0),
      .scoreDigits   (score),
      .bestDigits    (best),
      .newBest       (newBest),
      .blink         (blink),
      .drawingRequest(textDR),
      .RGBout        (textRGB)
  );

  objects_mux_top mux (
      .clk                (clk),
      .resetN             (resetN),
      .textDrawingRequest (textDR),
      .textRGB            (textRGB),
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
  assign LEDR = {blink, 6'b0, frozen, resetN, 1'b0};

endmodule
