// Checks water_background: only water-ramp or sand colours, never the reserved
// transparent value; pure water above the highest possible sand line, pure sand
// below the lowest one; water never gets brighter with depth.
`timescale 1ns / 1ps

module tb_water;
  import palette_pkg::*, game_params_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic [10:0] pixelX = '0, pixelY = '0;
  color_t      rgb;

  water_background dut (.clk(clk), .resetN(resetN), .pixelX(pixelX), .pixelY(pixelY), .RGBout(rgb));

  localparam color_t RAMP [0:8] = '{C_WATER_0, C_WATER_1, C_WATER_2, C_WATER_3, C_WATER_4,
                                    C_WATER_5, C_WATER_6, C_WATER_7, C_WATER_8};

  localparam int SAND_HIGHEST = SEABED_TOP;          // wave offset 0
  localparam int SAND_LOWEST  = SEABED_TOP + 7 + 7;  // both waves at their maximum

  int errors = 0;

  function automatic int ramp_index(input color_t c);
    for (int k = 0; k <= 8; k++) if (RAMP[k] == c) return k;
    return -1;
  endfunction

  function automatic bit is_sand(input color_t c);
    return c == C_SAND_LIGHT || c == C_SAND || c == C_SAND_DARK || c == C_PEBBLE;
  endfunction

  // The layer has a 3-clock latency: hold the coordinates, then sample.
  task automatic sample(input int x, input int y);
    @(negedge clk);
    pixelX = x;
    pixelY = y;
    repeat (3) @(negedge clk);
  endtask

  initial begin
    int idx;
    int rowSum [0:479];
    int sandPixels;

    repeat (2) @(posedge clk);
    resetN = 1'b1;

    sandPixels = 0;
    for (int y = 0; y < 480; y++) begin
      rowSum[y] = 0;
      for (int x = 0; x < 640; x++) begin
        sample(x, y);
        idx = ramp_index(rgb);
        if (rgb == TRANSPARENT || (idx < 0 && !is_sand(rgb))) begin
          errors++;
          if (errors < 5) $display("FAIL: (%0d,%0d) unexpected colour %h", x, y, rgb);
        end
        if (y < SAND_HIGHEST && idx < 0) begin
          errors++;
          if (errors < 5) $display("FAIL: (%0d,%0d) sand above the sea floor", x, y);
        end
        if (y > SAND_LOWEST + 1 && !is_sand(rgb)) begin
          errors++;
          if (errors < 5) $display("FAIL: (%0d,%0d) water below the sea floor", x, y);
        end
        if (is_sand(rgb)) sandPixels++;
        rowSum[y] += (idx < 0) ? 0 : idx;
      end
    end

    for (int y = 64; y < SAND_HIGHEST; y += 64) begin
      if (rowSum[y] < rowSum[y - 64]) begin
        errors++;
        $display("FAIL: row %0d brighter than row %0d", y, y - 64);
      end
    end
    if (rowSum[0] != 0) begin
      errors++;
      $display("FAIL: top row is not pure C_WATER_0");
    end
    $display("INFO: %0d sand pixels", sandPixels);

    if (errors == 0) $display("PASS: tb_water");
    else             $display("FAIL: tb_water (%0d errors)", errors);
    $finish;
  end

endmodule
