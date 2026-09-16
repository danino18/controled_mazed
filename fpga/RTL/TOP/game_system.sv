// Everything that runs on the pixel clock: VGA timing, game logic and drawing.
// Kept separate from the board-specific top level (PLL, precompiled keyboard
// and codec blocks) so the whole game can be simulated.

module game_system
  import palette_pkg::*, game_params_pkg::*;
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
  logic started;
  logic frozen;
  logic collision;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      started    <= 1'b0;
      frozen     <= 1'b0;
      roundStart <= 1'b0;
    end else begin
      roundStart <= 1'b0;
      if ((tickState && !started) || (frozen && enterPulse)) begin
        started    <= 1'b1;
        roundStart <= 1'b1;
        frozen     <= 1'b0;
      end else if (tickState && collision) begin
        frozen <= 1'b1;
      end
    end
  end

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
      .run      (started && !frozen),
      .restart  (roundStart),
      .mode     (2'd0),
      .rnd      (rnd),
      .birdY    (birdY),
      .birdVy   (birdVy),
      .trajState(birdTrajState)
  );

  // ---------------------------------------------------------------- maze steering
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
      .run       (started && !frozen),
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
      .run        (started && !frozen),
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

  // ---------------------------------------------------------------- drawing
  color_t waterRGB;

  water_background water (
      .clk   (clk),
      .resetN(resetN),
      .pixelX(pixelX),
      .pixelY(pixelY),
      .RGBout(waterRGB)
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

  objects_mux_top mux (
      .clk               (clk),
      .resetN            (resetN),
      .birdDrawingRequest(birdDR),
      .birdRGB           (birdRGB),
      .coralDrawingRequest(coralDR),
      .coralRGB           (coralRGB),
      .backgroundRGB     (waterRGB),
      .RGBOut            (screenRGB)
  );

  // ---------------------------------------------------------------- indicators
  logic [2:0][3:0] fpsBcd;
  logic [2:0]      fpsDigitOn;
  logic [5:0]      frameCount;

  fps_meter #(.CLOCKS_PER_SECOND(CLOCKS_PER_SECOND)) fpsMeter (
      .clk         (clk),
      .resetN      (resetN),
      .startOfFrame(startOfFrame),
      .fpsBcd      (fpsBcd)
  );

  leading_zero_blank #(.DIGITS(3)) fpsBlank (
      .digits (fpsBcd),
      .digitOn(fpsDigitOn)
  );

  hex_display_top hex (
      .clk    (clk),
      .resetN (resetN),
      .digits ({12'h000, fpsBcd}),
      .digitOn({3'b000, fpsDigitOn}),
      .HEX0   (HEX0),
      .HEX1   (HEX1),
      .HEX2   (HEX2),
      .HEX3   (HEX3),
      .HEX4   (HEX4),
      .HEX5   (HEX5)
  );

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      frameCount <= '0;
    end else if (startOfFrame) begin
      frameCount <= frameCount + 6'd1;
    end
  end

  // LEDR[0] is driven by the board top level (PLL locked).
  assign LEDR = {frameCount[5], 6'b0, frozen, resetN, 1'b0};

endmodule
