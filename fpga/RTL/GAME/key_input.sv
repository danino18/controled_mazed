// Decodes the game's keys from the keyboard's {keyCode, make, break} stream
// with the supplied singleKeyDecoder:
//   Arrow Up 9'h175, Arrow Down 9'h172, Enter 9'h05A, keypad Enter 9'h15A.
// Held levels drive the maze; one-clock press pulses drive the menus
// (PS/2 auto-repeat keeps a key "pressed" and does not create new pulses).

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

  logic mainEnterPulse, padEnterPulse;

  singleKeyDecoder #(.KEY_VALUE(9'h175)) arrowUp (
      .clk(clk), .resetN(resetN), .keyCode(keyCode), .make(keyMake), .brakee(keyBreak),
      .keyLatch(), .keyRisingEdgePulse(upPulse), .keyIsPressed(upHeld));

  singleKeyDecoder #(.KEY_VALUE(9'h172)) arrowDown (
      .clk(clk), .resetN(resetN), .keyCode(keyCode), .make(keyMake), .brakee(keyBreak),
      .keyLatch(), .keyRisingEdgePulse(downPulse), .keyIsPressed(downHeld));

  singleKeyDecoder #(.KEY_VALUE(9'h05A)) mainEnter (
      .clk(clk), .resetN(resetN), .keyCode(keyCode), .make(keyMake), .brakee(keyBreak),
      .keyLatch(), .keyRisingEdgePulse(mainEnterPulse), .keyIsPressed());

  singleKeyDecoder #(.KEY_VALUE(9'h15A)) padEnter (
      .clk(clk), .resetN(resetN), .keyCode(keyCode), .make(keyMake), .brakee(keyBreak),
      .keyLatch(), .keyRisingEdgePulse(padEnterPulse), .keyIsPressed());

  assign enterPulse = mainEnterPulse || padEnterPulse;

endmodule
