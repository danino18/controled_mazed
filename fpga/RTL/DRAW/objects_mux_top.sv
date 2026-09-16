// Priority multiplexer choosing the colour of the current pixel.
// Based on the supplied objects_mux.sv: the first layer with an active drawing
// request wins; the background has no request and is always last.
// Order (front to back): text, bird, coral, background.

module objects_mux_top
  import palette_pkg::*;
(
    input  logic   clk,
    input  logic   resetN,

    input  logic   textDrawingRequest,
    input  color_t textRGB,

    input  logic   birdDrawingRequest,
    input  color_t birdRGB,

    input  logic   coralDrawingRequest,
    input  color_t coralRGB,

    input  color_t backgroundRGB,

    output color_t RGBOut
);

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      RGBOut <= C_BLACK;
    end else if (textDrawingRequest) begin
      RGBOut <= textRGB;
    end else if (birdDrawingRequest) begin
      RGBOut <= birdRGB;
    end else if (coralDrawingRequest) begin
      RGBOut <= coralRGB;
    end else begin
      RGBOut <= backgroundRGB;
    end
  end

endmodule
