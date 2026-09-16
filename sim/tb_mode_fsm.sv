// mode_fsm: every path between HUMAN PLAY, TRAIN AI and WATCH AI, the menu
// cursors, KEY1, the NO TRAINED AI screen, the routing outputs and the page
// shown in each mode.
`timescale 1ns / 1ps

module tb_mode_fsm;
  import game_state_pkg::*, ui_pkg::*;

  localparam logic [2:0] MD_MODE_MENU = 3'd0;
  localparam logic [2:0] MD_NO_AI     = 3'd1;
  localparam logic [2:0] MD_GAME      = 3'd2;
  localparam logic [2:0] MD_SETUP     = 3'd3;
  localparam logic [2:0] MD_TRAIN     = 3'd4;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic       up = 0, down = 0, enter = 0, back = 0, debugSw = 0, watchValid = 0;
  logic       menuStart = 0, trainStart = 0;
  logic [2:0] screen = ST_MENU_DIFF;
  logic [2:0] mode;
  logic [3:0] page;
  logic [1:0] cursor;
  logic       aiMode, trainMode, gameKeys, gameVisible, abortGame, trainAbort, trainScreen;

  mode_fsm dut (
      .clk(clk), .resetN(resetN), .upPulse(up), .downPulse(down), .enterPulse(enter),
      .backPulse(back), .debugSw(debugSw), .watchValid(watchValid), .screen(screen),
      .menuStart(menuStart), .trainStart(trainStart), .mode(mode), .cursor(cursor),
      .aiMode(aiMode), .trainMode(trainMode), .gameKeys(gameKeys), .gameVisible(gameVisible),
      .abortGame(abortGame), .trainAbort(trainAbort), .trainScreen(trainScreen), .page(page));

  int errors = 0;
  int aborts = 0;
  int trainAborts = 0;
  always @(posedge clk) if (abortGame) aborts++;
  always @(posedge clk) if (trainAbort) trainAborts++;

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

  task automatic expect_mode(input logic [2:0] m, input logic [2:0] p, input string when);
    if (mode != m) fail($sformatf("%s: mode %0d, expected %0d", when, mode, m));
    if (page != p) fail($sformatf("%s: page %0d, expected %0d", when, page, p));
  endtask

  task automatic expect_routing(input bit keys, input bit visible, input bit ai, input bit train, input string when);
    if (gameKeys != keys || gameVisible != visible || aiMode != ai || trainMode != train)
      fail($sformatf("%s: keys %0d visible %0d ai %0d train %0d, expected %0d %0d %0d %0d",
                     when, gameKeys, gameVisible, aiMode, trainMode, keys, visible, ai, train));
  endtask

  initial begin
    repeat (3) @(negedge clk);
    resetN = 1'b1;
    @(negedge clk);

    // ---- mode menu
    expect_mode(MD_MODE_MENU, PAGE_MODE, "after reset");
    expect_routing(0, 0, 0, 0, "mode menu");
    if (cursor != 0) fail("cursor not on HUMAN PLAY");
    pulse(up);
    if (cursor != 0) fail("cursor moved above HUMAN PLAY");
    repeat (3) pulse(down);
    if (cursor != 2) fail("cursor moved below WATCH AI");
    pulse(back);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "KEY1 in the mode menu");

    // ---- WATCH AI without a network
    pulse(enter);
    expect_mode(MD_NO_AI, PAGE_NOAI, "WATCH without a network");
    if (cursor != 0) fail("NO AI cursor not on TRAIN AI");
    repeat (2) pulse(down);
    if (cursor != 1) fail("NO AI cursor not clamped");
    pulse(enter);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "NO AI -> MAIN MENU");
    if (cursor != 2) fail("mode cursor not back on WATCH AI");
    pulse(enter);
    pulse(back);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "KEY1 on NO AI");
    pulse(enter);
    pulse(enter);                                    // TRAIN AI from NO AI
    expect_mode(MD_SETUP, PAGE_SETUP, "NO AI -> TRAIN AI");
    expect_routing(1, 1, 0, 1, "training setup");

    // ---- training setup: KEY1 aborts the menus
    aborts = 0;
    pulse(back);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "KEY1 in the training setup");
    if (aborts != 1) fail("KEY1 in the setup did not reset the game menus");
    if (cursor != 1) fail("mode cursor not on TRAIN AI");
    // ---- training setup: world chosen
    pulse(enter);
    expect_mode(MD_SETUP, PAGE_SETUP, "TRAIN AI");
    pulse(enter);                                    // Enter goes to the game menus, not here
    expect_mode(MD_SETUP, PAGE_SETUP, "Enter in the setup");
    pulse(trainStart);
    expect_mode(MD_TRAIN, PAGE_TRAIN, "world chosen");
    expect_routing(0, 0, 0, 0, "training");
    if (!trainScreen) fail("training screen flag not set");
    pulse(enter);
    pulse(up);
    pulse(down);
    expect_mode(MD_TRAIN, PAGE_TRAIN, "Enter and 8/2 during training");
    if (trainAborts != 0) fail("training stopped without KEY1");
    pulse(back);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "KEY1 on the training screen");
    if (trainAborts != 1) fail("KEY1 did not stop the training run");
    if (trainScreen) fail("training screen flag still set");
    if (cursor != 1) fail("mode cursor not on TRAIN AI after training");

    // ---- HUMAN PLAY
    pulse(up);
    if (cursor != 0) fail("cursor not on HUMAN PLAY");
    pulse(enter);
    expect_mode(MD_GAME, PAGE_NONE, "HUMAN PLAY");
    expect_routing(1, 1, 0, 0, "human game");
    screen = ST_PLAY;
    pulse(menuStart);                                // not a real MAIN MENU, but must be obeyed
    expect_mode(MD_MODE_MENU, PAGE_MODE, "MAIN MENU after a human game");
    if (cursor != 0) fail("cursor not back on HUMAN PLAY");
    pulse(enter);
    aborts = 0;
    pulse(back);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "KEY1 during a human game");
    if (aborts != 1) fail("KEY1 did not abort the game");

    // ---- WATCH AI with a network
    watchValid = 1'b1;
    repeat (2) pulse(down);
    screen = ST_MENU_DIFF;
    pulse(enter);
    expect_mode(MD_GAME, PAGE_NONE, "WATCH AI in the game menus (no overlay)");
    expect_routing(1, 1, 1, 0, "AI game");
    screen = ST_READY;
    @(negedge clk);
    if (page != PAGE_WATCH) fail("no AI overlay in GET READY");
    screen = ST_PLAY;
    debugSw = 1'b1;
    @(negedge clk);
    if (page != PAGE_WATCHDBG) fail("SW1 did not select the debug overlay");
    debugSw = 1'b0;
    screen = ST_GAME_OVER;
    @(negedge clk);
    if (page != PAGE_WATCH) fail("no AI overlay on GAME OVER");
    pulse(menuStart);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "MAIN MENU after watching");
    if (aiMode) fail("AI still steering in the mode menu");
    if (cursor != 2) fail("cursor not back on WATCH AI");
    pulse(enter);
    pulse(back);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "KEY1 while watching");
    if (aiMode) fail("AI still steering after KEY1");

    // ---- menuStart / trainStart outside their modes are ignored
    pulse(menuStart);
    pulse(trainStart);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "stray pulses");

    if (errors == 0) $display("PASS: tb_mode_fsm");
    else             $display("FAIL: tb_mode_fsm (%0d errors)", errors);
    $finish;
  end

endmodule
