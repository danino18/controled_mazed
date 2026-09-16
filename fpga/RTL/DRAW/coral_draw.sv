// Draws all coral columns from two 64x32 tiles (body, tip) in one shared ROM.
//
// Tile rows are counted from the opening: d = distance of the pixel from the
// opening edge. The tip tile is used for d < 32, the body tile above/below it,
// and the tile row is ~d[4:0] so the texture moves with the opening and the
// lower column is a mirror image of the upper one. Columns never overlap
// horizontally, so at most one column covers a pixel. Latency: 3 clocks.

module coral_draw
  import palette_pkg::*, game_params_pkg::*;
(
    input  logic                         clk,
    input  logic                         resetN,
    input  logic [10:0]                  pixelX,
    input  logic [10:0]                  pixelY,
    input  logic [NUM_COLUMNS-1:0]       active,
    input  logic [NUM_COLUMNS-1:0][10:0] colX,
    input  logic [NUM_COLUMNS-1:0][9:0]  gapTop,
    input  logic [NUM_COLUMNS-1:0][9:0]  gapBottom,
    output logic                         drawingRequest,
    output color_t                       RGBout
);

  localparam logic TILE_BODY = 1'b0;
  localparam logic TILE_TIP  = 1'b1;

  // ---------------------------------------------------------------- stage 0: which column, where in the tile
  logic [NUM_COLUMNS-1:0]       hit;
  logic [NUM_COLUMNS-1:0][5:0]  tileX;
  logic [NUM_COLUMNS-1:0][9:0]  edgeDist;

  genvar i;
  generate
    for (i = 0; i < NUM_COLUMNS; i++) begin : column
      int   dx;
      logic above, below;

      assign dx      = int'(pixelX) - int'($signed(colX[i]));
      assign above   = pixelY < gapTop[i];
      assign below   = pixelY >= gapBottom[i];
      assign hit[i]  = active[i] && (dx >= 0) && (dx < CORAL_W) && (above || below);
      assign tileX[i] = dx[5:0];
      assign edgeDist[i]  = above ? 10'(gapTop[i] - pixelY[9:0] - 10'd1) : 10'(pixelY[9:0] - gapBottom[i]);
    end
  endgenerate

  logic       anyHit;
  logic [5:0] selX;
  logic [9:0] selDist;

  always_comb begin
    anyHit  = 1'b0;
    selX    = '0;
    selDist = '0;
    for (int k = NUM_COLUMNS - 1; k >= 0; k--) begin
      if (hit[k]) begin
        anyHit  = 1'b1;
        selX    = tileX[k];
        selDist = edgeDist[k];
      end
    end
  end

  // ---------------------------------------------------------------- stage 1: ROM address
  logic [11:0] address;
  logic        hit1, hit2;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      address <= '0;
      hit1    <= 1'b0;
    end else begin
      address <= {(selDist < 10'd32) ? TILE_TIP : TILE_BODY, ~selDist[4:0], selX};
      hit1    <= anyHit;
    end
  end

  // ---------------------------------------------------------------- stage 2: ROM read, stage 3: output
  color_t color;

  lpm_rom #(
      .lpm_width             (8),
      .lpm_widthad           (12),
      .lpm_numwords          (4096),
      .lpm_file              ("RTL/MIF/coral.mif"),
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
      hit2   <= 1'b0;
      RGBout <= TRANSPARENT;
    end else begin
      hit2   <= hit1;
      RGBout <= hit2 ? color : TRANSPARENT;
    end
  end

  assign drawingRequest = (RGBout != TRANSPARENT);

endmodule
