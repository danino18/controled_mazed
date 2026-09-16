// Measures the frame and line period of the supplied VGA_Controller and checks
// that fps_meter reports the resulting frame rate.
`timescale 1ns / 1ps

module tb_vga_timing;

  localparam int CLOCKS_PER_SECOND = 31_500_000;
  localparam int EXPECTED_LINE     = 833;          // counter runs 0..H_TOTAL
  localparam int EXPECTED_FRAME    = 833 * 521;    // 0..V_TOTAL lines

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #15.873 clk = ~clk;                        // 31.5 MHz

  logic [10:0]     pixelX, pixelY;
  logic            startOfFrame;
  logic [28:0]     oVGA;
  logic [2:0][3:0] fpsBcd;

  VGA_Controller dut (
      .RGBIn(8'h00), .PixelX(pixelX), .PixelY(pixelY), .startOfFrame(startOfFrame),
      .oVGA(oVGA), .address(), .clk(clk), .resetN(resetN));

  fps_meter #(.CLOCKS_PER_SECOND(CLOCKS_PER_SECOND)) meter (
      .clk(clk), .resetN(resetN), .startOfFrame(startOfFrame), .fpsBcd(fpsBcd));

  int errors = 0;

  task automatic check(input bit ok, input string what);
    if (!ok) begin
      errors++;
      $display("FAIL: %s", what);
    end
  endtask

  // Clock count between consecutive events.
  longint cycle = 0;
  always @(posedge clk) cycle++;

  longint lastFrame = -1, framePeriod = 0, frames = 0;
  always @(posedge clk) if (startOfFrame) begin
    if (lastFrame >= 0) framePeriod = cycle - lastFrame;
    lastFrame = cycle;
    frames++;
  end

  logic hsPrev = 1'b1;
  longint lastLine = -1, linePeriod = 0;
  always @(posedge clk) begin
    if (!hsPrev && oVGA[24]) begin
      if (lastLine >= 0) linePeriod = cycle - lastLine;
      lastLine = cycle;
    end
    hsPrev = oVGA[24];
  end

  longint maxX = 0, maxY = 0;
  always @(posedge clk) begin
    if (pixelX > maxX) maxX = pixelX;
    if (pixelY > maxY) maxY = pixelY;
  end

  initial begin
    repeat (5) @(posedge clk);
    resetN = 1'b1;

    wait (frames == 3);
    check(linePeriod == EXPECTED_LINE,
          $sformatf("line period %0d clocks, expected %0d", linePeriod, EXPECTED_LINE));
    check(framePeriod == EXPECTED_FRAME,
          $sformatf("frame period %0d clocks, expected %0d", framePeriod, EXPECTED_FRAME));
    check(maxX == 640 && maxY == 480,
          $sformatf("pixel range reached X=%0d Y=%0d (controller exposes 0..640 / 0..480)", maxX, maxY));
    $display("INFO: frame period %0d clocks -> %0.3f frames/s",
             framePeriod, real'(CLOCKS_PER_SECOND) / real'(framePeriod));

    // Two full one-second windows of the meter.
    wait (cycle >= 2 * CLOCKS_PER_SECOND + 10);
    check(fpsBcd[2] == 4'd0 && fpsBcd[1] == 4'd7 && (fpsBcd[0] == 4'd2 || fpsBcd[0] == 4'd3),
          $sformatf("fps_meter shows %0d%0d%0d, expected 072 or 073", fpsBcd[2], fpsBcd[1], fpsBcd[0]));
    $display("INFO: fps_meter shows %0d%0d%0d", fpsBcd[2], fpsBcd[1], fpsBcd[0]);

    if (errors == 0) $display("PASS: tb_vga_timing");
    else             $display("FAIL: tb_vga_timing (%0d errors)", errors);
    $finish;
  end

endmodule
