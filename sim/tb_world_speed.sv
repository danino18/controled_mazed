// Checks world_speed_control: Numpad 4 (speedUpHeld) increases the level,
// Numpad 6 (speedDownHeld) decreases it, bounds are never exceeded (never
// zero/negative worldStep), holding both makes no change, releasing leaves
// the level exactly where it was, and the step cadence matches the design.
`timescale 1ns / 1ps

module tb_world_speed;
  import game_params_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic       tick = 1'b0, speedUpHeld = 1'b0, speedDownHeld = 1'b0;
  logic [2:0] speedLevel;
  logic [11:0] worldStep;

  world_speed_control dut (
      .clk(clk), .resetN(resetN), .tick(tick), .speedUpHeld(speedUpHeld),
      .speedDownHeld(speedDownHeld), .speedLevel(speedLevel), .worldStep(worldStep));

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 15) $display("FAIL: %s", msg);
  endtask

  task automatic frame();
    @(negedge clk);
    tick = 1'b1;
    @(negedge clk);
    tick = 1'b0;
    @(negedge clk);
  endtask

  // The worldStep <-> speedLevel formula, expected to always be positive.
  function automatic int expected_step(input int level);
    return WORLD_STEP_BASE + WORLD_STEP_INCREMENT * level;
  endfunction

  task automatic check_consistent(input string when);
    if (worldStep != expected_step(speedLevel))
      fail($sformatf("%s: worldStep=%0d does not match level %0d (expected %0d)",
                     when, worldStep, speedLevel, expected_step(speedLevel)));
    if (worldStep <= 0) fail($sformatf("%s: worldStep=%0d is not a safe positive speed", when, worldStep));
    if (speedLevel < WORLD_SPEED_LEVEL_MIN[2:0] || speedLevel > WORLD_SPEED_LEVEL_MAX[2:0])
      fail($sformatf("%s: level %0d outside [%0d,%0d]", when, speedLevel, WORLD_SPEED_LEVEL_MIN, WORLD_SPEED_LEVEL_MAX));
  endtask

  initial begin
    int prevLevel;

    repeat (3) @(negedge clk);
    resetN = 1'b1;
    @(negedge clk);
    if (speedLevel != WORLD_SPEED_LEVEL_RESET[2:0])
      fail($sformatf("reset level %0d, expected %0d", speedLevel, WORLD_SPEED_LEVEL_RESET));
    check_consistent("after reset");

    // ---------------------------------------------------------------- Numpad 4 increases, step cadence
    speedUpHeld = 1'b1;
    for (int f = 0; f < WORLD_SPEED_STEP_FRAMES - 1; f++) begin
      frame();
      if (speedLevel != WORLD_SPEED_LEVEL_RESET[2:0])
        fail($sformatf("level changed after only %0d held frames (step is every %0d)", f + 1, WORLD_SPEED_STEP_FRAMES));
    end
    frame();   // the WORLD_SPEED_STEP_FRAMES-th frame
    if (speedLevel != WORLD_SPEED_LEVEL_RESET[2:0] + 1)
      fail($sformatf("level did not increase after %0d held frames (level=%0d)", WORLD_SPEED_STEP_FRAMES, speedLevel));
    check_consistent("after first Numpad 4 step");

    // keep holding: one more step every WORLD_SPEED_STEP_FRAMES frames, up to the max
    prevLevel = speedLevel;
    for (int step = 0; step < 20; step++) begin
      repeat (WORLD_SPEED_STEP_FRAMES) frame();
      check_consistent($sformatf("Numpad 4 held, step %0d", step));
      if (speedLevel == WORLD_SPEED_LEVEL_MAX[2:0]) begin
        if (prevLevel != speedLevel && prevLevel != speedLevel - 1)
          fail("level jumped by more than one while climbing");
        break;
      end
      if (speedLevel != prevLevel + 1) fail($sformatf("step %0d: level %0d, expected %0d", step, speedLevel, prevLevel + 1));
      prevLevel = speedLevel;
    end
    if (speedLevel != WORLD_SPEED_LEVEL_MAX[2:0]) fail($sformatf("never reached the max level (stuck at %0d)", speedLevel));

    // held past the max: stays at the max, never wraps or goes unsafe
    repeat (5 * WORLD_SPEED_STEP_FRAMES) frame();
    if (speedLevel != WORLD_SPEED_LEVEL_MAX[2:0]) fail($sformatf("level left the max bound: %0d", speedLevel));
    check_consistent("held past the max");
    speedUpHeld = 1'b0;

    // release: level holds exactly where it is, with no decay
    repeat (10 * WORLD_SPEED_STEP_FRAMES) frame();
    if (speedLevel != WORLD_SPEED_LEVEL_MAX[2:0]) fail("level decayed after releasing Numpad 4");

    // ---------------------------------------------------------------- Numpad 6 decreases
    speedDownHeld = 1'b1;
    prevLevel = speedLevel;
    for (int step = 0; step < 20; step++) begin
      repeat (WORLD_SPEED_STEP_FRAMES) frame();
      check_consistent($sformatf("Numpad 6 held, step %0d", step));
      if (speedLevel == WORLD_SPEED_LEVEL_MIN[2:0]) break;
      if (speedLevel != prevLevel - 1) fail($sformatf("step %0d: level %0d, expected %0d", step, speedLevel, prevLevel - 1));
      prevLevel = speedLevel;
    end
    if (speedLevel != WORLD_SPEED_LEVEL_MIN[2:0]) fail($sformatf("never reached the min level (stuck at %0d)", speedLevel));

    // held past the min: stays at the min, never goes to zero/negative
    repeat (5 * WORLD_SPEED_STEP_FRAMES) frame();
    if (speedLevel != WORLD_SPEED_LEVEL_MIN[2:0]) fail($sformatf("level left the min bound: %0d", speedLevel));
    check_consistent("held past the min");
    if (worldStep != WORLD_STEP_BASE) fail("min level does not give the intended slowest-but-safe speed");
    speedDownHeld = 1'b0;

    // ---------------------------------------------------------------- both held: no change
    speedUpHeld   = 1'b1;
    speedDownHeld = 1'b1;
    prevLevel = speedLevel;
    repeat (10 * WORLD_SPEED_STEP_FRAMES) frame();
    if (speedLevel != prevLevel) fail($sformatf("level changed while both Numpad 4 and 6 were held: %0d -> %0d", prevLevel, speedLevel));
    speedUpHeld   = 1'b0;
    speedDownHeld = 1'b0;

    // after both released, a single hold starts a fresh step count from zero
    // (no partial credit carried over from the "both held" period)
    speedUpHeld = 1'b1;
    for (int f = 0; f < WORLD_SPEED_STEP_FRAMES - 1; f++) begin
      frame();
      if (speedLevel != prevLevel) fail("level changed before a full fresh step after releasing both keys");
    end
    frame();
    if (speedLevel != prevLevel + 1) fail("fresh single-hold step did not land exactly at STEP_FRAMES");
    speedUpHeld = 1'b0;

    // ---------------------------------------------------------------- neither held: frozen, no drift
    prevLevel = speedLevel;
    repeat (10 * WORLD_SPEED_STEP_FRAMES) frame();
    if (speedLevel != prevLevel) fail("level drifted while neither key was held");

    if (errors == 0) $display("PASS: tb_world_speed");
    else             $display("FAIL: tb_world_speed (%0d errors)", errors);
    $finish;
  end

endmodule
