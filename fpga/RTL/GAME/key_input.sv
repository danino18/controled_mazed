// Decodes the game's keys from the keyboard's {keyCode, make, break} stream
// with the supplied singleKeyDecoder:
//   Arrow Up 9'h175 or Numpad 8 9'h075, Arrow Down 9'h172 or Numpad 2 9'h072,
//   Enter 9'h05A, keypad Enter 9'h15A.
// Held levels drive the maze; one-clock press pulses drive the menus
// (PS/2 auto-repeat keeps a key "pressed" and does not create new pulses).
//
// Numpad 8/2/Enter are the primary controls: the only keyboard on this board
// is a standalone numeric keypad. Arrow Up/Down and main Enter are kept too,
// in case a full keyboard is used instead; both sources are simply OR'd.

module key_input (
    input  logic       clk,
    input  logic       resetN,
    input  logic [8:0] keyCode,
    input  logic       keyMake,
    input  logic       keyBreak,
    output logic       upHeld,
    output logic       downHeld,
    output logic       upPulse,
    output logic       downPulse,
    output logic       enterPulse
);

  logic arrowUpHeld, arrowUpPulse, pad8Held, pad8Pulse;
  logic arrowDownHeld, arrowDownPulse, pad2Held, pad2Pulse;
  logic mainEnterPulse, padEnterPulse;

  singleKeyDecoder #(.KEY_VALUE(9'h175)) arrowUp (
      .clk(clk), .resetN(resetN), .keyCode(keyCode), .make(keyMake), .brakee(keyBreak),
      .keyLatch(), .keyRisingEdgePulse(arrowUpPulse), .keyIsPressed(arrowUpHeld));

  singleKeyDecoder #(.KEY_VALUE(9'h075)) numpad8 (
      .clk(clk), .resetN(resetN), .keyCode(keyCode), .make(keyMake), .brakee(keyBreak),
      .keyLatch(), .keyRisingEdgePulse(pad8Pulse), .keyIsPressed(pad8Held));

  singleKeyDecoder #(.KEY_VALUE(9'h172)) arrowDown (
      .clk(clk), .resetN(resetN), .keyCode(keyCode), .make(keyMake), .brakee(keyBreak),
      .keyLatch(), .keyRisingEdgePulse(arrowDownPulse), .keyIsPressed(arrowDownHeld));

  singleKeyDecoder #(.KEY_VALUE(9'h072)) numpad2 (
      .clk(clk), .resetN(resetN), .keyCode(keyCode), .make(keyMake), .brakee(keyBreak),
      .keyLatch(), .keyRisingEdgePulse(pad2Pulse), .keyIsPressed(pad2Held));

  singleKeyDecoder #(.KEY_VALUE(9'h05A)) mainEnter (
      .clk(clk), .resetN(resetN), .keyCode(keyCode), .make(keyMake), .brakee(keyBreak),
      .keyLatch(), .keyRisingEdgePulse(mainEnterPulse), .keyIsPressed());

  singleKeyDecoder #(.KEY_VALUE(9'h15A)) padEnter (
      .clk(clk), .resetN(resetN), .keyCode(keyCode), .make(keyMake), .brakee(keyBreak),
      .keyLatch(), .keyRisingEdgePulse(padEnterPulse), .keyIsPressed());

  assign upHeld     = arrowUpHeld   || pad8Held;
  assign downHeld   = arrowDownHeld || pad2Held;
  assign upPulse    = arrowUpPulse  || pad8Pulse;
  assign downPulse  = arrowDownPulse|| pad2Pulse;
  assign enterPulse = mainEnterPulse || padEnterPulse;

endmodule
