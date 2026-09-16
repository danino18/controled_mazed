// Draws the animated bird at (BIRD_X, birdY).
// square_object (supplied) finds the 32x32 bracket; birdBitMap supplies the pixels.
// The fin animation plays frames 0-1-2-1. Latency: 3 clocks.

module bird_draw
  import palette_pkg::*, game_params_pkg::*;
(
    input  logic               clk,
    input  logic               resetN,
    input  logic [10:0]        pixelX,
    input  logic [10:0]        pixelY,
    input  logic signed [10:0] birdY,
    input  logic               tick,       // once per frame
    input  logic               animate,    // flap the fin
    input  logic               blink,      // flash the bird (after a hit)
    output logic               drawingRequest,
    output color_t             RGBout
);

  logic [10:0] offsetX;
  logic [10:0] offsetY;
  logic        inBracket;

  square_object #(
      .OBJECT_WIDTH_X (BIRD_SIZE),
      .OBJECT_HEIGHT_Y(BIRD_SIZE)
  ) bracket (
      .clk           (clk),
      .resetN        (resetN),
      .pixelX        (pixelX),
      .pixelY        (pixelY),
      .topLeftX      (11'(BIRD_X)),
      .topLeftY      (birdY),
      .offsetX       (offsetX),
      .offsetY       (offsetY),
      .drawingRequest(inBracket),
      .RGBout        ()
  );

  // ---------------------------------------------------------------- animation
  logic [3:0] frameCount;
  logic [1:0] animStep;
  logic [1:0] frame;
  logic       blinkOff;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      frameCount <= '0;
      animStep   <= '0;
    end else if (tick) begin
      frameCount <= frameCount + 4'd1;
      if (animate && frameCount == 4'(BIRD_FRAMES_PER_ANIM_STEP - 1)) begin
        frameCount <= '0;
        animStep   <= animStep + 2'd1;
      end
    end
  end

  assign frame    = (animStep == 2'd3) ? 2'd1 : animStep;
  assign blinkOff = blink && frameCount[2];

  logic   bitmapDR;
  color_t bitmapRGB;

  birdBitMap bitmap (
      .clk            (clk),
      .resetN         (resetN),
      .offsetX        (offsetX),
      .offsetY        (offsetY),
      .InsideRectangle(inBracket),
      .frame          (frame),
      .drawingRequest (bitmapDR),
      .RGBout         (bitmapRGB)
  );

  assign drawingRequest = bitmapDR && !blinkOff;
  assign RGBout         = bitmapRGB;

endmodule
