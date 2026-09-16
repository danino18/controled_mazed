// Procedural underwater background (base layer, always drawn, no ROM).
//
// Water: the screen is split into 64-pixel bands; each band blends from one
// ramp colour to the next with a 4x4 ordered (Bayer) dither, which hides the
// coarse 2-bit blue channel.
// Sea floor: a wavy sand strip whose top edge is the sum of two triangle
// waves, textured with a cheap coordinate hash.
// Latency: 3 clocks, like every drawing layer.

module water_background
  import palette_pkg::*, game_params_pkg::*;
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

  // ---------------------------------------------------------------- water
  logic [3:0] band;        // 0..7 on screen; band + 1 reaches the last ramp entry
  logic [3:0] blend;       // position inside the band, 0..15
  logic [3:0] threshold;
  logic       useNext;
  color_t     waterColor;

  assign band       = {1'b0, pixelY[8:6]};
  assign blend      = pixelY[5:2];
  assign threshold  = BAYER[pixelY[1:0]][pixelX[1:0]];
  assign useNext    = (blend > threshold);
  assign waterColor = useNext ? RAMP[band + 4'd1] : RAMP[band];

  // ---------------------------------------------------------------- sea floor
  logic [10:0] shiftedX;
  logic [4:0]  wave64;     // 0..31, period 64
  logic [5:0]  wave128;    // 0..63, period 128
  logic [10:0] sandTop;
  logic [3:0]  grain;
  color_t      sandColor;

  assign shiftedX = pixelX + 11'd37;
  assign wave64   = pixelX[5]   ? ~pixelX[4:0]   : pixelX[4:0];
  assign wave128  = shiftedX[6] ? ~shiftedX[5:0] : shiftedX[5:0];
  assign sandTop  = 11'(SEABED_TOP) + 11'(wave64[4:2]) + 11'(wave128[5:3]);
  assign grain    = pixelX[3:0] ^ {pixelY[1:0], pixelY[3:2]} ^ pixelX[7:4] ^ pixelY[6:3];

  always_comb begin
    if (pixelY < sandTop + 11'd2)           sandColor = C_SAND_LIGHT;
    else if (grain == 4'hF && pixelX[1])    sandColor = C_PEBBLE;
    else if (grain[0] ^ grain[2])           sandColor = C_SAND;
    else                                    sandColor = C_SAND_DARK;
  end

  // ---------------------------------------------------------------- output pipeline
  color_t stage1, stage2;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      stage1 <= C_BLACK;
      stage2 <= C_BLACK;
      RGBout <= C_BLACK;
    end else begin
      stage1 <= (pixelY >= sandTop) ? sandColor : waterColor;
      stage2 <= stage1;
      RGBout <= stage2;
    end
  end

endmodule
