// Checks maze_control: speed ramp while holding a key, clamping, no motion
// for both/neither keys or when frozen, and restart.
`timescale 1ns / 1ps

module tb_maze;
  import game_params_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic              tick = 1'b0, run = 1'b1, restart = 1'b0;
  logic              moveUp = 1'b0, moveDown = 1'b0;
  logic signed [9:0] mazeOffset;
  logic signed [4:0] mazeVy;

  maze_control dut (
      .clk(clk), .resetN(resetN), .tick(tick), .run(run), .restart(restart),
      .moveUp(moveUp), .moveDown(moveDown), .mazeOffset(mazeOffset), .mazeVy(mazeVy));

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 10) $display("FAIL: %s", msg);
  endtask

  task automatic frame();
    @(negedge clk);
    tick = 1'b1;
    @(negedge clk);
    tick = 1'b0;
    @(negedge clk);
  endtask

  initial begin
    int expected, prev, stepSize;

    repeat (2) @(negedge clk);
    resetN = 1'b1;
    if (mazeOffset != 0) fail("offset not 0 after reset");

    // hold Down: steps 1,1,1,1,2,2,2,2,3,3,3,3,4,4,...
    moveDown = 1'b1;
    expected = 0;
    for (int f = 0; f < 30; f++) begin
      frame();
      stepSize = (f >= 12) ? MAZE_STEP_MAX : 1 + f / 4;
      expected += stepSize;
      if (mazeOffset != expected) fail($sformatf("hold down frame %0d: offset %0d, expected %0d", f, mazeOffset, expected));
      if (mazeVy != stepSize) fail($sformatf("hold down frame %0d: vy %0d, expected %0d", f, mazeVy, stepSize));
    end

    // release: no motion, ramp restarts
    moveDown = 1'b0;
    prev = mazeOffset;
    repeat (5) frame();
    if (mazeOffset != prev || mazeVy != 0) fail("maze moved with no key");

    // both keys: no motion
    moveUp = 1'b1;
    moveDown = 1'b1;
    repeat (5) frame();
    if (mazeOffset != prev) fail("maze moved with both keys");
    moveDown = 1'b0;

    // Up alone starts slowly again
    frame();
    if (mazeOffset != prev - 1) fail($sformatf("first Up step %0d, expected 1", prev - mazeOffset));

    // long hold clamps
    repeat (200) frame();
    if (mazeOffset != -MAZE_OFFSET_MAX) fail($sformatf("offset %0d not clamped to %0d", mazeOffset, -MAZE_OFFSET_MAX));
    moveUp = 1'b0;
    moveDown = 1'b1;
    repeat (200) frame();
    if (mazeOffset != MAZE_OFFSET_MAX) fail($sformatf("offset %0d not clamped to %0d", mazeOffset, MAZE_OFFSET_MAX));

    // frozen
    run = 1'b0;
    moveDown = 1'b0;
    moveUp = 1'b1;
    prev = mazeOffset;
    repeat (10) frame();
    if (mazeOffset != prev || mazeVy != 0) fail("maze moved while run = 0");
    run = 1'b1;

    // restart
    @(negedge clk);
    restart = 1'b1;
    @(negedge clk);
    restart = 1'b0;
    if (mazeOffset != 0) fail("restart did not centre the maze");

    if (errors == 0) $display("PASS: tb_maze");
    else             $display("FAIL: tb_maze (%0d errors)", errors);
    $finish;
  end

endmodule
