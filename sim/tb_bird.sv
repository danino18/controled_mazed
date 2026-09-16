// Checks bird_trajectory (report module #2): for EASY, MEDIUM and HARD the
// bird stays in its band, never jumps, respects the speed and acceleration
// limits, and the three modes really behave differently:
//   EASY   - exact 256-frame periodic sine,
//   MEDIUM - random direction decisions at a fixed 24-frame interval,
//   HARD   - random targets at irregular 6..37-frame intervals, covering the band.
`timescale 1ns / 1ps

module tb_bird;
  import game_params_pkg::*, game_state_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic               tick = 1'b0;
  logic               run = 1'b1;
  logic               restart = 1'b0;
  logic [1:0]         mode = DIFF_EASY;
  logic [15:0]        rnd;
  logic               rngLoad = 1'b0;
  logic [15:0]        rngSeed = 16'hACE1;
  logic signed [10:0] birdY;
  logic signed [11:0] birdVy;
  logic [7:0]         trajState;

  // the same random source as the game (one leap per frame)
  lfsr_rng rng (.clk(clk), .resetN(resetN), .step(tick), .seedLoad(rngLoad), .seed(rngSeed), .rnd(rnd));

  bird_trajectory dut (
      .clk(clk), .resetN(resetN), .tick(tick), .run(run), .restart(restart),
      .mode(mode), .rnd(rnd), .birdY(birdY), .birdVy(birdVy), .trajState(trajState));

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 12) $display("FAIL: %s", msg);
  endtask

  // One game frame: a tick pulse followed by a few idle clocks.
  task automatic frame();
    @(negedge clk);
    tick = 1'b1;
    @(negedge clk);
    tick = 1'b0;
    repeat (3) @(negedge clk);
  endtask

  typedef struct {
    int minY, maxY;
    int reversals;
    int decisions;
    int minInterval, maxInterval;
    int distinctIntervals;
    int maxSpeed, maxAccel;
  } stats_t;

  // Runs n frames in mode m and collects statistics.
  task automatic run_mode(input logic [1:0] m, input int n, input int speedLimit, input int accelLimit,
                          output stats_t s, output int ys[]);
    int prevVy, lastVy, prevY, lastDecision, prevState;
    bit seen [64];
    mode = m;
    restart = 1'b1;
    @(negedge clk);
    restart = 1'b0;
    ys = new[n];
    s.minY = 1000; s.maxY = -1000; s.reversals = 0; s.decisions = 0;
    s.minInterval = 1000; s.maxInterval = 0; s.distinctIntervals = 0;
    s.maxSpeed = 0; s.maxAccel = 0;
    foreach (seen[i]) seen[i] = 0;
    prevVy = 0; lastVy = 0; prevY = birdY; lastDecision = -1; prevState = trajState;
    for (int f = 0; f < n; f++) begin
      int speed, accel;
      frame();
      ys[f] = birdY;
      if (birdY < s.minY) s.minY = birdY;
      if (birdY > s.maxY) s.maxY = birdY;
      if (birdY < BIRD_Y_MIN || birdY > BIRD_Y_MAX)
        fail($sformatf("mode %0d frame %0d: y=%0d outside [%0d,%0d]", m, f, birdY, BIRD_Y_MIN, BIRD_Y_MAX));
      if (birdY - prevY > MAZE_STEP_MAX || prevY - birdY > MAZE_STEP_MAX)
        fail($sformatf("mode %0d frame %0d: moved %0d px (limit %0d)", m, f, birdY - prevY, MAZE_STEP_MAX));
      speed = birdVy < 0 ? -birdVy : birdVy;
      accel = birdVy - lastVy;                // change from the previous frame
      if (accel < 0) accel = -accel;
      if (speed > s.maxSpeed) s.maxSpeed = speed;
      // the speed drops to 0 when the bird stops at a limit; that is not counted as acceleration
      if (birdY != BIRD_Y_MIN && birdY != BIRD_Y_MAX && prevY != BIRD_Y_MIN && prevY != BIRD_Y_MAX && accel > s.maxAccel)
        s.maxAccel = accel;
      if (speed > speedLimit) fail($sformatf("mode %0d frame %0d: speed %0d/64 px > %0d", m, f, speed, speedLimit));
      if ((prevVy > 0 && birdVy < 0) || (prevVy < 0 && birdVy > 0)) s.reversals++;
      // a decision reloads the countdown (trajState jumps up)
      if (m != DIFF_EASY && int'(trajState) > prevState) begin
        if (lastDecision >= 0) begin
          int interval;
          interval = f - lastDecision;
          if (interval < s.minInterval) s.minInterval = interval;
          if (interval > s.maxInterval) s.maxInterval = interval;
          if (!seen[interval]) begin
            seen[interval] = 1;
            s.distinctIntervals++;
          end
        end
        lastDecision = f;
        s.decisions++;
      end
      prevState = trajState;
      if (birdVy != 0) prevVy = birdVy;       // last non-zero speed, for counting reversals
      lastVy = birdVy;
      prevY = birdY;
    end
    if (accelLimit >= 0 && s.maxAccel > accelLimit)
      fail($sformatf("mode %0d: acceleration %0d/64 px > %0d", m, s.maxAccel, accelLimit));
  endtask

  function automatic int difference(input int a[], input int b[]);
    int d;
    d = 0;
    foreach (a[i]) d += (a[i] > b[i]) ? a[i] - b[i] : b[i] - a[i];
    return d / a.size();
  endfunction

  initial begin
    stats_t statEasy, statMedium, statHard;
    int easyY[], mediumY[], hardY[], again[];

    repeat (3) @(negedge clk);
    resetN = 1'b1;
    @(negedge clk);
    if (birdY != BIRD_Y_CENTER) fail($sformatf("reset y=%0d", birdY));

    // ---------------------------------------------------------------- EASY
    run_mode(DIFF_EASY, 3000, 4 * 64, -1, statEasy, easyY);
    if (statEasy.minY != BIRD_Y_CENTER - 128 || statEasy.maxY != BIRD_Y_CENTER + 127)
      fail($sformatf("EASY range [%0d,%0d], expected [%0d,%0d]", statEasy.minY, statEasy.maxY, BIRD_Y_CENTER - 128, BIRD_Y_CENTER + 127));
    for (int f = 0; f + 256 < 3000; f++)
      if (easyY[f] != easyY[f + 256]) begin
        fail($sformatf("EASY not periodic at frame %0d", f));
        break;
      end

    // ---------------------------------------------------------------- MEDIUM
    run_mode(DIFF_MEDIUM, 3000, MEDIUM_SPEED, MEDIUM_ACCEL, statMedium, mediumY);
    if (statMedium.minInterval != MEDIUM_INTERVAL || statMedium.maxInterval != MEDIUM_INTERVAL)
      fail($sformatf("MEDIUM decision interval %0d..%0d, expected %0d", statMedium.minInterval, statMedium.maxInterval, MEDIUM_INTERVAL));
    if (statMedium.maxSpeed != MEDIUM_SPEED) fail($sformatf("MEDIUM never reaches its speed (%0d)", statMedium.maxSpeed));

    // ---------------------------------------------------------------- HARD
    run_mode(DIFF_HARD, 3000, HARD_MAX_SPEED, HARD_MAX_ACCEL + HARD_JITTER, statHard, hardY);
    if (statHard.minInterval < HARD_DWELL_MIN || statHard.maxInterval > HARD_DWELL_MIN + 31)
      fail($sformatf("HARD decision interval %0d..%0d outside %0d..%0d", statHard.minInterval, statHard.maxInterval, HARD_DWELL_MIN, HARD_DWELL_MIN + 31));
    if (statHard.distinctIntervals < 15)
      fail($sformatf("HARD has only %0d different decision intervals", statHard.distinctIntervals));
    if (statHard.minY > BIRD_Y_MIN + 40 || statHard.maxY < BIRD_Y_MAX - 80)
      fail($sformatf("HARD covers only [%0d,%0d]", statHard.minY, statHard.maxY));

    // ---------------------------------------------------------------- the modes differ
    if (statHard.reversals <= statEasy.reversals || statMedium.reversals <= statEasy.reversals)
      fail("MEDIUM/HARD do not change direction more often than EASY");
    if (difference(easyY, mediumY) < 20 || difference(easyY, hardY) < 20 || difference(mediumY, hardY) < 20)
      fail("two modes produce nearly the same motion");

    // MEDIUM and HARD depend on the random stream: another stream gives another path
    rngSeed = 16'h1D2F;
    rngLoad = 1'b1;
    @(negedge clk);
    rngLoad = 1'b0;
    run_mode(DIFF_HARD, 3000, HARD_MAX_SPEED, HARD_MAX_ACCEL + HARD_JITTER, statHard, again);
    if (difference(hardY, again) < 20) fail("HARD path does not depend on the random bits");

    $display("INFO: EASY   y [%0d,%0d]  reversals %0d  max speed %0d/64",
             statEasy.minY, statEasy.maxY, statEasy.reversals, statEasy.maxSpeed);
    $display("INFO: MEDIUM y [%0d,%0d]  reversals %0d  max speed %0d/64  max accel %0d/64  decisions %0d (every %0d frames)",
             statMedium.minY, statMedium.maxY, statMedium.reversals, statMedium.maxSpeed, statMedium.maxAccel, statMedium.decisions, statMedium.minInterval);
    $display("INFO: HARD   y [%0d,%0d]  reversals %0d  max speed %0d/64  max accel %0d/64  decisions %0d (every %0d..%0d frames, %0d different)",
             statHard.minY, statHard.maxY, statHard.reversals, statHard.maxSpeed, statHard.maxAccel, statHard.decisions,
             statHard.minInterval, statHard.maxInterval, statHard.distinctIntervals);
    $display("INFO: mean |y difference| EASY/MEDIUM %0d px, EASY/HARD %0d px, MEDIUM/HARD %0d px",
             difference(easyY, mediumY), difference(easyY, hardY), difference(mediumY, hardY));

    // run = 0 freezes the bird
    run = 1'b0;
    begin
      int y0;
      y0 = birdY;
      repeat (20) frame();
      if (birdY != y0 || birdVy != 0) fail("bird moved while run = 0");
    end
    run = 1'b1;

    if (errors == 0) $display("PASS: tb_bird");
    else             $display("FAIL: tb_bird (%0d errors)", errors);
    $finish;
  end

endmodule
