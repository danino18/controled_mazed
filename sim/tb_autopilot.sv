// Headless integration test: runs game_logic much faster than real time
// (one frame every few clocks, no VGA) and plays it with a simple autopilot
// that steers the next opening towards the bird using the arrow-key levels.
//
// For every difficulty and column count it checks that:
//   - the menus select what was asked for,
//   - all active columns keep moving together,
//   - the autopilot survives and the score equals the number of columns passed,
//   - without steering the bird crashes and the game reaches GAME OVER,
//   - RESTART and MAIN MENU work.
// It also reports how far the autopilot gets in each mode.
`timescale 1ns / 1ps

module tb_autopilot;
  import game_params_pkg::*, game_state_pkg::*;

  localparam int CLOCKS_PER_FRAME = 6;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------- per-frame ticks
  int   phase = 0;
  logic tickMove, tickCheck, tickState;
  always @(posedge clk) phase <= (phase + 1) % CLOCKS_PER_FRAME;
  assign tickMove  = resetN && (phase == 0);
  assign tickCheck = resetN && (phase == 1);
  assign tickState = resetN && (phase == 2);

  logic upHeld = 1'b0, downHeld = 1'b0, upPulse = 1'b0, downPulse = 1'b0, enterPulse = 1'b0;

  logic [2:0]                   screen;
  logic [1:0]                   difficulty, columnCount, menuCursor;
  logic [7:0]                   stateFrames;
  logic signed [10:0]           birdY;
  logic signed [11:0]           birdVy;
  logic [7:0]                   birdTrajState;
  logic signed [9:0]            mazeOffset;
  logic [NUM_COLUMNS-1:0]       colActive;
  logic [NUM_COLUMNS-1:0][10:0] colX;
  logic [NUM_COLUMNS-1:0][9:0]  gapTop, gapBottom;
  logic                         collision;
  logic [NUM_COLUMNS-1:0]       hitColumn;
  logic [2:0][3:0]              score, best;
  logic                         newBest;

  game_logic #(.READY_FRAMES(10), .HIT_FRAMES(10), .OVER_LOCK_FRAMES(3)) dut (
      .clk(clk), .resetN(resetN), .tickMove(tickMove), .tickCheck(tickCheck), .tickState(tickState),
      .upHeld(upHeld), .downHeld(downHeld), .upPulse(upPulse), .downPulse(downPulse),
      .enterPulse(enterPulse), .aiMode(1'b0), .aiUp(1'b0), .aiDown(1'b0), .aiValid(1'b0),
      .screen(screen), .difficulty(difficulty), .columnCount(columnCount), .menuCursor(menuCursor),
      .stateFrames(stateFrames), .birdY(birdY), .birdVy(birdVy), .birdTrajState(birdTrajState),
      .mazeOffset(mazeOffset), .colActive(colActive), .colX(colX), .gapTop(gapTop),
      .gapBottom(gapBottom), .collision(collision), .hitColumn(hitColumn), .score(score),
      .best(best), .newBest(newBest));

  int errors = 0;
  bit autopilot = 1'b0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 15) $display("FAIL: %s", msg);
  endtask

  function automatic int dec(input logic [2:0][3:0] d);
    return d[2] * 100 + d[1] * 10 + d[0];
  endfunction

  task automatic frames(input int n);
    repeat (n) @(posedge clk iff phase == CLOCKS_PER_FRAME - 1);
  endtask

  task automatic pulse(ref logic sig);
    @(negedge clk);
    sig = 1'b1;
    @(negedge clk);
    sig = 1'b0;
  endtask

  // ---------------------------------------------------------------- autopilot
  // Target: the first active column whose collision core has not yet passed
  // the bird. Steer so its opening centre follows the bird's centre.
  always @(negedge clk) begin
    if (!autopilot) begin
      upHeld   <= 1'b0;
      downHeld <= 1'b0;
    end else if (phase == 3) begin
      int best_x, target, birdCentre;
      best_x = 100000;
      target = -1;
      for (int i = 0; i < NUM_COLUMNS; i++) begin
        int x;
        x = int'($signed(colX[i]));
        if (colActive[i] && x + CORAL_W - CORAL_CORE_INSET > BIRD_X + BIRD_HB_X0 && x < best_x) begin
          best_x = x;
          target = (int'(gapTop[i]) + int'(gapBottom[i])) / 2;
        end
      end
      birdCentre = int'(birdY) + (BIRD_HB_Y0 + BIRD_HB_Y1) / 2;
      upHeld   <= (target >= 0) && (target > birdCentre + 6);
      downHeld <= (target >= 0) && (target < birdCentre - 6);
    end
  end

  // Every frame, every active opening moves exactly as much as the shared maze
  // offset. Skipped: a column that just wrapped (it gets a new random opening)
  // and openings clamped at the screen limits.
  int prevOffset;
  int prevTop [NUM_COLUMNS];
  int prevColX [NUM_COLUMNS];
  int together = 0;
  always @(posedge clk) begin
    if (tickCheck && screen == ST_PLAY) begin
      for (int i = 0; i < NUM_COLUMNS; i++) begin
        int moved, expected;
        bit wrapped, clamped;
        moved    = int'(gapTop[i]) - prevTop[i];
        expected = int'(mazeOffset) - prevOffset;
        wrapped  = int'($signed(colX[i])) > prevColX[i];
        clamped  = gapTop[i] == GAP_CENTER_MIN - GAP_H / 2 || gapTop[i] == GAP_CENTER_MAX - GAP_H / 2 ||
                   prevTop[i] == GAP_CENTER_MIN - GAP_H / 2 || prevTop[i] == GAP_CENTER_MAX - GAP_H / 2;
        if (colActive[i] && !wrapped && !clamped) begin
          if (moved != expected)
            fail($sformatf("column %0d opening moved %0d while the maze moved %0d", i, moved, expected));
          else if (expected != 0)
            together++;
        end
      end
    end
    if (tickCheck) begin
      prevOffset = int'(mazeOffset);
      for (int i = 0; i < NUM_COLUMNS; i++) begin
        prevTop[i]  = int'(gapTop[i]);
        prevColX[i] = int'($signed(colX[i]));
      end
    end
  end

  // Columns passed, counted independently from the design.
  int passes = 0;
  int prevX [NUM_COLUMNS];
  always @(posedge clk) begin
    if (tickCheck && screen == ST_PLAY) begin
      for (int i = 0; i < NUM_COLUMNS; i++) begin
        int x;
        x = int'($signed(colX[i]));
        if (colActive[i] && prevX[i] + CORAL_W - CORAL_CORE_INSET > BIRD_X + BIRD_HB_X0 &&
            x + CORAL_W - CORAL_CORE_INSET <= BIRD_X + BIRD_HB_X0)
          passes++;
      end
    end
    if (tickCheck) for (int i = 0; i < NUM_COLUMNS; i++) prevX[i] = int'($signed(colX[i]));
  end

  task automatic go_to_menu();
    if (screen != ST_MENU_DIFF) fail($sformatf("expected the difficulty menu, screen %0d", screen));
  endtask

  // Selects a mode from the menus (the cursor starts on the previous choice).
  task automatic select(input int diff, input int cols);
    while (menuCursor > diff) pulse(upPulse);
    while (menuCursor < diff) pulse(downPulse);
    pulse(enterPulse);
    if (screen != ST_MENU_OBST || difficulty != diff) fail($sformatf("difficulty %0d not selected", diff));
    while (menuCursor > cols - 1) pulse(upPulse);
    while (menuCursor < cols - 1) pulse(downPulse);
    pulse(enterPulse);
    if (screen != ST_READY || columnCount != cols) fail($sformatf("%0d columns not selected", cols));
  endtask

  task automatic play_mode(input int diff, input int cols, input int maxFrames);
    int survived, crashFrame;
    select(diff, cols);
    frames(12);
    if (screen != ST_PLAY) fail("READY did not end");
    passes = 0;
    autopilot = 1'b1;
    survived = 0;
    while (survived < maxFrames && screen == ST_PLAY) begin
      frames(1);
      survived++;
    end
    autopilot = 1'b0;
    if (survived < maxFrames) begin
      // a crash: the score must match the independent count
      if (dec(score) != passes) fail($sformatf("mode %0d/%0d: score %0d but %0d columns passed", diff, cols, dec(score), passes));
    end else begin
      if (dec(score) != passes) fail($sformatf("mode %0d/%0d: score %0d but %0d columns passed", diff, cols, dec(score), passes));
      // now let go: the bird must crash within a few columns
      crashFrame = 0;
      while (screen == ST_PLAY && crashFrame < 3000) begin
        frames(1);
        crashFrame++;
      end
      if (screen == ST_PLAY) fail($sformatf("mode %0d/%0d: no crash without steering", diff, cols));
    end
    $display("INFO: %s %0d column(s): autopilot %s after %0d frames, score %0d, best %0d",
             diff == 0 ? "EASY  " : diff == 1 ? "MEDIUM" : "HARD  ", cols,
             survived < maxFrames ? "crashed" : "still alive", survived, dec(score), dec(best));
    frames(12);
    if (screen != ST_GAME_OVER) fail($sformatf("mode %0d/%0d: not at GAME OVER (screen %0d)", diff, cols, screen));
  endtask

  initial begin
    int modes;
    repeat (3) @(negedge clk);
    resetN = 1'b1;
    frames(2);
    go_to_menu();
    if (!$value$plusargs("modes=%d", modes)) modes = 1;

    for (int diff = 0; diff < modes; diff++) begin
      for (int cols = 1; cols <= 3; cols++) begin
        play_mode(diff, cols, 2500);
        // alternate between RESTART (same mode, played again) and MAIN MENU
        frames(4);
        pulse(enterPulse);                              // RESTART
        if (screen != ST_READY || difficulty != diff || columnCount != cols) fail("RESTART changed the mode");
        frames(12);
        frames(5);
        autopilot = 1'b0;
        while (screen == ST_PLAY) frames(1);            // crash quickly
        frames(12);
        pulse(downPulse);
        frames(4);
        pulse(enterPulse);                              // MAIN MENU
        go_to_menu();
      end
    end

    $display("INFO: %0d column-frames confirmed moving together with the maze", together);
    if (together == 0) fail("no steering was observed");
    if (errors == 0) $display("PASS: tb_autopilot");
    else             $display("FAIL: tb_autopilot (%0d errors)", errors);
    $finish;
  end

endmodule
