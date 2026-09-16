// Bird bitmap: 32x32 pixels, 3 animation frames, 8-bit colour, 8'hFF transparent.
// Modelled on the supplied smileyBitMap.sv. Because every dimension is a power
// of two the ROM address is a plain concatenation {frame, y, x}.
//
// Parameter names are lower case (as in the Intel simulation model); Quartus accepts both.
// Latency: the ROM registers its address, and the colour is registered again,
// so the output is aligned with InsideRectangle delayed by two clocks.

module birdBitMap
  import palette_pkg::*;
(
    input  logic        clk,
    input  logic        resetN,
    input  logic [10:0] offsetX,          // from square_object
    input  logic [10:0] offsetY,
    input  logic        InsideRectangle,
    input  logic [1:0]  frame,            // 0..2
    output logic        drawingRequest,
    output color_t      RGBout
);

  logic [11:0] address;
  color_t      color;
  logic        insideD;

  assign address = {frame, offsetY[4:0], offsetX[4:0]};

  lpm_rom #(
      .lpm_width             (8),
      .lpm_widthad           (12),
      .lpm_numwords          (3072),
      .lpm_file              ("RTL/MIF/bird.mif"),
      .lpm_type              ("LPM_ROM"),
      .lpm_address_control   ("REGISTERED"),
      .lpm_outdata           ("UNREGISTERED"),
      .intended_device_family("Cyclone V")
  ) rom (
      .address(address),
      .inclock(clk),
      .q      (color)
  );

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      insideD <= 1'b0;
      RGBout  <= TRANSPARENT;
    end else begin
      insideD <= InsideRectangle;
      RGBout  <= insideD ? color : TRANSPARENT;
    end
  end

  assign drawingRequest = (RGBout != TRANSPARENT);

endmodule
