// Checks that water_background only produces ramp colours, never the reserved
// transparent value, and that colours darken monotonically with depth on average.
`timescale 1ns / 1ps

module tb_water;
  import palette_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic [10:0] pixelX = '0, pixelY = '0;
  color_t      rgb;

  water_background dut (.clk(clk), .resetN(resetN), .pixelX(pixelX), .pixelY(pixelY), .RGBout(rgb));

  localparam color_t RAMP [0:8] = '{C_WATER_0, C_WATER_1, C_WATER_2, C_WATER_3, C_WATER_4,
                                    C_WATER_5, C_WATER_6, C_WATER_7, C_WATER_8};

  int errors = 0;

  function automatic int ramp_index(input color_t c);
    for (int k = 0; k <= 8; k++) if (RAMP[k] == c) return k;
    return -1;
  endfunction

  // The layer has a 3-clock latency: hold the coordinates, then sample.
  task automatic sample(input int x, input int y, output int idx);
    @(negedge clk);
    pixelX = x;
    pixelY = y;
    repeat (3) @(negedge clk);
    idx = ramp_index(rgb);
  endtask

  initial begin
    int idx;
    int rowSum [0:479];

    repeat (2) @(posedge clk);
    resetN = 1'b1;

    for (int y = 0; y < 480; y++) begin
      rowSum[y] = 0;
      for (int x = 0; x < 640; x += 1) begin
        sample(x, y, idx);
        if (idx < 0 || rgb == TRANSPARENT) begin
          errors++;
          if (errors < 5) $display("FAIL: (%0d,%0d) colour %h not in ramp", x, y, rgb);
        end
        rowSum[y] += idx;
      end
    end

    // Top row is pure surface colour; average ramp index must never decrease with depth
    // when compared band to band (64-pixel steps).
    for (int y = 64; y < 480; y += 64) begin
      if (rowSum[y] < rowSum[y - 64]) begin
        errors++;
        $display("FAIL: row %0d brighter than row %0d", y, y - 64);
      end
    end
    if (rowSum[0] != 0) begin
      errors++;
      $display("FAIL: top row is not pure C_WATER_0");
    end

    if (errors == 0) $display("PASS: tb_water");
    else             $display("FAIL: tb_water (%0d errors)", errors);
    $finish;
  end

endmodule
