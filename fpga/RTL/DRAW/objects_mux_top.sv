// Priority multiplexer choosing the colour of the current pixel.
// Based on the supplied objects_mux.sv: the first layer with an active drawing
// request wins; the background has no request and is always last.
// Order (front to back): text screens (char_screen), training screen graphics
// (lane_view_draw), speed readout, text, panels, bird, coral, background.

module objects_mux_top
  import palette_pkg::*;
(
    input  logic   clk,
    input  logic   resetN,

    input  logic   charDrawingRequest,
    input  color_t charRGB,

    input  logic   trainDrawingRequest,
    input  color_t trainRGB,

    input  logic   speedDrawingRequest,
    input  color_t speedRGB,

    input  logic   textDrawingRequest,
    input  color_t textRGB,

    input  logic   panelDrawingRequest,
    input  color_t panelRGB,

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
    end else if (charDrawingRequest) begin
      RGBOut <= charRGB;
    end else if (trainDrawingRequest) begin
      RGBOut <= trainRGB;
    end else if (speedDrawingRequest) begin
      RGBOut <= speedRGB;
    end else if (textDrawingRequest) begin
      RGBOut <= textRGB;
    end else if (panelDrawingRequest) begin
      RGBOut <= panelRGB;
    end else if (birdDrawingRequest) begin
      RGBOut <= birdRGB;
    end else if (coralDrawingRequest) begin
      RGBOut <= coralRGB;
    end else begin
      RGBOut <= backgroundRGB;
    end
  end

endmodule
