// Learning chart (chart_draw) against a reference renderer.
//
// The history memory is filled through its write port with random entries
// (including 0 % and 100 %); for several generation counts every visible
// pixel must equal the reference: the champion line (gold, 2 px), the
// generation-top point (cyan, 2 px), the mean bar (dim), the axes and the
// dotted 50 % / 100 % guides; nothing past `count`; nothing when disabled.
`timescale 1ns / 1ps

module tb_chart;
  import palette_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #15.873 clk = ~clk;

  logic [10:0] pixelX, pixelY;
  logic        startOfFrame;
  logic [28:0] ovga;

  VGA_Controller vga (
      .RGBIn(8'h00), .PixelX(pixelX), .PixelY(pixelY), .startOfFrame(startOfFrame),
      .oVGA(ovga), .address(), .clk(clk), .resetN(resetN));

  logic        enable = 1'b0;
  logic [7:0]  count = '0;
  logic        histWe = 1'b0;
  logic [6:0]  histWa = '0;
  logic [20:0] histWd = '0;
  logic        drawingRequest;
  color_t      rgb;

  chart_draw dut (
      .clk(clk), .resetN(resetN), .pixelX(pixelX), .pixelY(pixelY), .enable(enable), .count(count),
      .histWe(histWe), .histWa(histWa), .histWd(histWd), .drawingRequest(drawingRequest), .RGBout(rgb));

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 25) $display("FAIL: %s", msg);
  endtask

  int champ [128], top [128], mean [128];
  int count_list [4] = '{0, 1, 57, 128};

  function automatic color_t expected(input int x, input int y, output bit drawn);
    int g, h;
    drawn = 0;
    if (!enable) return TRANSPARENT;
    if (x >= 368 && x < 624 && y >= 332 && y <= 432) begin
      g = (x - 368) / 2;
      h = 432 - y;
      if (g < count) begin
        drawn = 1;
        if (h == champ[g] || h + 1 == champ[g]) return {3'd7, 3'd6, 2'd0};
        if (h == top[g] || h + 1 == top[g])     return {3'd0, 3'd7, 2'd3};
        if (h < mean[g])                        return {3'd1, 3'd2, 2'd2};
      end
    end
    drawn = 1;
    if ((x == 367 && y >= 331 && y <= 433) || (y == 433 && x >= 367 && x <= 624)) return {3'd3, 3'd3, 2'd2};
    if (x >= 368 && x < 624 && (y == 331 || y == 382) && (x % 4) == 0) return {3'd2, 3'd2, 2'd1};
    drawn = 0;
    return TRANSPARENT;
  endfunction

  logic [10:0] xd [3];
  logic [10:0] yd [3];
  logic        vd [3];
  bit          checking = 0;
  int          checked = 0, marked = 0;

  always @(posedge clk) begin
    xd[0] <= pixelX;  yd[0] <= pixelY;  vd[0] <= ovga[27] && pixelX < 640 && pixelY < 480;
    xd[1] <= xd[0];   yd[1] <= yd[0];   vd[1] <= vd[0];
    xd[2] <= xd[1];   yd[2] <= yd[1];   vd[2] <= vd[1];
    if (resetN && checking && vd[2]) begin
      color_t e;
      bit     d;
      e = expected(xd[2], yd[2], d);
      checked++;
      if (d) marked++;
      if (rgb !== e || drawingRequest !== d)
        fail($sformatf("pixel (%0d,%0d) = %02h/%0d, expected %02h/%0d (count %0d)", xd[2], yd[2], rgb, drawingRequest, e, d, count));
    end
  end

  initial begin
    repeat (5) @(posedge clk);
    resetN = 1'b1;
    for (int g = 0; g < 128; g++) begin
      champ[g] = (g % 17 == 0) ? 100 : (g % 13 == 0) ? 0 : $urandom_range(0, 100);
      top[g]   = $urandom_range(0, 100);
      mean[g]  = (g % 11 == 0) ? 100 : $urandom_range(0, 100);
      @(negedge clk);
      histWe = 1'b1;
      histWa = 7'(g);
      histWd = {7'(champ[g]), 7'(top[g]), 7'(mean[g])};
    end
    @(negedge clk);
    histWe = 1'b0;

    @(posedge clk iff startOfFrame);
    checking = 1;
    @(posedge clk iff startOfFrame);          // disabled: nothing drawn
    enable = 1'b1;
    foreach (count_list[i]) begin
      checking = 0;
      count = 8'(count_list[i]);
      repeat (4) @(posedge clk);
      checking = 1;
      @(posedge clk iff startOfFrame);
    end
    checking = 0;
    $display("INFO: %0d pixels compared, %0d of them drawn by the chart", checked, marked);
    if (checked < 1000000 || marked < 10000) fail("too few pixels compared");
    if (errors == 0) $display("PASS: tb_chart");
    else             $display("FAIL: tb_chart (%0d errors)", errors);
    $finish;
  end

endmodule
