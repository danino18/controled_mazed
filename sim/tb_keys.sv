// Checks key_input with the keyCode/make/break stream the keyboard block
// produces: one press pulse per key press, held levels until release,
// auto-repeat ignored, and that Numpad 8/2 behave exactly like Arrow Up/Down
// (the board's only keyboard is a standalone numeric keypad), including when
// an arrow and its matching numpad key are held at the same time.
`timescale 1ns / 1ps

module tb_keys;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic [8:0] keyCode = '0;
  logic       keyMake = 1'b0;
  logic       keyBreak = 1'b0;
  logic       upHeld, downHeld, upPulse, downPulse, enterPulse;

  key_input dut (
      .clk(clk), .resetN(resetN), .keyCode(keyCode), .keyMake(keyMake), .keyBreak(keyBreak),
      .upHeld(upHeld), .downHeld(downHeld), .upPulse(upPulse), .downPulse(downPulse),
      .enterPulse(enterPulse));

  localparam logic [8:0] UP = 9'h175, DOWN = 9'h172, ENTER = 9'h05A, PAD_ENTER = 9'h15A;
  localparam logic [8:0] PAD_8 = 9'h075, PAD_2 = 9'h072, SPACE = 9'h029;

  int errors = 0;
  int upPulses = 0, downPulses = 0, enterPulses = 0;

  always @(posedge clk) begin
    if (upPulse) upPulses++;
    if (downPulse) downPulses++;
    if (enterPulse) enterPulses++;
  end

  task automatic fail(input string msg);
    errors++;
    $display("FAIL: %s", msg);
  endtask

  // byterec updates keyCode together with a one-clock make or break pulse
  task automatic send(input logic [8:0] code, input bit isBreak);
    @(negedge clk);
    keyCode = code;
    keyMake = !isBreak;
    keyBreak = isBreak;
    @(negedge clk);
    keyMake = 1'b0;
    keyBreak = 1'b0;
    repeat (20) @(negedge clk);
  endtask

  task automatic expect_counts(input int u, input int d, input int e, input string when);
    if (upPulses != u || downPulses != d || enterPulses != e)
      fail($sformatf("%s: pulses up=%0d down=%0d enter=%0d, expected %0d %0d %0d",
                     when, upPulses, downPulses, enterPulses, u, d, e));
  endtask

  initial begin
    repeat (3) @(negedge clk);
    resetN = 1'b1;
    repeat (3) @(negedge clk);

    // ---------------------------------------------------------------- Arrow Up/Down (unchanged)
    send(UP, 0);
    if (!upHeld || downHeld) fail("Up press not held");
    expect_counts(1, 0, 0, "after Up press");
    repeat (5) send(UP, 0);                         // auto-repeat
    expect_counts(1, 0, 0, "after Up auto-repeat");
    if (!upHeld) fail("Up released by auto-repeat");

    send(DOWN, 0);                                  // both held
    if (!upHeld || !downHeld) fail("Up and Down not both held");
    send(SPACE, 1);                                 // unrelated release
    if (!upHeld || !downHeld) fail("unrelated break released a key");
    send(UP, 1);
    if (upHeld || !downHeld) fail("Up break did not release only Up");
    send(DOWN, 1);
    if (downHeld) fail("Down break did not release Down");
    expect_counts(1, 1, 0, "after Down");

    // ---------------------------------------------------------------- Numpad 8/2 behave exactly like the arrows
    send(PAD_8, 0);
    if (!upHeld || downHeld) fail("Numpad 8 press not held as Up");
    expect_counts(2, 1, 0, "after Numpad 8 press");
    repeat (5) send(PAD_8, 0);                       // auto-repeat
    expect_counts(2, 1, 0, "after Numpad 8 auto-repeat");
    if (!upHeld) fail("Numpad 8 released by auto-repeat");
    send(PAD_8, 1);
    if (upHeld) fail("Numpad 8 break did not release Up");

    send(PAD_2, 0);
    if (upHeld || !downHeld) fail("Numpad 2 press not held as Down");
    expect_counts(2, 2, 0, "after Numpad 2 press");
    send(PAD_2, 1);
    if (downHeld) fail("Numpad 2 break did not release Down");

    // Arrow and its matching numpad key pressed one after another: each is a separate rising
    // edge on the OR'd signal, so each contributes its own pulse; both must release before upHeld drops.
    send(UP, 0);
    send(PAD_8, 0);
    expect_counts(4, 2, 0, "after Up and Numpad 8 both pressed (two separate pulses)");
    if (!upHeld) fail("Up+Numpad8: not held");
    send(UP, 1);
    if (!upHeld) fail("Up+Numpad8: released early when only Arrow Up broke");
    send(PAD_8, 1);
    if (upHeld) fail("Up+Numpad8: still held after both broke");

    // ---------------------------------------------------------------- Enter (unchanged)
    send(ENTER, 0);
    send(ENTER, 0);                                 // auto-repeat
    send(ENTER, 1);
    send(PAD_ENTER, 0);
    send(PAD_ENTER, 1);
    expect_counts(4, 2, 2, "after both Enter keys");

    send(UP, 0);                                    // a new press gives a new pulse
    send(UP, 1);
    expect_counts(5, 2, 2, "after second Up press");

    if (errors == 0) $display("PASS: tb_keys");
    else             $display("FAIL: tb_keys (%0d errors)", errors);
    $finish;
  end

endmodule
