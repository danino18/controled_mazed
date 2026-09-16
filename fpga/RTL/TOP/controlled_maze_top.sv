// Controlled Maze - top level.
// M1: water background, static bird placeholder, frame-rate meter on HEX1..HEX0.

module controlled_maze_top
  import palette_pkg::*, game_params_pkg::*;
(
    input  logic        CLOCK_50,
    input  logic        resetN_pin,     // KEY[0], active low
    output logic [9:0]  LEDR,
    output logic [6:0]  HEX0,
    output logic [6:0]  HEX1,
    output logic [6:0]  HEX2,
    output logic [6:0]  HEX3,
    output logic [6:0]  HEX4,
    output logic [6:0]  HEX5,
    output logic [28:0] OVGA
);

  // ---------------------------------------------------------------- clock / reset
  // As in the supplied demo, KEY[0] also resets the PLL; logic stays in reset until it relocks.
  logic clk;
  logic pllLocked;
  logic resetN;

  CLK_31P5 pll (
      .refclk  (CLOCK_50),
      .rst     (~resetN_pin),
      .outclk_0(clk),
      .locked  (pllLocked)
  );

  reset_sync resetSync (
      .clk        (clk),
      .asyncResetN(resetN_pin & pllLocked),
      .resetN     (resetN)
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

  square_object #(
      .OBJECT_WIDTH_X (BIRD_SIZE),
      .OBJECT_HEIGHT_Y(BIRD_SIZE),
      .OBJECT_COLOR   (C_AMBER)
  ) birdBox (
      .clk           (clk),
      .resetN        (resetN),
      .pixelX        (pixelX),
      .pixelY        (pixelY),
      .topLeftX      (11'(BIRD_X)),
      .topLeftY      (11'(BIRD_Y0)),
      .offsetX       (),
      .offsetY       (),
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

  // ---------------------------------------------------------------- debug indicators
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

  assign LEDR = {frameCount[5], 7'b0, resetN, pllLocked};

endmodule
