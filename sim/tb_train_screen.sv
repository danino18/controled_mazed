// TRAIN AI on the whole system (game_system): the training screen tells the truth.
//
// Training is started with the keys (TRAIN AI -> MEDIUM -> 2 corals). Then,
// for several frames at SIM x4 and at MAX:
//   - the trainer's snapshot is taken after the frame starts and before the
//     text writer starts, and never while the writer runs
//   - the text of every lane label (candidate, state, action, gates, fitness,
//     steps) and of the header (RUN ID, generation, batch, world, seed, play
//     step) equals the snapshot the lane windows are drawn from
//   - LEDR[8:1] show the live alive mask, HEX5..3 the generation
//   - Numpad 4 held on the training screen raises the simulation speed and
//     leaves the world speed unchanged; the game menus do not move
//   - KEY1 opens the pause menu (the lanes wait) and closes it again; Enter
//     opens it too; KEEP THE BEST stops training: final test, committed
//     champion, the completion sound and the TRAINING COMPLETE page; KEY1 there
//     goes to the mode menu, which now names the trained AI
`timescale 1ns / 1ps

module tb_train_screen;
  import game_state_pkg::*, ml_pkg::*, ui_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #15.873 clk = ~clk;

  logic [8:0]  keyCode = 9'h000;
  logic        keyMake = 1'b0;
  logic        keyBreak = 1'b0;
  logic        backN = 1'b1;
  logic [28:0] ovga;
  logic [6:0]  hex0, hex1, hex2, hex3, hex4, hex5;
  logic [9:0]  ledr;
  logic [15:0] audioSample;

  game_system dut (
      .clk(clk), .resetN(resetN), .keyCode(keyCode), .keyMake(keyMake), .keyBreak(keyBreak),
      .muteSw(1'b0), .debugSw(1'b0), .backN(backN),
      .OVGA(ovga), .HEX0(hex0), .HEX1(hex1), .HEX2(hex2), .HEX3(hex3), .HEX4(hex4), .HEX5(hex5),
      .LEDR(ledr), .audioSample(audioSample));

  defparam dut.BUTTON_STABLE_CLOCKS = 20;

  localparam logic [8:0] KEY_DOWN = 9'h172, KEY_ENTER = 9'h05A, KEY_PAD4 = 9'h06B;

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 30) $display("FAIL: %s", msg);
  endtask

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

  task automatic press_key1();
    backN = 1'b0;
    repeat (100) @(negedge clk);
    backN = 1'b1;
    repeat (100) @(negedge clk);
  endtask

  task automatic wait_frames(input int n);
    repeat (n) @(posedge clk iff dut.startOfFrame);
  endtask

  // ---------------------------------------------------------------- screen text
  function automatic string cells(input int row, input int col, input int len);
    string s;
    s = "";
    for (int k = 0; k < len; k++) s = {s, $sformatf("%c", 8'h20 + dut.textScreens.charRam[row * 80 + col + k][5:0])};
    return s;
  endfunction

  function automatic string dec(input longint v, input int n);
    string s;
    s = "";
    for (int i = 0; i < n; i++) begin
      s = {$sformatf("%0d", v % 10), s};
      v /= 10;
    end
    return s;
  endfunction

  function automatic string hex_text(input logic [15:0] v);
    string s;
    s = $sformatf("%04h", v);
    return s.toupper();
  endfunction

  function automatic string state_word(input logic [1:0] s);
    case (s)
      LANE_ALIVE: return "ALIVE";
      LANE_DEAD:  return "DEAD ";
      LANE_DONE:  return "DONE ";
      default:    return "IDLE ";
    endcase
  endfunction

  function automatic string act_word(input logic [1:0] a);
    return (a == ACT_UP) ? "UP  " : (a == ACT_DOWN) ? "DOWN" : "HOLD";
  endfunction

  // ---------------------------------------------------------------- snapshot timing
  int  sinceFrame = -1;
  bit  snapThisFrame = 0;
  bit  trainAtFrame = 0;
  bit  writerBusy = 0;
  int  frames = 0;

  always @(posedge clk) begin
    if (dut.startOfFrame) begin
      if (dut.trainScreen && trainAtFrame && !snapThisFrame) fail("a frame without a snapshot");
      trainAtFrame = dut.trainScreen;
      sinceFrame    = 0;
      snapThisFrame = 0;
    end else if (sinceFrame >= 0) sinceFrame++;
    if (dut.trainer.snapTaken) begin
      if (writerBusy) fail("snapshot taken while the text writer was running");
      if (snapThisFrame) fail("two snapshots in one frame");
      snapThisFrame = 1;
    end
    if (dut.textFrame) begin
      if (dut.trainScreen && !snapThisFrame && dut.trainer.active) fail("text writer started before the snapshot");
      writerBusy = 1;
    end
    if (writerBusy && dut.textScreens.writerIdle) writerBusy = 0;
  end

  // ---------------------------------------------------------------- one frame's text against the snapshot
  task automatic check_frame(input string when);
    wait_frames(1);
    @(posedge clk iff dut.textFrame);
    @(posedge clk);
    while (!dut.textScreens.writerIdle) @(posedge clk);
    frames++;
    for (int k = 0; k < LANES; k++) begin
      int b, r;
      b = 20 * (k % 4);
      r = (k < 4) ? 19 : 35;
      if (cells(r, b + 1, 2) != dec(dut.sLaneCand[k], 2)) fail($sformatf("%s lane %0d candidate '%s'", when, k, cells(r, b + 1, 2)));
      if (cells(r, b + 4, 5) != state_word(dut.sLaneState[k])) fail($sformatf("%s lane %0d state '%s'", when, k, cells(r, b + 4, 5)));
      if (cells(r, b + 10, 4) != act_word(dut.sLaneAct[k])) fail($sformatf("%s lane %0d action '%s'", when, k, cells(r, b + 10, 4)));
      if (cells(r, b + 16, 3) != dec(dut.sLaneGates[k], 3)) fail($sformatf("%s lane %0d gates '%s'", when, k, cells(r, b + 16, 3)));
      if (cells(r + 1, b + 1, 8) != dec(dut.sLaneFit[k], 8)) fail($sformatf("%s lane %0d fitness '%s'", when, k, cells(r + 1, b + 1, 8)));
      if (cells(r + 1, b + 11, 4) != dec(dut.sLaneSteps[k], 4)) fail($sformatf("%s lane %0d steps '%s'", when, k, cells(r + 1, b + 11, 4)));
    end
    if (cells(0, 19, 4) != hex_text(dut.sRunId)) fail($sformatf("%s RUN ID '%s'", when, cells(0, 19, 4)));
    if (cells(0, 37, 3) != dec(dut.sGen, 3)) fail($sformatf("%s generation '%s'", when, cells(0, 37, 3)));
    if (cells(0, 52, 1) != dec(dut.sBatch + 1, 1)) fail($sformatf("%s batch '%s'", when, cells(0, 52, 1)));
    if (dut.sWorld < 2 && cells(1, 39, 2) != (dut.sWorld == 0 ? "A " : "B "))
      fail($sformatf("%s world '%s'", when, cells(1, 39, 2)));
    if (dut.sWorld >= 2 && dut.sWorld < 6 && cells(1, 39, 2) != $sformatf("V%0d", dut.sWorld - 1))
      fail($sformatf("%s world '%s'", when, cells(1, 39, 2)));
    if (cells(1, 48, 4) != hex_text(dut.sSeed)) fail($sformatf("%s seed '%s'", when, cells(1, 48, 4)));
    if (cells(2, 45, 4) != dec(dut.sPlaySteps, 4)) fail($sformatf("%s play step '%s'", when, cells(2, 45, 4)));
    if (cells(2, 8, 6) != "MEDIUM" || cells(2, 15, 1) != "2") fail($sformatf("%s config '%s %s'", when, cells(2, 8, 6), cells(2, 15, 1)));
    // LEDs follow the live lanes, HEX5..3 the generation
    if (ledr[8:1] != dut.trainAlive) fail($sformatf("%s LEDR %b, alive %b", when, ledr[8:1], dut.trainAlive));
    if (dut.hexHigh != {4'(dut.sGen / 100), 4'((dut.sGen / 10) % 10), 4'(dut.sGen % 10)}) fail($sformatf("%s HEX5..3", when));
  endtask

  initial begin
    int dead, alive;
    string lanes;
    repeat (5) @(posedge clk);
    resetN = 1'b1;
    wait_frames(2);

    press(KEY_DOWN);                         // TRAIN AI
    press(KEY_ENTER);
    press(KEY_DOWN);                         // MEDIUM
    press(KEY_ENTER);
    press(KEY_DOWN);                         // 2 corals
    press(KEY_ENTER);
    if (!dut.trainScreen || !dut.trainer.active) fail("training did not start");
    if (dut.simLevel != 3'd2) fail("simulation speed is not x4 after reset");

    for (int f = 0; f < 3; f++) check_frame($sformatf("x4 frame %0d", f));
    force dut.simLevel = 3'd7;
    for (int f = 0; f < 4; f++) check_frame($sformatf("MAX frame %0d", f));
    dead = 0; alive = 0; lanes = "";
    for (int k = 0; k < LANES; k++) begin
      if (dut.sLaneState[k] == LANE_DEAD) dead++;
      if (dut.sLaneState[k] == LANE_ALIVE) alive++;
      lanes = {lanes, $sformatf(" C%0d:%s", dut.sLaneCand[k], state_word(dut.sLaneState[k]))};
    end
    $display("INFO: generation %0d batch %0d step %0d:%s", dut.sGen, dut.sBatch, dut.sPlaySteps, lanes);
    release dut.simLevel;

    // Numpad 4 on the training screen: simulation speed only
    begin
      logic [2:0] worldBefore;
      logic [2:0] screenBefore;
      worldBefore  = dut.speedLevel;
      screenBefore = dut.screen;
      key_event(KEY_PAD4, 0);
      wait_frames(14);
      key_event(KEY_PAD4, 1);
      if (dut.simLevel != 3'd3) fail($sformatf("Numpad 4 held for 14 frames: simulation level %0d", dut.simLevel));
      if (dut.speedLevel != worldBefore) fail("Numpad 4 changed the world speed during training");
      if (dut.screen != screenBefore) fail("the game menus reacted during training");
      if (cells(0, 61, 5) != "X16  ")
        fail($sformatf("SIM shows '%s' (cells %h %h %h, source %0d, page %0d)", cells(0, 61, 5),
                       dut.textScreens.charRam[61], dut.textScreens.charRam[62], dut.textScreens.charRam[63],
                       dut.uiSources[SRC_TR_SIM], dut.page));
    end
    check_frame("x16 frame");

    // KEY1: the pause menu; the lanes wait
    force dut.simLevel = 3'd7;
    wait (dut.trainer.ctrl.champExists && dut.trainer.lanes.running);
    press_key1();
    wait_frames(2);
    begin
      logic [11:0] stepBefore;
      if (dut.mode != 3'd5 || dut.page != PAGE_PAUSE) fail("KEY1 did not open the pause menu");
      if (cells(22, 32, 15) != "TRAINING PAUSED" || cells(25, 24, 8) != "> RESUME") fail("pause menu text wrong");
      stepBefore = dut.sPlaySteps;
      wait_frames(3);
      if (dut.sPlaySteps != stepBefore || dut.sRunState != RS_PAUSED) fail("the lanes moved while paused");
      if (cells(1, 22, 8) != "PAUSED  ") fail($sformatf("run state shown as '%s'", cells(1, 22, 8)));
    end
    press_key1();                            // KEY1 = resume
    wait_frames(2);
    if (dut.mode != 3'd4 || dut.page != PAGE_TRAIN) fail("KEY1 did not resume");

    // Enter: pause menu, KEEP THE BEST: final test, TRAINING COMPLETE, the completion sound
    press(KEY_ENTER);
    press(KEY_DOWN);
    press(KEY_ENTER);
    wait (dut.trainComplete);
    fork
      begin : sound_watch
        wait (dut.sound.playingScore);
      end
      begin
        wait_frames(20);
        fail("no completion sound");
      end
    join_any
    disable fork;
    wait_frames(2);
    if (dut.mode != 3'd6 || dut.page != PAGE_DONE || !dut.aiCommitted) fail("no TRAINING COMPLETE page with a committed champion");
    if (cells(7, 38, 8) != "STOPPED ") fail($sformatf("result shown as '%s'", cells(7, 38, 8)));
    if (cells(9, 10, 4) != hex_text(dut.sRunId)) fail("DONE page RUN ID wrong");
    if (cells(14, 36, 1) != dec(dut.sTestW, 1)) fail("DONE page test worlds wrong");
    if (cells(22, 24, 10) != "> WATCH AI") fail($sformatf("DONE cursor shown as '%s'", cells(22, 24, 10)));
    $display("INFO: stopped at generation %0d: final test %0d gates, %0d/8 worlds; DONE page shown",
             dut.sGen, dut.sTestScore >> 16, dut.sTestW);
    // KEY1 = MAIN MENU; the AI is kept and named on the mode menu
    press_key1();
    wait_frames(2);
    if (dut.mode != 3'd0 || dut.trainer.active || dut.trainer.lanes.running) fail("KEY1 did not leave TRAINING COMPLETE");
    if (dut.page != PAGE_MODE) fail("mode menu not shown after KEY1");
    if (!dut.aiCommitted) fail("the committed AI was lost when leaving");
    if (cells(21, 22, 9) != {"RUN  ", hex_text(dut.aiRunId)}) fail($sformatf("mode menu AI line '%s'", cells(21, 22, 9)));
    release dut.simLevel;

    $display("INFO: %0d frames of training text checked", frames);
    if (errors == 0) $display("PASS: tb_train_screen");
    else             $display("FAIL: tb_train_screen (%0d errors)", errors);
    $finish;
  end

endmodule
