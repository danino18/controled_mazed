// Training screen graphics (lane_view_draw) against a reference renderer.
//
// For many frames of random snapshots (every lane state, bird heights, column
// positions on and off the screen, openings, active columns), every visible
// pixel must equal the reference picture: window k shows lane k at 1/4 scale
// with the game's coral and bird artwork (read from the same .mif files) and
// water colours, a border in the lane state's colour, dead lanes darkened with
// a red cross, idle lanes grey, and the backdrop everywhere else. The layer
// draws nothing while the training screen is not shown.
`timescale 1ns / 1ps

module tb_train_view;
  import palette_pkg::*, game_params_pkg::*, ml_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #15.873 clk = ~clk;

  logic [10:0] pixelX, pixelY;
  logic        startOfFrame;
  logic [28:0] ovga;

  VGA_Controller vga (
      .RGBIn(8'h00), .PixelX(pixelX), .PixelY(pixelY), .startOfFrame(startOfFrame),
      .oVGA(ovga), .address(), .clk(clk), .resetN(resetN));

  logic                     enable = 1'b0;
  logic [LANES-1:0][1:0]    laneState = '0;
  logic [LANES-1:0][10:0]   birdY = '0;
  logic [LANES-1:0][2:0]    active = '0;
  logic [LANES-1:0][32:0]   colX = '0;
  logic [LANES-1:0][29:0]   gapTop = '0;
  logic                     drawingRequest;
  color_t                   rgb;

  lane_view_draw dut (
      .clk(clk), .resetN(resetN), .pixelX(pixelX), .pixelY(pixelY), .enable(enable),
      .laneState(laneState), .viewBirdY(birdY), .viewActive(active), .viewColX(colX), .viewGapTop(gapTop),
      .drawingRequest(drawingRequest), .RGBout(rgb));

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 25) $display("FAIL: %s", msg);
  endtask

  // ---------------------------------------------------------------- .mif reader (hex addresses and data)
  task automatic load_mif(input string path, ref logic [7:0] mem [], output int depth);
    int fd, a, d, n;
    string line;
    bit inContent;
    fd = $fopen(path, "r");
    depth = 0;
    if (fd == 0) begin
      fail($sformatf("cannot open %s", path));
      return;
    end
    inContent = 0;
    while (!$feof(fd)) begin
      void'($fgets(line, fd));
      if (!inContent) begin
        if ($sscanf(line, "DEPTH = %d;", n) == 1) begin
          depth = n;
          mem = new[n];
        end
        if (line.substr(0, 12) == "CONTENT BEGIN") inContent = 1;
      end else if ($sscanf(line, "%h : %h;", a, d) == 2) begin
        mem[a] = 8'(d);
      end
    end
    $fclose(fd);
  endtask

  logic [7:0] coral [];
  logic [7:0] bird [];

  // ---------------------------------------------------------------- reference picture
  function automatic color_t water_of(input int wy);
    case (wy >> 6)
      0: return C_WATER_1;
      1: return C_WATER_2;
      2: return C_WATER_3;
      3: return C_WATER_4;
      4: return C_WATER_5;
      5: return C_WATER_6;
      default: return C_WATER_7;
    endcase
  endfunction

  function automatic color_t expected(input int x, input int y);
    int k, lx, ly, wx, wy, by;
    color_t pic, edgeC;
    bit found;
    if (!enable) return TRANSPARENT;
    lx = x % 160;
    if (y >= 40 && y < 152)       begin k = x / 160;     ly = y - 40;  end
    else if (y >= 168 && y < 280) begin k = x / 160 + 4; ly = y - 168; end
    else return 8'h00;                                    // backdrop
    case (laneState[k])
      LANE_ALIVE: edgeC = 8'h1F;
      LANE_DEAD:  edgeC = 8'hE0;
      LANE_DONE:  edgeC = 8'h3C;
      default:    edgeC = 8'h6D;
    endcase
    if (lx == 0 || lx == 159 || ly == 0 || ly == 111) return edgeC;
    if (laneState[k] == LANE_IDLE) return 8'h25;
    wx = lx * 4 + 2;
    wy = (ly - 1) * 4 + 2;
    pic = water_of(wy);
    found = 0;
    by = wy - int'($signed(birdY[k]));
    if (wx >= 144 && wx < 176 && by >= 0 && by < 32 && bird[by * 32 + wx - 144] != 8'hFF) begin
      pic = bird[by * 32 + wx - 144];
      found = 1;
    end
    for (int i = 0; i < NUM_COLUMNS && !found; i++) begin
      int cx, top, d;
      cx  = int'($signed(colX[k][i * 11 +: 11]));
      top = int'(gapTop[k][i * 10 +: 10]);
      if (active[k][i] && wx >= cx && wx < cx + 64 && (wy < top || wy >= top + 128)) begin
        d = (wy < top) ? top - wy - 1 : wy - top - 128;
        if (coral[(d < 32 ? 2048 : 0) + (31 - d % 32) * 64 + (wx - cx)] != 8'hFF)
          pic = coral[(d < 32 ? 2048 : 0) + (31 - d % 32) * 64 + (wx - cx)];
        found = 1;              // the first column hit decides, as the columns never overlap
      end
    end
    if (laneState[k] == LANE_DEAD) begin
      int d1, d2;
      d1 = ly * 10 - lx * 7;
      d2 = (111 - ly) * 10 - lx * 7;
      if ((d1 > -12 && d1 < 12) || (d2 > -12 && d2 < 12)) return 8'hE4;
      return {1'b0, pic[7:6], 1'b0, pic[4:3], 1'b0, pic[1]};
    end
    return pic;
  endfunction

  // RGBout belongs to the pixel coordinates of 3 clocks earlier
  logic [10:0] xd [3];
  logic [10:0] yd [3];
  logic        vd [3];
  bit          checking = 0;
  longint      checked = 0;
  int          kinds [string];

  always @(posedge clk) begin
    xd[0] <= pixelX;  yd[0] <= pixelY;  vd[0] <= ovga[27] && pixelX < 640 && pixelY < 480;
    xd[1] <= xd[0];   yd[1] <= yd[0];   vd[1] <= vd[0];
    xd[2] <= xd[1];   yd[2] <= yd[1];   vd[2] <= vd[1];
    if (resetN && checking && vd[2]) begin
      color_t e;
      e = expected(xd[2], yd[2]);
      checked++;
      if (rgb !== e) fail($sformatf("pixel (%0d,%0d) = %02h, expected %02h", xd[2], yd[2], rgb, e));
      if (drawingRequest !== enable) fail("drawing request wrong");
    end
  end

  task automatic random_snapshot(input int seed);
    for (int k = 0; k < LANES; k++) begin
      int r;
      r = $urandom(seed * 13 + k);
      laneState[k] = 2'(r);
      birdY[k]     = 11'(BIRD_Y_MIN + $urandom_range(0, BIRD_Y_MAX - BIRD_Y_MIN));
      active[k]    = 3'($urandom_range(1, 7));
      for (int i = 0; i < NUM_COLUMNS; i++) begin
        colX[k][i * 11 +: 11]   = 11'($urandom_range(0, 760) - 64);
        gapTop[k][i * 10 +: 10] = 10'($urandom_range(GAP_CENTER_MIN, GAP_CENTER_MAX) - GAP_H / 2);
      end
    end
    // one lane with a column right at the bird, to cover the bird in front of coral
    colX[seed % LANES][10:0] = 11'(130 + seed % 30);
    laneState[seed % LANES]  = LANE_ALIVE;
  endtask

  initial begin
    int d;
    load_mif("RTL/MIF/coral.mif", coral, d);
    if (d != 4096) fail("coral.mif depth");
    load_mif("RTL/MIF/bird.mif", bird, d);
    if (d != 3072) fail("bird.mif depth");

    repeat (5) @(posedge clk);
    resetN = 1'b1;

    // hidden while the training screen is not shown
    @(posedge clk iff startOfFrame);
    checking = 1;
    @(posedge clk iff startOfFrame);

    enable = 1'b1;
    for (int f = 0; f < 10; f++) begin
      checking = 0;
      random_snapshot(f + 1);
      repeat (4) @(posedge clk);
      checking = 1;
      @(posedge clk iff startOfFrame);
    end
    checking = 0;
    enable = 1'b0;
    repeat (4) @(posedge clk);
    checking = 1;
    @(posedge clk iff startOfFrame);

    $display("INFO: %0d pixels compared", checked);
    if (checked < 3000000) fail("too few pixels compared");
    if (errors == 0) $display("PASS: tb_train_view");
    else             $display("FAIL: tb_train_view (%0d errors)", errors);
    $finish;
  end

endmodule
