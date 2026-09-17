// mode_fsm: every path between HUMAN PLAY, TRAIN AI and WATCH AI, the menu
// cursors, KEY1, the NO TRAINED AI screen, the pause menu, the TRAINING
// COMPLETE menu (WATCH AI / TRAIN AGAIN / MAIN MENU), the JTAG requests, the
// routing outputs and the page shown in each mode.
`timescale 1ns / 1ps

module tb_mode_fsm;
  import game_state_pkg::*, ui_pkg::*;

  localparam logic [2:0] MD_MODE_MENU = 3'd0;
  localparam logic [2:0] MD_NO_AI     = 3'd1;
  localparam logic [2:0] MD_GAME      = 3'd2;
  localparam logic [2:0] MD_SETUP     = 3'd3;
  localparam logic [2:0] MD_TRAIN     = 3'd4;
  localparam logic [2:0] MD_PAUSE     = 3'd5;
  localparam logic [2:0] MD_DONE      = 3'd6;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic       up = 0, down = 0, enter = 0, back = 0, debugSw = 0, watchValid = 0, watchTrained = 0;
  logic       menuStart = 0, trainStart = 0, remoteStart = 0, remoteStop = 0, remoteExit = 0;
  logic [2:0] screen = ST_MENU_DIFF;
  logic [2:0] mode;
  logic [3:0] page;
  logic [1:0] cursor;
  logic       aiMode, trainMode, gameKeys, gameVisible, abortGame;
  logic       trainGo, trainAgain, trainStop, trainAbort, trainHold, trainScreen, watchAuto, watchLoad;

  // A model of the trainer: starts on trainStart (from the setup menus),
  // trainGo or trainAgain (the latter also from COMPLETE); a stop completes it
  // when it has a champion, otherwise it goes idle; abort makes it idle.
  logic trainActive = 0, trainComplete = 0;
  bit   modelHasChampion = 1;

  always @(posedge clk) begin
    if ((trainStart && mode == MD_SETUP) || trainGo || trainAgain) begin
      trainActive   <= 1'b1;
      trainComplete <= 1'b0;
    end
    if (trainStop) begin
      if (modelHasChampion) trainComplete <= 1'b1;
      else                  trainActive   <= 1'b0;
    end
    if (trainAbort) begin
      trainActive   <= 1'b0;
      trainComplete <= 1'b0;
    end
  end

  mode_fsm dut (
      .clk(clk), .resetN(resetN), .upPulse(up), .downPulse(down), .enterPulse(enter),
      .backPulse(back), .debugSw(debugSw), .watchValid(watchValid), .watchTrained(watchTrained),
      .screen(screen), .menuStart(menuStart), .trainStart(trainStart), .trainActive(trainActive),
      .trainComplete(trainComplete), .remoteStart(remoteStart), .remoteStop(remoteStop),
      .remoteExit(remoteExit), .mode(mode), .cursor(cursor),
      .aiMode(aiMode), .trainMode(trainMode), .gameKeys(gameKeys), .gameVisible(gameVisible),
      .abortGame(abortGame), .trainGo(trainGo), .trainAgain(trainAgain), .trainStop(trainStop),
      .trainAbort(trainAbort), .trainHold(trainHold), .trainScreen(trainScreen),
      .watchAuto(watchAuto), .watchLoad(watchLoad), .page(page));

  int errors = 0;
  int aborts = 0, trainAborts = 0, trainStops = 0, trainGos = 0, trainAgains = 0, watchLoads = 0;
  always @(posedge clk) begin
    if (abortGame)  aborts++;
    if (trainAbort) trainAborts++;
    if (trainStop)  trainStops++;
    if (trainGo)    trainGos++;
    if (trainAgain) trainAgains++;
    if (watchLoad)  watchLoads++;
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

  task automatic expect_mode(input logic [2:0] m, input logic [3:0] p, input string when);
    if (mode != m) fail($sformatf("%s: mode %0d, expected %0d", when, mode, m));
    if (page != p) fail($sformatf("%s: page %0d, expected %0d", when, page, p));
  endtask

  task automatic expect_routing(input bit keys, input bit visible, input bit ai, input bit train, input string when);
    if (gameKeys != keys || gameVisible != visible || aiMode != ai || trainMode != train)
      fail($sformatf("%s: keys %0d visible %0d ai %0d train %0d, expected %0d %0d %0d %0d",
                     when, gameKeys, gameVisible, aiMode, trainMode, keys, visible, ai, train));
  endtask

  // from the mode menu (cursor anywhere) to the training screen
  task automatic start_training();
    while (cursor > 1) pulse(up);
    while (cursor < 1) pulse(down);
    pulse(enter);
    pulse(trainStart);
    if (mode != MD_TRAIN || !trainActive) fail("training did not start");
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

    // ---- WATCH AI with nothing trained (the product has no demo network)
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

    // ---- training setup
    aborts = 0;
    pulse(back);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "KEY1 in the training setup");
    if (aborts != 1) fail("KEY1 in the setup did not reset the game menus");
    if (cursor != 1) fail("mode cursor not on TRAIN AI");
    pulse(enter);
    expect_mode(MD_SETUP, PAGE_SETUP, "TRAIN AI");
    pulse(enter);                                    // Enter goes to the game menus, not here
    expect_mode(MD_SETUP, PAGE_SETUP, "Enter in the setup");
    pulse(trainStart);
    expect_mode(MD_TRAIN, PAGE_TRAIN, "world chosen");
    expect_routing(0, 0, 0, 0, "training");
    if (!trainScreen || trainHold) fail("training screen / hold flags wrong");
    pulse(up);
    pulse(down);
    expect_mode(MD_TRAIN, PAGE_TRAIN, "8/2 during training");

    // ---- pause menu: KEY1 and Enter open it; KEY1 and RESUME close it
    pulse(back);
    expect_mode(MD_PAUSE, PAGE_PAUSE, "KEY1 while training");
    if (!trainHold || !trainScreen || cursor != 0) fail("pause: hold, screen or cursor wrong");
    repeat (3) pulse(down);
    if (cursor != 2) fail("pause cursor not clamped");
    pulse(back);
    expect_mode(MD_TRAIN, PAGE_TRAIN, "KEY1 in the pause menu resumes");
    if (trainHold) fail("still holding after resume");
    pulse(enter);
    expect_mode(MD_PAUSE, PAGE_PAUSE, "Enter while training");
    pulse(enter);                                    // RESUME (cursor reset to 0)
    expect_mode(MD_TRAIN, PAGE_TRAIN, "RESUME");
    if (trainStops != 0 || trainAborts != 0) fail("pause sent a request without a choice");

    // ---- KEEP THE BEST -> COMPLETE -> DONE page
    pulse(enter);
    pulse(down);
    pulse(enter);
    if (trainStops != 1) fail("KEEP THE BEST did not stop");
    @(negedge clk);
    expect_mode(MD_DONE, PAGE_DONE, "training complete");
    if (cursor != 0 || !trainScreen || trainHold) fail("DONE page: cursor or flags wrong");
    watchTrained = 1'b1;          // the trainer committed its champion
    watchValid   = 1'b1;

    // DONE: MAIN MENU
    repeat (2) pulse(down);
    pulse(enter);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "DONE -> MAIN MENU");
    if (trainAborts != 1 || cursor != 2) fail("MAIN MENU: trainer not idle or cursor not on WATCH AI");

    // DONE: KEY1 = MAIN MENU
    start_training();
    pulse(remoteStop);                               // JTAG stop goes straight to the stop
    @(negedge clk);
    expect_mode(MD_DONE, PAGE_DONE, "JTAG stop");
    pulse(back);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "KEY1 on DONE");
    if (trainAborts != 2) fail("KEY1 on DONE did not send the trainer to idle");

    // DONE: TRAIN AGAIN, then DISCARD from the pause menu
    start_training();
    pulse(enter);
    pulse(down);
    pulse(enter);                                    // keep the best
    @(negedge clk);
    expect_mode(MD_DONE, PAGE_DONE, "complete again");
    pulse(down);
    pulse(enter);                                    // TRAIN AGAIN
    repeat (3) @(negedge clk);
    expect_mode(MD_TRAIN, PAGE_TRAIN, "TRAIN AGAIN");
    if (trainAgains != 1 || !trainActive || trainComplete) fail("TRAIN AGAIN did not restart the trainer");
    pulse(back);
    repeat (2) pulse(down);
    pulse(enter);                                    // DISCARD RUN
    expect_mode(MD_MODE_MENU, PAGE_MODE, "DISCARD RUN");
    if (trainAborts != 3 || cursor != 1) fail("DISCARD: trainer not idle or cursor not on TRAIN AI");

    // DONE: WATCH AI starts the trained champion at once
    start_training();
    pulse(back);
    pulse(down);
    pulse(enter);
    @(negedge clk);
    expect_mode(MD_DONE, PAGE_DONE, "complete for WATCH");
    screen = ST_MENU_DIFF;
    watchLoads = 0;
    pulse(enter);                                    // WATCH AI
    expect_mode(MD_GAME, PAGE_NONE, "DONE -> WATCH AI before the round starts");
    if (!watchAuto || watchLoads != 1 || trainAborts != 4) fail("WATCH AI from DONE: automatic start or trainer release missing");
    expect_routing(0, 0, 1, 0, "trained AI starting");
    screen = ST_READY;
    repeat (2) @(negedge clk);
    if (watchAuto) fail("automatic start still requested in GET READY");
    expect_routing(1, 1, 1, 0, "trained AI game");
    if (page != PAGE_WATCH) fail("no AI overlay for the trained AI");
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
    if (aiMode || cursor != 2) fail("AI still steering or cursor not on WATCH AI");

    // WATCH AI from the mode menu (trained)
    screen = ST_MENU_DIFF;
    pulse(enter);
    if (mode != MD_GAME || !watchAuto || !aiMode) fail("trained WATCH AI from the mode menu");
    screen = ST_READY;
    pulse(back);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "KEY1 while watching");
    if (aiMode || watchAuto) fail("AI still steering after KEY1");

    // ---- a stop before any champion: the screen follows the trainer back
    modelHasChampion = 0;
    screen = ST_MENU_DIFF;
    start_training();
    pulse(enter);
    pulse(down);
    pulse(enter);
    repeat (3) @(negedge clk);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "stop without a champion");
    if (cursor != 1) fail("mode cursor not on TRAIN AI after an empty training");
    modelHasChampion = 1;

    // ---- JTAG: start from the mode menu, exit is ignored while training, stop, exit
    trainGos = 0;
    pulse(remoteStart);
    expect_mode(MD_TRAIN, PAGE_TRAIN, "JTAG start");
    if (trainGos != 1 || !trainActive) fail("JTAG start did not start the trainer");
    pulse(remoteExit);
    expect_mode(MD_TRAIN, PAGE_TRAIN, "JTAG exit while training");
    pulse(remoteStop);
    @(negedge clk);
    expect_mode(MD_DONE, PAGE_DONE, "JTAG stop");
    pulse(remoteExit);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "JTAG exit after completion");
    pulse(remoteStop);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "JTAG stop in the mode menu is ignored");

    // ---- HUMAN PLAY
    repeat (2) pulse(up);
    if (cursor != 0) fail("cursor not on HUMAN PLAY");
    pulse(enter);
    expect_mode(MD_GAME, PAGE_NONE, "HUMAN PLAY");
    expect_routing(1, 1, 0, 0, "human game");
    screen = ST_PLAY;
    pulse(menuStart);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "MAIN MENU after a human game");
    if (cursor != 0) fail("cursor not back on HUMAN PLAY");
    pulse(enter);
    aborts = 0;
    pulse(back);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "KEY1 during a human game");
    if (aborts != 1) fail("KEY1 did not abort the game");

    // ---- stray pulses outside their modes are ignored
    pulse(menuStart);
    pulse(trainStart);
    expect_mode(MD_MODE_MENU, PAGE_MODE, "stray pulses");
    if (trainActive) fail("a stray trainStart started the trainer");

    if (errors == 0) $display("PASS: tb_mode_fsm");
    else             $display("FAIL: tb_mode_fsm (%0d errors)", errors);
    $finish;
  end

endmodule
