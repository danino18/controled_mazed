// Training screen graphics: the eight lane windows and the dark backdrop.
//
// Window k (k = 0..7, four per row) shows training lane k from the per-frame
// snapshot, as a 1/4-scale nearest-neighbour picture of the real game: world
// x 0..639 -> 160 px, world y 0..439 -> 110 px, sampled at the centre of each
// 4x4 block, with the game's own coral and bird artwork (the same .mif files
// as coral_draw and bird_draw) and the game's water colours.
//
//   window k:  x = 160 * (k % 4) .. +159,  y = 40 + 128 * (k / 4) .. +111
//   border:    cyan = alive, red = dead, green = done, grey = idle
//   dead:      the picture of the death step, darkened, with a red cross
//   idle:      dark grey, no picture
//
// Everything outside the windows is the backdrop (the text layer is drawn on
// top of this layer). Latency: 3 clocks, like every drawing layer.

module lane_view_draw
  import palette_pkg::*, game_params_pkg::*, ml_pkg::*;
(
    input  logic                                 clk,
    input  logic                                 resetN,
    input  logic [10:0]                          pixelX,
    input  logic [10:0]                          pixelY,
    input  logic                                 enable,       // the training screen is shown
    input  logic [LANES-1:0][1:0]                laneState,    // LANE_*
    input  logic [LANES-1:0][10:0]               viewBirdY,
    input  logic [LANES-1:0][NUM_COLUMNS-1:0]    viewActive,
    input  logic [LANES-1:0][NUM_COLUMNS*11-1:0] viewColX,
    input  logic [LANES-1:0][NUM_COLUMNS*10-1:0] viewGapTop,
    output logic                                 drawingRequest,
    output color_t                               RGBout
);

  localparam int WIN_W   = 160;
  localparam int WIN_H   = 112;
  localparam int ROW0_Y  = 40;
  localparam int ROW1_Y  = 168;

  localparam logic TILE_BODY = 1'b0;
  localparam logic TILE_TIP  = 1'b1;

  localparam color_t C_BACKDROP  = {3'd0, 3'd0, 2'd0};
  localparam color_t C_IDLE_FILL = {3'd1, 3'd1, 2'd1};
  localparam color_t C_EDGE_IDLE = {3'd3, 3'd3, 2'd1};
  localparam color_t C_EDGE_LIVE = {3'd0, 3'd7, 2'd3};
  localparam color_t C_EDGE_DEAD = {3'd7, 3'd0, 2'd0};
  localparam color_t C_EDGE_DONE = {3'd1, 3'd7, 2'd0};
  localparam color_t C_CROSS     = {3'd7, 3'd1, 2'd0};

  // ---------------------------------------------------------------- stage 0: which window, where in it
  logic [1:0]  kx;
  logic [10:0] lx0;
  logic        rowSel;
  logic        inRow;
  logic [10:0] ly0;

  always_comb begin
    if (pixelX >= 11'(3 * WIN_W))      kx = 2'd3;
    else if (pixelX >= 11'(2 * WIN_W)) kx = 2'd2;
    else if (pixelX >= 11'(WIN_W))     kx = 2'd1;
    else                               kx = 2'd0;
    lx0 = pixelX - 11'(int'(kx) * WIN_W);

    if (pixelY >= 11'(ROW0_Y) && pixelY < 11'(ROW0_Y + WIN_H)) begin
      inRow  = 1'b1;
      rowSel = 1'b0;
      ly0    = pixelY - 11'(ROW0_Y);
    end else if (pixelY >= 11'(ROW1_Y) && pixelY < 11'(ROW1_Y + WIN_H)) begin
      inRow  = 1'b1;
      rowSel = 1'b1;
      ly0    = pixelY - 11'(ROW1_Y);
    end else begin
      inRow  = 1'b0;
      rowSel = 1'b0;
      ly0    = '0;
    end
  end

  logic [2:0] k0;
  assign k0 = {rowSel, kx};

  // ---------------------------------------------------------------- stage 1: this lane's snapshot
  logic                         valid1, inWin1;
  logic [7:0]                   lx1;
  logic [6:0]                   ly1;
  logic [1:0]                   state1;
  logic signed [10:0]           birdY1;
  logic [NUM_COLUMNS-1:0]       active1;
  logic [NUM_COLUMNS-1:0][10:0] colX1;
  logic [NUM_COLUMNS-1:0][9:0]  gapTop1;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      valid1  <= 1'b0;
      inWin1  <= 1'b0;
      lx1     <= '0;
      ly1     <= '0;
      state1  <= LANE_IDLE;
      birdY1  <= '0;
      active1 <= '0;
      colX1   <= '0;
      gapTop1 <= '0;
    end else begin
      valid1  <= enable && pixelX < 11'(SCREEN_W) && pixelY < 11'(SCREEN_H);
      inWin1  <= inRow;
      lx1     <= lx0[7:0];
      ly1     <= ly0[6:0];
      state1  <= laneState[k0];
      birdY1  <= viewBirdY[k0];
      active1 <= viewActive[k0];
      colX1   <= viewColX[k0];
      gapTop1 <= viewGapTop[k0];
    end
  end

  // ---------------------------------------------------------------- stage 2: geometry, ROM addresses
  int   wx, wy;                       // world point sampled by this pixel
  logic border, content, xMark;

  assign wx      = int'(lx1) * 4 + 2;
  assign wy      = (int'(ly1) - 1) * 4 + 2;
  assign border  = (lx1 == 8'd0) || (lx1 == 8'(WIN_W - 1)) || (ly1 == 7'd0) || (ly1 == 7'(WIN_H - 1));
  assign content = (ly1 >= 7'd1) && (ly1 <= 7'(WIN_H - 2));

  // a red cross (xMark) over a dead window: two lines of slope 111/159 ~= 7/10
  int d1, d2;
  assign d1    = int'(ly1) * 10 - int'(lx1) * 7;
  assign d2    = (WIN_H - 1 - int'(ly1)) * 10 - int'(lx1) * 7;
  assign xMark = (d1 > -12 && d1 < 12) || (d2 > -12 && d2 < 12);

  // coral (same tile addressing as coral_draw)
  logic [NUM_COLUMNS-1:0]       cHit;
  logic [NUM_COLUMNS-1:0][5:0]  cTileX;
  logic [NUM_COLUMNS-1:0][9:0]  cDist;

  genvar i;
  generate
    for (i = 0; i < NUM_COLUMNS; i++) begin : column
      int   dx;
      logic above, below;
      assign dx        = wx - int'($signed(colX1[i]));
      assign above     = wy < int'(gapTop1[i]);
      assign below     = wy >= int'(gapTop1[i]) + GAP_H;
      assign cHit[i]   = active1[i] && dx >= 0 && dx < CORAL_W && (above || below);
      assign cTileX[i] = dx[5:0];
      assign cDist[i]  = above ? 10'(int'(gapTop1[i]) - wy - 1) : 10'(wy - int'(gapTop1[i]) - GAP_H);
    end
  endgenerate

  logic       coralHit;
  logic [5:0] selX;
  logic [9:0] selDist;

  always_comb begin
    coralHit = 1'b0;
    selX     = '0;
    selDist  = '0;
    for (int c = NUM_COLUMNS - 1; c >= 0; c--)
      if (cHit[c]) begin
        coralHit = 1'b1;
        selX     = cTileX[c];
        selDist  = cDist[c];
      end
  end

  int   bx, by;
  logic birdHit;
  assign bx      = wx - BIRD_X;
  assign by      = wy - int'(birdY1);
  assign birdHit = bx >= 0 && bx < BIRD_SIZE && by >= 0 && by < BIRD_SIZE;

  // water colour by depth, as in the game
  color_t water;
  always_comb begin
    case (wy >> 6)
      0:       water = C_WATER_1;
      1:       water = C_WATER_2;
      2:       water = C_WATER_3;
      3:       water = C_WATER_4;
      4:       water = C_WATER_5;
      5:       water = C_WATER_6;
      default: water = C_WATER_7;
    endcase
  end

  logic [11:0] coralAddr, birdAddr;
  assign coralAddr = {(selDist < 10'd32) ? TILE_TIP : TILE_BODY, ~selDist[4:0], selX};
  assign birdAddr  = {2'b00, by[4:0], bx[4:0]};

  logic   valid2, inWin2, border2, xMark2, coralHit2, birdHit2;
  logic [1:0] state2;
  color_t water2;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      valid2    <= 1'b0;
      inWin2    <= 1'b0;
      border2   <= 1'b0;
      xMark2    <= 1'b0;
      coralHit2 <= 1'b0;
      birdHit2  <= 1'b0;
      state2    <= LANE_IDLE;
      water2    <= C_BACKDROP;
    end else begin
      valid2    <= valid1;
      inWin2    <= inWin1;
      border2   <= border;
      xMark2    <= xMark;
      coralHit2 <= coralHit && content;
      birdHit2  <= birdHit && content;
      state2    <= state1;
      water2    <= water;
    end
  end

  color_t coralColour, birdColour;

  lpm_rom #(
      .lpm_width             (8),
      .lpm_widthad           (12),
      .lpm_numwords          (4096),
      .lpm_file              ("RTL/MIF/coral.mif"),
      .lpm_type              ("LPM_ROM"),
      .lpm_address_control   ("REGISTERED"),
      .lpm_outdata           ("UNREGISTERED"),
      .intended_device_family("Cyclone V")
  ) coralRom (
      .address(coralAddr),
      .inclock(clk),
      .q      (coralColour)
  );

  lpm_rom #(
      .lpm_width             (8),
      .lpm_widthad           (12),
      .lpm_numwords          (3072),
      .lpm_file              ("RTL/MIF/bird.mif"),
      .lpm_type              ("LPM_ROM"),
      .lpm_address_control   ("REGISTERED"),
      .lpm_outdata           ("UNREGISTERED"),
      .intended_device_family("Cyclone V")
  ) birdRom (
      .address(birdHit ? birdAddr : 12'd0),     // the model stops on addresses past 3071
      .inclock(clk),
      .q      (birdColour)
  );

  // ---------------------------------------------------------------- stage 3: colour
  color_t picture, edgeColour, shaded;

  always_comb begin
    if (birdHit2 && birdColour != TRANSPARENT)        picture = birdColour;
    else if (coralHit2 && coralColour != TRANSPARENT) picture = coralColour;
    else                                              picture = water2;

    case (state2)
      LANE_ALIVE: edgeColour = C_EDGE_LIVE;
      LANE_DEAD:  edgeColour = C_EDGE_DEAD;
      LANE_DONE:  edgeColour = C_EDGE_DONE;
      default:    edgeColour = C_EDGE_IDLE;
    endcase

    if (!inWin2)                    shaded = C_BACKDROP;
    else if (border2)               shaded = edgeColour;
    else if (state2 == LANE_IDLE)   shaded = C_IDLE_FILL;
    else if (state2 == LANE_DEAD)   shaded = xMark2 ? C_CROSS : {1'b0, picture[7:6], 1'b0, picture[4:3], 1'b0, picture[1]};
    else                            shaded = picture;
  end

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      drawingRequest <= 1'b0;
      RGBout         <= TRANSPARENT;
    end else begin
      drawingRequest <= valid2;
      RGBout         <= valid2 ? shaded : TRANSPARENT;
    end
  end

endmodule
