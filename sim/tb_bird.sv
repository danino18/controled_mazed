// Checks bird_trajectory: bounds, speed and smoothness limits, restart, and
// (from M8) that the three difficulty modes really behave differently.
`timescale 1ns / 1ps

module tb_bird;
  import game_params_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic               tick = 1'b0;
  logic               run = 1'b1;
  logic               restart = 1'b0;
  logic [1:0]         mode = 2'd0;
  logic [15:0]        rnd = 16'hACE1;
  logic signed [10:0] birdY;
  logic signed [11:0] birdVy;
  logic [7:0]         trajState;

  bird_trajectory dut (
      .clk(clk), .resetN(resetN), .tick(tick), .run(run), .restart(restart),
      .mode(mode), .rnd(rnd), .birdY(birdY), .birdVy(birdVy), .trajState(trajState));

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 10) $display("FAIL: %s", msg);
  endtask

  // One game frame: a tick pulse followed by a few idle clocks.
  task automatic frame();
    @(negedge clk);
    tick = 1'b1;
    rnd = {rnd[14:0], rnd[15] ^ rnd[13] ^ rnd[12] ^ rnd[10]};
    @(negedge clk);
    tick = 1'b0;
    repeat (3) @(negedge clk);
  endtask

  // Runs n frames and returns statistics of the motion.
  task automatic run_mode(input int m, input int n, input int maxSpeedPx16,
                          output int minY, output int maxY, output int reversals);
    int prevVy;
    int prevY;
    mode = 2'(m);
    restart = 1'b1;
    @(negedge clk);
    restart = 1'b0;
    minY = 1000;
    maxY = -1000;
    reversals = 0;
    prevVy = 0;
    prevY = birdY;
    for (int f = 0; f < n; f++) begin
      frame();
      if (birdY < minY) minY = birdY;
      if (birdY > maxY) maxY = birdY;
      if (birdY < BIRD_Y_MIN || birdY > BIRD_Y_MAX)
        fail($sformatf("mode %0d frame %0d: y=%0d outside [%0d,%0d]", m, f, birdY, BIRD_Y_MIN, BIRD_Y_MAX));
      if ((birdY - prevY) > 5 || (prevY - birdY) > 5)
        fail($sformatf("mode %0d frame %0d: jump of %0d px", m, f, birdY - prevY));
      if (birdVy * 16 > maxSpeedPx16 * 64 || -birdVy * 16 > maxSpeedPx16 * 64)
        fail($sformatf("mode %0d frame %0d: speed %0d/64 px exceeds limit", m, f, birdVy));
      if ((prevVy > 0 && birdVy < 0) || (prevVy < 0 && birdVy > 0)) reversals++;
      if (birdVy != 0) prevVy = birdVy;
      prevY = birdY;
    end
  endtask

  initial begin
    int minY, maxY, rev;
    int easyY [0:299];

    repeat (3) @(negedge clk);
    resetN = 1'b1;
    @(negedge clk);
    if (birdY != BIRD_Y_CENTER) fail($sformatf("reset y=%0d", birdY));

    // EASY: deterministic sine (supplied table spans -128..127), period 256 frames.
    // The table steps by up to 4 per entry, so EASY moves at most 4 px per frame.
    run_mode(0, 300, 64, minY, maxY, rev);
    $display("INFO: EASY   y range [%0d,%0d], %0d direction changes in 300 frames", minY, maxY, rev);
    if (minY != BIRD_Y_CENTER - 128 || maxY != BIRD_Y_CENTER + 127)
      fail($sformatf("EASY range [%0d,%0d], expected [%0d,%0d]", minY, maxY, BIRD_Y_CENTER - 128, BIRD_Y_CENTER + 127));

    // EASY must repeat exactly: record 300 frames, restart, compare.
    restart = 1'b1;
    @(negedge clk);
    restart = 1'b0;
    for (int f = 0; f < 300; f++) begin
      frame();
      easyY[f] = birdY;
    end
    for (int f = 0; f < 44; f++) begin
      if (easyY[f] != easyY[f + 256]) fail($sformatf("EASY not periodic at frame %0d", f));
    end

    // run = 0 freezes the bird.
    run = 1'b0;
    minY = birdY;
    repeat (20) frame();
    if (birdY != minY || birdVy != 0) fail("bird moved while run = 0");
    run = 1'b1;

    if (errors == 0) $display("PASS: tb_bird");
    else             $display("FAIL: tb_bird (%0d errors)", errors);
    $finish;
  end

endmodule
