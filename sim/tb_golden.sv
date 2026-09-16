// Golden-trace regression for game_logic.
//
// Plays a fixed script through every difficulty and column count (menus, world
// speed changes, a noisy autopilot, crashes, RESTART, MAIN MENU) and hashes
// every change of every game_logic output together with the clock number it
// happened on. The expected hashes were recorded before game_logic was split
// into world_engine + lane_engine, so any change in behaviour or timing of the
// visible game shows up as a hash mismatch.
//
// It also checks that a round is a pure function of its seed: two rounds
// started from the same entropy value, after different histories, must be
// identical frame by frame.
//
//   +record    print the hashes in table form instead of checking them
`timescale 1ns / 1ps

module tb_golden;
  import game_params_pkg::*, game_state_pkg::*;

  localparam int CLOCKS_PER_FRAME = 8;
  localparam int SESSIONS = 9;

  // Recorded at the seed-then-restart baseline (before the world/lane split).
  localparam longint unsigned EXPECTED [SESSIONS] = '{
      64'he06379538bff45bf, 64'h3e72c468f632371b, 64'h2260a20edba09c30,
      64'hc08f687ca94968c3, 64'haa3d4ff0360d4704, 64'h4afc6cdbf596578e,
      64'hfffca2c840dd9e00, 64'h7e523eb4f9ade3b2, 64'hbf77041c657f97a3
  };

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  int   phase = 0;
  logic tickMove, tickCheck, tickState;
  always @(posedge clk) phase <= (phase + 1) % CLOCKS_PER_FRAME;
  assign tickMove  = resetN && (phase == 0);
  assign tickCheck = resetN && (phase == 1);
  assign tickState = resetN && (phase == 2);

  logic upHeld = 1'b0, downHeld = 1'b0, upPulse = 1'b0, downPulse = 1'b0, enterPulse = 1'b0;
  logic speedUpHeld = 1'b0, speedDownHeld = 1'b0;

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
  logic [2:0]                   speedLevel;
  logic                         scoreEvent, failEvent;

  game_logic #(.READY_FRAMES(10), .HIT_FRAMES(10), .OVER_LOCK_FRAMES(3)) dut (
      .clk(clk), .resetN(resetN), .tickMove(tickMove), .tickCheck(tickCheck), .tickState(tickState),
      .upHeld(upHeld), .downHeld(downHeld), .upPulse(upPulse), .downPulse(downPulse),
      .enterPulse(enterPulse), .speedUpHeld(speedUpHeld), .speedDownHeld(speedDownHeld),
      .entropyPulse(enterPulse),
      .aiMode(1'b0), .aiUp(1'b0), .aiDown(1'b0), .aiValid(1'b0),
      .trainMode(1'b0), .autoStart(1'b0), .autoDifficulty(2'd0), .autoColumns(2'd1), .abort(1'b0),
      .speedLoad(1'b0), .speedLoadLevel(3'd0), .trainStart(), .mazeVy(), .gapBase(),
      .screen(screen), .difficulty(difficulty), .columnCount(columnCount), .menuCursor(menuCursor),
      .stateFrames(stateFrames), .birdY(birdY), .birdVy(birdVy), .birdTrajState(birdTrajState),
      .mazeOffset(mazeOffset), .colActive(colActive), .colX(colX), .gapTop(gapTop),
      .gapBottom(gapBottom), .collision(collision), .hitColumn(hitColumn), .score(score),
      .best(best), .newBest(newBest), .speedLevel(speedLevel),
      .scoreEvent(scoreEvent), .failEvent(failEvent));

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 15) $display("FAIL: %s", msg);
  endtask

  // ---------------------------------------------------------------- hashing
  // FNV-1a over 32-bit words: {clock number, packed outputs}, folded whenever
  // any output changes.
  localparam int VEC_W = 188;
  logic [VEC_W-1:0] vec, prevVec;
  longint unsigned  hash;
  longint unsigned  clockNo = 0;

  assign vec = {screen, difficulty, columnCount, menuCursor, stateFrames, birdY, birdVy,
                birdTrajState, mazeOffset, colActive, colX, gapTop, gapBottom, collision,
                hitColumn, score, best, newBest, speedLevel, scoreEvent, failEvent};

  function automatic longint unsigned fnv(input longint unsigned h, input logic [31:0] w);
    return (h ^ longint'(w)) * 64'h00000100000001B3;
  endfunction

  always @(posedge clk) begin
    clockNo++;
    if (resetN && vec !== prevVec) begin
      logic [223:0] words;
      words = {clockNo[31:0], vec, 4'h0};
      for (int i = 0; i < 7; i++) hash = fnv(hash, words[i * 32 +: 32]);
      prevVec = vec;
    end
  end

  // ---------------------------------------------------------------- stimulus helpers
  task automatic frames(input int n);
    repeat (n) @(posedge clk iff phase == CLOCKS_PER_FRAME - 1);
  endtask

  task automatic pulse(ref logic sig);
    @(negedge clk);
    sig = 1'b1;
    @(negedge clk);
    sig = 1'b0;
    frames(1);
  endtask

  function automatic int dec(input logic [2:0][3:0] d);
    return d[2] * 100 + d[1] * 10 + d[0];
  endfunction

  // A 16-bit LFSR that makes the autopilot err now and then.
  logic [15:0] noise = 16'hBEEF;
  bit          autopilot = 1'b0;
  int          sleepFrames = 0;

  always @(negedge clk) begin
    if (phase == 4) begin
      noise = {noise[14:0], noise[15] ^ noise[13] ^ noise[12] ^ noise[10]};
      if (!autopilot) begin
        upHeld   = 1'b0;
        downHeld = 1'b0;
      end else begin
        int bestX, target, birdCentre;
        bit wantUp, wantDown;
        bestX  = 100000;
        target = -1;
        for (int i = 0; i < NUM_COLUMNS; i++) begin
          int x;
          x = int'($signed(colX[i]));
          if (colActive[i] && x + CORAL_W - CORAL_CORE_INSET > BIRD_X + BIRD_HB_X0 && x < bestX) begin
            bestX  = x;
            target = (int'(gapTop[i]) + int'(gapBottom[i])) / 2;
          end
        end
        birdCentre = int'(birdY) + (BIRD_HB_Y0 + BIRD_HB_Y1) / 2;
        wantUp   = (target >= 0) && (target > birdCentre + 6);
        wantDown = (target >= 0) && (target < birdCentre - 6);
        if (sleepFrames > 0) begin
          sleepFrames--;
          wantUp   = 1'b0;
          wantDown = 1'b0;
        end else if (noise[6:0] == 7'd0) begin
          sleepFrames = 20;                     // a lapse of attention
        end else if (noise[3:0] == 4'd7) begin
          {wantUp, wantDown} = {wantDown, wantUp};   // a wrong key for one frame
        end
        upHeld   = wantUp;
        downHeld = wantDown;
        if (noise[9:6] == 4'd3) begin               // sometimes both keys
          upHeld   = 1'b1;
          downHeld = 1'b1;
        end
      end
    end
  end

  task automatic set_speed(input int level);
    int guard;
    guard = 0;
    while (speedLevel != level && guard < 200) begin
      speedUpHeld   = speedLevel < level;
      speedDownHeld = speedLevel > level;
      frames(1);
      guard++;
    end
    speedUpHeld   = 1'b0;
    speedDownHeld = 1'b0;
    frames(1);
    if (speedLevel != level) fail($sformatf("could not reach speed level %0d", level));
  endtask

  task automatic select(input int diff, input int cols);
    while (menuCursor > diff) pulse(upPulse);
    while (menuCursor < diff) pulse(downPulse);
    pulse(enterPulse);
    while (menuCursor > cols - 1) pulse(upPulse);
    while (menuCursor < cols - 1) pulse(downPulse);
    pulse(enterPulse);
    if (screen != ST_READY || difficulty != diff || columnCount != cols)
      fail($sformatf("mode %0d/%0d not selected", diff, cols));
  endtask

  // speedDir: hold Numpad 4 (+1) or 6 (-1) for frames 20..49 of the round.
  task automatic play_until_crash(input int maxSteered, input int speedDir);
    int n;
    wait (screen == ST_PLAY);
    autopilot = 1'b1;
    n = 0;
    while (screen == ST_PLAY && n < maxSteered) begin
      speedUpHeld   = (speedDir > 0) && n >= 20 && n < 50;
      speedDownHeld = (speedDir < 0) && n >= 20 && n < 50;
      frames(1);
      n++;
    end
    speedUpHeld   = 1'b0;
    speedDownHeld = 1'b0;
    autopilot = 1'b0;
    sleepFrames = 0;
    while (screen == ST_PLAY) frames(1);
    wait (screen == ST_GAME_OVER);
  endtask

  task automatic session(input int s, output longint unsigned h, output int sc);
    int diff, cols;
    diff = s / 3;
    cols = s % 3 + 1;
    hash = 64'hCBF29CE484222325;
    set_speed((s * 3) % 8);
    select(diff, cols);
    play_until_crash(1500, 0);
    sc = dec(score);
    frames(5);
    pulse(enterPulse);                          // RESTART
    play_until_crash(200, s % 2 ? 1 : -1);      // the speed changes during this round
    frames(5);
    pulse(downPulse);
    pulse(enterPulse);                          // MAIN MENU
    if (screen != ST_MENU_DIFF) fail($sformatf("session %0d did not return to the menu", s));
    frames(3);
    h = hash;
  endtask

  // ---------------------------------------------------------------- seed purity
  // Hash of the world-related outputs over the first frames of a round.
  logic [15:0] forcedSeed;

  task automatic seeded_round(input logic [15:0] seed, input int warmup, output longint unsigned h);
    // different history before the round: idle frames plus random presses
    frames(warmup);
    forcedSeed = seed;
    force dut.entropy = forcedSeed;
    select(0, 2);
    h = 64'hCBF29CE484222325;
    repeat (150) begin
      frames(1);
      h = fnv(h, {birdY[10:0], birdVy[11:0], 9'd0});
      h = fnv(h, {colX[0], colX[1], 10'd0});
      h = fnv(h, {colX[2], gapTop[0], gapTop[1][9:9]});
      h = fnv(h, {gapTop[1][8:0], gapTop[2], mazeOffset, screen});
    end
    release dut.entropy;
    while (screen == ST_PLAY) frames(1);
    wait (screen == ST_GAME_OVER);
    frames(5);
    pulse(downPulse);
    pulse(enterPulse);
  endtask

  initial begin
    bit              record;
    longint unsigned h [SESSIONS];
    int              scores [SESSIONS];
    longint unsigned p1, p2;

    record = $test$plusargs("record");
    prevVec = '0;
    repeat (3) @(negedge clk);
    resetN = 1'b1;
    frames(3);

    for (int s = 0; s < SESSIONS; s++) begin
      session(s, h[s], scores[s]);
      $display("INFO: session %0d (%s, %0d column(s)): first-round score %0d, hash %016h", s,
               s / 3 == 0 ? "EASY" : s / 3 == 1 ? "MEDIUM" : "HARD", s % 3 + 1, scores[s], h[s]);
      if (!record && h[s] != EXPECTED[s])
        fail($sformatf("session %0d hash %016h, expected %016h", s, h[s], EXPECTED[s]));
    end

    if (record) begin
      $display("INFO: golden table:");
      for (int s = 0; s < SESSIONS; s++) $display("INFO:   64'h%016h%s", h[s], s < SESSIONS - 1 ? "," : "");
    end

    // the same seed after different histories gives the same round
    seeded_round(16'h1234, 7, p1);
    pulse(downPulse);                          // move the difficulty cursor, then back
    pulse(upPulse);
    seeded_round(16'h1234, 131, p2);
    if (p1 != p2) fail($sformatf("seed 1234 gave different rounds (%016h vs %016h)", p1, p2));
    seeded_round(16'h4321, 3, p2);
    if (p1 == p2) fail("different seeds gave identical rounds");

    if (errors == 0) $display("PASS: tb_golden");
    else             $display("FAIL: tb_golden (%0d errors)", errors);
    $finish;
  end

endmodule
