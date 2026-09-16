// Checks game_fsm through every state and transition (report module #1).
`timescale 1ns / 1ps

module tb_game_fsm;
  import game_state_pkg::*;

  localparam int READY = 5, HIT = 4, LOCK = 3;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic       tick = 1'b0, upPulse = 1'b0, downPulse = 1'b0, enterPulse = 1'b0, collision = 1'b0;
  logic [2:0] state;
  logic [1:0] difficulty, columnCount, menuCursor;
  logic [7:0] stateFrames;
  logic       roundStart, roundOver, menuStart;

  game_fsm #(.READY_FRAMES(READY), .HIT_FRAMES(HIT), .OVER_LOCK_FRAMES(LOCK)) dut (
      .clk(clk), .resetN(resetN), .tick(tick), .upPulse(upPulse), .downPulse(downPulse),
      .enterPulse(enterPulse), .collision(collision), .state(state), .difficulty(difficulty),
      .columnCount(columnCount), .menuCursor(menuCursor), .stateFrames(stateFrames),
      .roundStart(roundStart), .roundOver(roundOver), .menuStart(menuStart));

  int errors = 0;
  int starts = 0, overs = 0, menus = 0;
  int visits [6];
  logic [2:0] lastState = ST_MENU_DIFF;

  always @(posedge clk) begin
    if (roundStart) starts++;
    if (roundOver) overs++;
    if (menuStart) menus++;
  end

  always @(negedge clk) begin
    if (resetN && state != lastState) begin
      $display("INFO: %0t  state %0d -> %0d", $time, lastState, state);
      visits[state]++;
      lastState = state;
    end
  end

  task automatic fail(input string msg);
    errors++;
    $display("FAIL: %s", msg);
  endtask

  task automatic pulse(ref logic sig);
    @(negedge clk);
    sig = 1'b1;
    @(negedge clk);
    sig = 1'b0;
    @(negedge clk);
  endtask

  task automatic frames(input int n, input bit crash = 0);
    repeat (n) begin
      @(negedge clk);
      tick = 1'b1;
      collision = crash;
      @(negedge clk);
      tick = 1'b0;
      collision = 1'b0;
      @(negedge clk);
    end
  endtask

  task automatic expect_state(input logic [2:0] s, input string when);
    if (state != s) fail($sformatf("%s: state %0d, expected %0d", when, state, s));
  endtask

  initial begin
    repeat (2) @(negedge clk);
    resetN = 1'b1;
    @(negedge clk);
    expect_state(ST_MENU_DIFF, "after reset");
    if (difficulty != DIFF_EASY || columnCount != 1 || menuCursor != 0) fail("reset defaults");

    // difficulty menu: clamped cursor
    pulse(upPulse);
    if (menuCursor != 0) fail("cursor moved above the first entry");
    repeat (3) pulse(downPulse);
    if (menuCursor != 2) fail("cursor moved below the last entry");
    pulse(upPulse);
    if (menuCursor != 1) fail("cursor did not move up");
    frames(3, 1);                                         // a crash signal in a menu is ignored
    expect_state(ST_MENU_DIFF, "crash signal in the menu");
    pulse(enterPulse);
    expect_state(ST_MENU_OBST, "Enter on MEDIUM");
    if (difficulty != DIFF_MEDIUM) fail("difficulty not MEDIUM");
    if (menuCursor != 0) fail("obstacle cursor not on the previous choice (1)");

    // obstacle menu
    repeat (2) pulse(downPulse);
    starts = 0;
    pulse(enterPulse);
    expect_state(ST_READY, "Enter on 3 CORALS");
    if (columnCount != 3) fail("column count not 3");
    if (starts != 1) fail($sformatf("%0d round starts, expected 1", starts));

    // READY lasts exactly READY frames and ignores keys and crash signals
    pulse(enterPulse);
    pulse(upPulse);
    frames(READY - 1, 1);
    expect_state(ST_READY, "one frame before the end of READY");
    frames(1);
    expect_state(ST_PLAY, "after READY");

    // PLAY until a crash
    frames(20);
    expect_state(ST_PLAY, "playing without a crash");
    overs = 0;
    frames(1, 1);
    expect_state(ST_HIT, "crash");
    if (overs != 1) fail("round-over pulse missing");
    frames(HIT - 1, 1);
    expect_state(ST_HIT, "one frame before the end of HIT");
    if (overs != 1) fail("extra round-over pulses during HIT");
    frames(1);
    expect_state(ST_GAME_OVER, "after HIT");
    if (menuCursor != 0) fail("GAME OVER cursor not on RESTART");

    // Enter is locked out at first, then RESTART keeps the settings
    pulse(enterPulse);
    expect_state(ST_GAME_OVER, "Enter during the lockout");
    frames(LOCK);
    starts = 0;
    pulse(enterPulse);
    expect_state(ST_READY, "RESTART");
    if (starts != 1 || difficulty != DIFF_MEDIUM || columnCount != 3) fail("RESTART changed the settings");

    // second round, then MAIN MENU
    frames(READY);
    expect_state(ST_PLAY, "second round");
    frames(1, 1);
    frames(HIT);
    expect_state(ST_GAME_OVER, "second game over");
    repeat (2) pulse(downPulse);
    if (menuCursor != 1) fail("GAME OVER cursor not clamped on MAIN MENU");
    frames(LOCK);
    menus = 0;
    starts = 0;
    pulse(enterPulse);
    expect_state(ST_MENU_DIFF, "MAIN MENU");
    if (menus != 1 || starts != 0) fail("MAIN MENU pulses wrong");
    if (menuCursor != DIFF_MEDIUM) fail("difficulty cursor not on the previous choice");
    pulse(enterPulse);
    if (menuCursor != 2) fail("obstacle cursor not on the previous choice (3)");

    for (int s = 0; s < 6; s++)
      if (visits[s] == 0) fail($sformatf("state %0d never visited", s));

    if (errors == 0) $display("PASS: tb_game_fsm");
    else             $display("FAIL: tb_game_fsm (%0d errors)", errors);
    $finish;
  end

endmodule
