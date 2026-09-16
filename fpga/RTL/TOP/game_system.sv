// Everything that runs on the pixel clock: VGA timing, game logic and drawing.
// Kept separate from the board-specific top level (PLL, precompiled keyboard
// and codec blocks) so the whole game can be simulated.

module game_system
  import palette_pkg::*, game_params_pkg::*;
(
    input  logic        clk,
    input  logic        resetN,
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

  // ---------------------------------------------------------------- game logic
  logic signed [10:0] birdY;
  logic signed [11:0] birdVy;
  logic [7:0]         birdTrajState;

  bird_trajectory bird (
      .clk      (clk),
      .resetN   (resetN),
      .tick     (tickMove),
      .run      (1'b1),
      .restart  (1'b0),
      .mode     (2'd0),
      .rnd      (16'd0),
      .birdY    (birdY),
      .birdVy   (birdVy),
      .trajState(birdTrajState)
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
      .animate       (1'b1),
      .blink         (1'b0),
      .drawingRequest(birdDR),
      .RGBout        (birdRGB)
  );

  objects_mux_top mux (
      .clk               (clk),
      .resetN            (resetN),
      .birdDrawingRequest(birdDR),
      .birdRGB           (birdRGB),
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
  assign LEDR = {frameCount[5], 7'b0, resetN, 1'b0};

endmodule
