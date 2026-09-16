// Checks obstacle_manager: placement, scrolling, wrap-around, scoring,
// opening geometry and the shared vertical offset, for each column count.
`timescale 1ns / 1ps

module tb_obstacles;
  import game_params_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic                         tickMove = 1'b0, tickCheck = 1'b0;
  logic                         run = 1'b1, restart = 1'b0;
  logic [1:0]                   columnCount = 2'd1;
  logic [11:0]                  worldStep = 12'd128;
  logic signed [9:0]            mazeOffset = '0;
  logic [15:0]                  rnd = 16'h1234;
  logic [NUM_COLUMNS-1:0]       active;
  logic [NUM_COLUMNS-1:0][10:0] colX;
  logic [NUM_COLUMNS-1:0][9:0]  gapTop, gapBottom;
  logic                         scorePulse;

  obstacle_manager dut (
      .clk(clk), .resetN(resetN), .tickMove(tickMove), .tickCheck(tickCheck),
      .run(run), .restart(restart), .columnCount(columnCount), .worldStep(worldStep),
      .mazeOffset(mazeOffset), .rnd(rnd), .active(active), .colX(colX),
      .gapTop(gapTop), .gapBottom(gapBottom), .scorePulse(scorePulse));

  int errors = 0;
  int scores = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 12) $display("FAIL: %s", msg);
  endtask

  // One frame: tickMove, then tickCheck, like frame_sequencer.
  task automatic frame();
    @(negedge clk);
    tickMove = 1'b1;
    rnd = {rnd[14:0], rnd[15] ^ rnd[13] ^ rnd[12] ^ rnd[10]};
    @(negedge clk);
    tickMove = 1'b0;
    tickCheck = 1'b1;
    @(negedge clk);
    tickCheck = 1'b0;
    if (scorePulse) scores++;
    @(negedge clk);
    if (scorePulse) scores++;
  endtask

  function automatic int sx(input int i);
    return int'($signed(colX[i]));
  endfunction

  task automatic check_geometry(input string when);
    for (int i = 0; i < NUM_COLUMNS; i++) begin
      if (int'(gapBottom[i]) - int'(gapTop[i]) != GAP_H)
        fail($sformatf("%s: column %0d opening height %0d", when, i, gapBottom[i] - gapTop[i]));
      if (gapTop[i] < GAP_CENTER_MIN - GAP_H / 2 || gapBottom[i] > GAP_CENTER_MAX + GAP_H / 2)
        fail($sformatf("%s: column %0d opening %0d..%0d off limits", when, i, gapTop[i], gapBottom[i]));
    end
  endtask

  task automatic run_count(input int count);
    int spacing, prev[NUM_COLUMNS], passFrames, expectedScores;
    spacing = CORAL_WRAP_W / count;
    columnCount = 2'(count);
    mazeOffset = '0;
    @(negedge clk);
    restart = 1'b1;
    @(negedge clk);
    restart = 1'b0;
    scores = 0;

    if (active != 3'((1 << count) - 1)) fail($sformatf("count %0d: active=%b", count, active));
    for (int i = 0; i < count; i++)
      if (sx(i) != CORAL_FIRST_X + i * spacing)
        fail($sformatf("count %0d: column %0d starts at %0d, expected %0d", count, i, sx(i), CORAL_FIRST_X + i * spacing));
    check_geometry("after restart");

    // 1500 frames at 2 px/frame = 3000 px of travel.
    expectedScores = 0;
    for (int f = 0; f < 1500; f++) begin
      for (int i = 0; i < NUM_COLUMNS; i++) prev[i] = sx(i);
      frame();
      for (int i = 0; i < count; i++) begin
        int moved;
        moved = prev[i] - sx(i);
        if (moved != 2 && moved != 2 - CORAL_WRAP_W)
          fail($sformatf("count %0d frame %0d: column %0d moved %0d", count, f, i, moved));
        if (sx(i) < -CORAL_W || sx(i) > CORAL_FIRST_X + 2 * spacing)
          fail($sformatf("count %0d frame %0d: column %0d at %0d", count, f, i, sx(i)));
        // a column passes the bird when its core's right edge crosses x = 153
        if (prev[i] + CORAL_W - CORAL_CORE_INSET > BIRD_X + BIRD_HB_X0 &&
            sx(i) + CORAL_W - CORAL_CORE_INSET <= BIRD_X + BIRD_HB_X0)
          expectedScores++;
      end
      // neighbours keep their spacing (modulo the wrap distance)
      for (int i = 1; i < count; i++) begin
        int gap;
        gap = ((sx(i) - sx(i - 1)) % CORAL_WRAP_W + CORAL_WRAP_W) % CORAL_WRAP_W;
        if (gap != spacing) fail($sformatf("count %0d frame %0d: spacing %0d", count, f, gap));
      end
      if (f % 100 == 0) check_geometry($sformatf("frame %0d", f));
    end
    if (scores != expectedScores || scores == 0)
      fail($sformatf("count %0d: %0d score pulses, expected %0d", count, scores, expectedScores));
    $display("INFO: %0d column(s): %0d columns passed in 1500 frames", count, scores);

    // Shared offset: every active column's opening moves by the same amount (until clamped).
    begin
      int topBefore[NUM_COLUMNS];
      for (int i = 0; i < NUM_COLUMNS; i++) topBefore[i] = gapTop[i];
      mazeOffset = 10'sd20;
      #1;
      for (int i = 0; i < count; i++) begin
        int expected;
        expected = topBefore[i] + 20;
        if (expected + GAP_H / 2 > GAP_CENTER_MAX) expected = GAP_CENTER_MAX - GAP_H / 2;
        if (gapTop[i] != expected) fail($sformatf("count %0d: column %0d offset +20 gave top %0d, expected %0d", count, i, gapTop[i], expected));
      end
      mazeOffset = 10'sd300;
      #1;
      for (int i = 0; i < count; i++)
        if (gapTop[i] != GAP_CENTER_MAX - GAP_H / 2) fail($sformatf("count %0d: offset +300 not clamped (%0d)", count, gapTop[i]));
      mazeOffset = -10'sd300;
      #1;
      for (int i = 0; i < count; i++)
        if (gapTop[i] != GAP_CENTER_MIN - GAP_H / 2) fail($sformatf("count %0d: offset -300 not clamped (%0d)", count, gapTop[i]));
      mazeOffset = '0;
    end

    // run = 0 freezes the columns and scoring
    run = 1'b0;
    for (int i = 0; i < NUM_COLUMNS; i++) prev[i] = sx(i);
    scores = 0;
    repeat (50) frame();
    for (int i = 0; i < NUM_COLUMNS; i++) if (sx(i) != prev[i]) fail("column moved while run = 0");
    if (scores != 0) fail("scored while run = 0");
    run = 1'b1;
  endtask

  initial begin
    int counts;
    repeat (2) @(negedge clk);
    resetN = 1'b1;
    if (!$value$plusargs("counts=%d", counts)) counts = 3;
    for (int c = 1; c <= counts; c++) run_count(c);

    if (errors == 0) $display("PASS: tb_obstacles");
    else             $display("FAIL: tb_obstacles (%0d errors)", errors);
    $finish;
  end

endmodule
