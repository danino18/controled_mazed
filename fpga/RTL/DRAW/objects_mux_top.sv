// Priority multiplexer choosing the colour of the current pixel.
// Based on the supplied objects_mux.sv: the first object with an active
// drawing request wins; the background has no request and is always last.

module objects_mux_top
  import palette_pkg::*;
(
    input  logic   clk,
    input  logic   resetN,

    input  logic   birdDrawingRequest,
    input  color_t birdRGB,

    input  color_t backgroundRGB,

    output color_t RGBOut
);

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      RGBOut <= C_BLACK;
    end else if (birdDrawingRequest) begin
      RGBOut <= birdRGB;
    end else begin
      RGBOut <= backgroundRGB;
    end
  end

endmodule
