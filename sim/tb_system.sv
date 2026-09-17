// The complete product (game_system, M12), driven only through its inputs
// (keyboard, KEY1, SW0, SW1, reset), with training shortened by parameters
// (runs of 150 steps, 2 generations) and the simulation speed at MAX.
//
//   1. after configuration there is no trained AI: the mode menu says NONE and
//      WATCH AI shows NO TRAINED AI (the hand-set demo network is not built in)
//   2. TRAIN AI -> EASY -> 1 coral: training runs to MAX GENERATIONS, the final
//      test runs, the TRAINING COMPLETE page appears with the completion sound
//   3. WATCH AI from that page: the game starts by itself in the training
//      world; the WATCH memory holds exactly the champion's genes; the AI
//      steers; SW1 shows the debug overlay naming the trained network
//   4. KEY0 (reset): the trained AI survives; its genes are still read by the
//      AI player; WATCH AI starts it again
//   5. TRAIN AI, pause, DISCARD RUN: the old AI stays
//   6. TRAIN AI, pause, KEEP THE BEST, TRAIN AGAIN (same world, new RUN ID),
//      MAIN MENU: the new champion replaces the old one; SW0 mutes the
//      completion sound
`timescale 1ns / 1ps

module tb_system;
  import game_state_pkg::*, ml_pkg::*, ui_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #15.873 clk = ~clk;

  logic [8:0]  keyCode = 9'h000;
  logic        keyMake = 1'b0;
  logic        keyBreak = 1'b0;
  logic        backN = 1'b1;
  logic        muteSw = 1'b0;
  logic        debugSw = 1'b0;
  logic [28:0] ovga;
  logic [6:0]  hex0, hex1, hex2, hex3, hex4, hex5;
  logic [9:0]  ledr;
  logic [15:0] audioSample;

  game_system dut (
      .clk(clk), .resetN(resetN), .keyCode(keyCode), .keyMake(keyMake), .keyBreak(keyBreak),
      .muteSw(muteSw), .debugSw(debugSw), .backN(backN),
      .OVGA(ovga), .HEX0(hex0), .HEX1(hex1), .HEX2(hex2), .HEX3(hex3), .HEX4(hex4), .HEX5(hex5),
      .LEDR(ledr), .audioSample(audioSample));

  defparam dut.BUTTON_STABLE_CLOCKS    = 20;
  defparam dut.gameLogic.READY_FRAMES  = 12;     // the watched game only has to start; replay equality is tb_train_flow's job
  defparam dut.trainer.T_LIMIT         = 150;
  defparam dut.trainer.MAX_GEN         = 2;
  defparam dut.trainer.HOLD_RUN_FRAMES = 1;
  defparam dut.trainer.HOLD_GEN_FRAMES = 1;

  localparam logic [8:0] KEY_UP = 9'h175, KEY_DOWN = 9'h172, KEY_ENTER = 9'h05A;

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 30) $display("FAIL: %s", msg);
  endtask

  // ---------------------------------------------------------------- stimulus helpers
  task automatic key_event(input logic [8:0] code, input bit isBreak);
    @(negedge clk);
    keyCode  = code;
    keyMake  = !isBreak;
    keyBreak = isBreak;
    @(negedge clk);
    keyMake  = 1'b0;
    keyBreak = 1'b0;
  endtask

  task automatic press(input logic [8:0] code);
    key_event(code, 0);
    repeat (1000) @(negedge clk);
    key_event(code, 1);
    repeat (1000) @(negedge clk);
  endtask

  task automatic key1();
    backN = 1'b0;
    repeat (100) @(negedge clk);
    backN = 1'b1;
    repeat (100) @(negedge clk);
  endtask

  task automatic frames(input int n);
    repeat (n) @(posedge clk iff dut.startOfFrame);
  endtask

  // the text of a cell range, after the current frame's text has been written
  function automatic string cells(input int row, input int col, input int len);
    string s;
    s = "";
    for (int k = 0; k < len; k++) s = {s, $sformatf("%c", 8'h20 + dut.textScreens.charRam[row * 80 + col + k][5:0])};
    return s;
  endfunction

  function automatic string hex_text(input logic [15:0] v);
    string s;
    s = $sformatf("%04h", v);
    return s.toupper();
  endfunction

  task automatic settle();                    // two frames: a new page is loaded and written
    frames(3);
  endtask

  task automatic cursor_to(input int item);
    while (dut.modeCursor > item) press(KEY_UP);
    while (dut.modeCursor < item) press(KEY_DOWN);
  endtask

  // from the mode menu: TRAIN AI -> EASY -> 1 coral (the menus remember the last choice)
  task automatic start_training();
    cursor_to(1);
    press(KEY_ENTER);
    while (dut.menuCursor > 0) press(KEY_UP);
    press(KEY_ENTER);
    while (dut.menuCursor > 0) press(KEY_UP);
    press(KEY_ENTER);
    if (!dut.trainScreen || !dut.trainActive) fail("training did not start");
  endtask

  // ---------------------------------------------------------------- shadows
  logic [7:0] chmp [64];
  logic [7:0] watchMem [64];
  int         watchWrites = 0;
  always @(posedge clk) begin
    if (dut.trainer.ctrl.chmpWe) chmp[dut.trainer.ctrl.chmpA] <= dut.trainer.ctrl.chmpWd;
    if (dut.watchWe) begin
      watchMem[dut.watchWa] <= dut.watchWd;
      watchWrites++;
    end
  end

  // the AI player reads gene geneAddr one clock later: check what it reads
  int   genesRead = 0, genesWrong = 0;
  logic [5:0] addrD;
  logic       readD;
  bit         checkReads = 0;
  always @(posedge clk) begin
    addrD <= dut.ai.geneAddr;
    readD <= dut.ai.sched.issuing;
    if (checkReads && readD && addrD < NN_GENES) begin
      genesRead++;
      if (dut.ai.gene !== watchMem[addrD]) genesWrong++;
    end
  end

  int chimes = 0;
  bit loudDuringChime = 0;
  always @(posedge clk) begin
    if (dut.chime[0]) chimes++;
    if (dut.sound.playingScore && muteSw && audioSample != 16'd0) loudDuringChime = 1;
  end

  task automatic wait_complete(input string when);
    int f;
    f = 0;
    while (!dut.trainComplete && f < 200) begin
      frames(1);
      f++;
    end
    if (!dut.trainComplete) fail($sformatf("%s: training did not complete", when));
    settle();
  endtask

  initial begin
    logic [15:0] firstRun;
    int          actions;
    repeat (5) @(posedge clk);
    resetN = 1'b1;
    settle();

    // ---- 1. nothing trained after configuration
    if (dut.page != PAGE_MODE) fail("no mode menu after configuration");
    if (cells(21, 10, 16) != "TRAINED AI  NONE") fail($sformatf("mode menu AI line '%s'", cells(21, 10, 16)));
    if (dut.aiCommitted || dut.watchValid) fail("an AI is available after configuration");
    cursor_to(2);
    press(KEY_ENTER);
    settle();
    if (dut.page != PAGE_NOAI) fail("WATCH AI without training did not show NO TRAINED AI");
    key1();
    settle();
    $display("INFO: 1. after configuration: TRAINED AI NONE, WATCH AI -> NO TRAINED AI");

    // ---- 2. train to completion
    force dut.simLevel = 3'd7;
    start_training();
    wait_complete("first training");
    if (dut.page != PAGE_DONE || dut.mode != 3'd6) fail("no TRAINING COMPLETE page");
    if (cells(7, 38, 8) != "MAX GEN ") fail($sformatf("result '%s'", cells(7, 38, 8)));
    if (cells(9, 29, 3) != "002") fail($sformatf("generations '%s'", cells(9, 29, 3)));
    if (cells(9, 41, 6) != "EASY  " || cells(9, 48, 1) != "1") fail("trained world not shown");
    if (cells(22, 24, 10) != "> WATCH AI") fail("cursor not on WATCH AI");
    if (chimes != 1) fail($sformatf("%0d completion chimes", chimes));
    if (!dut.aiCommitted || watchWrites != NN_GENES) fail("champion not committed");
    for (int g = 0; g < NN_GENES; g++)
      if (watchMem[g] !== chmp[g]) begin
        fail($sformatf("WATCH gene %0d = %02h, champion %02h", g, watchMem[g], chmp[g]));
        break;
      end
    firstRun = dut.aiRunId;
    $display("INFO: 2. trained RUN %04h: champion %0d gates %0d/4, test %0d gates %0d/8",
             firstRun, dut.sChampScore >> 16, dut.sChampW, dut.sTestScore >> 16, dut.sTestW);

    // ---- 3. WATCH AI from the TRAINING COMPLETE page
    release dut.simLevel;
    press(KEY_ENTER);
    frames(2);
    if (dut.mode != 3'd2 || !dut.aiMode) fail("WATCH AI did not start");
    if (dut.trainActive) fail("trainer still active while watching");
    wait (dut.screen == ST_PLAY);
    if (dut.difficulty != DIFF_EASY || dut.columnCount != 2'd1 || dut.speedLevel != dut.aiSpeed)
      fail("the watched game is not the training world");
    checkReads = 1;
    actions = 0;
    repeat (60) begin
      frames(1);
      if (dut.appliedAction != ACT_HOLD) actions++;
    end
    debugSw = 1'b1;
    settle();
    if (dut.page != PAGE_WATCHDBG) fail("SW1 did not show the debug overlay");
    if (cells(54, 3, 8) != "TRAINED " || cells(54, 17, 4) != hex_text(firstRun))
      fail($sformatf("debug overlay names '%s %s'", cells(54, 3, 8), cells(54, 17, 4)));
    debugSw = 1'b0;
    settle();
    if (dut.page != PAGE_WATCH && dut.screen != ST_HIT && dut.screen != ST_GAME_OVER) fail("overlay did not return");
    if (genesRead < 1000 || genesWrong != 0) fail($sformatf("AI player read %0d genes, %0d not the champion's", genesRead, genesWrong));
    $display("INFO: 3. WATCH AI: training world, %0d genes read = champion, %0d of 60 frames with a move", genesRead, actions);
    key1();
    settle();
    if (dut.mode != 3'd0) fail("KEY1 did not leave WATCH AI");
    if (cells(21, 22, 9) != {"RUN  ", hex_text(firstRun)}) fail($sformatf("mode menu AI line '%s'", cells(21, 22, 9)));

    // ---- 4. KEY0 keeps the trained AI
    checkReads = 0;
    @(negedge clk);
    resetN = 1'b0;
    repeat (50) @(negedge clk);
    resetN = 1'b1;
    settle();
    if (!dut.aiCommitted || dut.aiRunId != firstRun) fail("KEY0 lost the trained AI");
    if (cells(21, 22, 9) != {"RUN  ", hex_text(firstRun)}) fail("mode menu forgot the AI after KEY0");
    genesRead = 0;
    genesWrong = 0;
    checkReads = 1;
    cursor_to(2);
    press(KEY_ENTER);
    wait (dut.screen == ST_PLAY);
    frames(20);
    if (genesRead < 500 || genesWrong != 0) fail($sformatf("after KEY0 the AI read %0d genes, %0d wrong", genesRead, genesWrong));
    checkReads = 0;
    key1();
    settle();
    $display("INFO: 4. KEY0: the trained AI (RUN %04h) was kept and plays again", dut.aiRunId);

    // ---- 5. DISCARD keeps the old AI
    force dut.simLevel = 3'd6;
    start_training();
    frames(2);
    press(KEY_ENTER);
    settle();
    if (dut.page != PAGE_PAUSE || !dut.trainHold) fail("Enter did not pause training");
    press(KEY_DOWN);
    press(KEY_DOWN);
    press(KEY_ENTER);
    settle();
    if (dut.mode != 3'd0 || dut.trainActive) fail("DISCARD did not return to the mode menu");
    if (dut.aiRunId != firstRun) fail("DISCARD changed the committed AI");
    $display("INFO: 5. DISCARD RUN: back to the menu, RUN %04h kept", dut.aiRunId);

    // ---- 6. KEEP THE BEST, TRAIN AGAIN, muted completion, MAIN MENU
    force dut.simLevel = 3'd7;
    muteSw = 1'b1;
    start_training();
    wait (dut.trainer.ctrl.champExists);
    key1();                                        // pause
    press(KEY_DOWN);
    press(KEY_ENTER);                              // KEEP THE BEST
    wait_complete("kept run");
    if (cells(7, 38, 8) != "STOPPED " && cells(7, 38, 8) != "MAX GEN ") fail("kept run: result wrong");
    if (dut.aiRunId == firstRun) fail("KEEP THE BEST did not commit the new champion");
    firstRun = dut.aiRunId;
    press(KEY_DOWN);
    press(KEY_ENTER);                              // TRAIN AGAIN
    frames(1);
    if (dut.mode != 3'd4 && dut.mode != 3'd6) fail("TRAIN AGAIN did not return to training");
    wait_complete("TRAIN AGAIN");
    if (dut.trainer.cfgDifficulty != DIFF_EASY || dut.trainer.cfgColumns != 2'd1) fail("TRAIN AGAIN changed the world");
    if (dut.aiRunId == firstRun) fail("TRAIN AGAIN did not commit a new AI");
    if (loudDuringChime) fail("SW0 did not mute the completion sound");
    if (chimes != 3) fail($sformatf("%0d completion chimes in total, expected 3", chimes));
    repeat (2) press(KEY_DOWN);
    press(KEY_ENTER);                              // MAIN MENU
    settle();
    if (dut.mode != 3'd0 || dut.trainActive) fail("MAIN MENU did not leave training");
    if (cells(21, 22, 9) != {"RUN  ", hex_text(dut.aiRunId)}) fail("mode menu does not name the new AI");
    muteSw = 1'b0;
    release dut.simLevel;
    $display("INFO: 6. KEEP THE BEST, TRAIN AGAIN (RUN %04h), MAIN MENU; the completion sound was muted by SW0", dut.aiRunId);

    if (errors == 0) $display("PASS: tb_system");
    else             $display("FAIL: tb_system (%0d errors)", errors);
    $finish;
  end

endmodule
