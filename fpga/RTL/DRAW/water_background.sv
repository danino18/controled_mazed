// Procedural underwater depth gradient (base layer, always drawn, no ROM).
//
// The screen is split into 64-pixel bands. Each band blends from one ramp
// colour to the next using a 4x4 ordered (Bayer) dither, which hides the
// coarse 2-bit blue channel. Latency: 3 clocks, like every drawing layer.

module water_background
  import palette_pkg::*;
(
    input  logic        clk,
    input  logic        resetN,
    input  logic [10:0] pixelX,
    input  logic [10:0] pixelY,
    output color_t      RGBout
);

  localparam logic [0:8][7:0] RAMP = {C_WATER_0, C_WATER_1, C_WATER_2,
                                      C_WATER_3, C_WATER_4, C_WATER_5,
                                      C_WATER_6, C_WATER_7, C_WATER_8};

  localparam logic [0:3][0:3][3:0] BAYER = {
      4'd0,  4'd8,  4'd2,  4'd10,
      4'd12, 4'd4,  4'd14, 4'd6,
      4'd3,  4'd11, 4'd1,  4'd9,
      4'd15, 4'd7,  4'd13, 4'd5};

  logic [3:0] band;        // 0..7 on screen; band + 1 reaches the last ramp entry
  logic [3:0] blend;       // position inside the band, 0..15
  logic [3:0] threshold;
  logic       useNext;

  assign band      = {1'b0, pixelY[8:6]};
  assign blend     = pixelY[5:2];
  assign threshold = BAYER[pixelY[1:0]][pixelX[1:0]];
  assign useNext   = (blend > threshold);

  color_t stage1, stage2;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      stage1 <= C_BLACK;
      stage2 <= C_BLACK;
      RGBout <= C_BLACK;
    end else begin
      stage1 <= useNext ? RAMP[band + 4'd1] : RAMP[band];
      stage2 <= stage1;
      RGBout <= stage2;
    end
  end

endmodule
