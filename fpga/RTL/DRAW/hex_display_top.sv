// Drives the six seven-segment displays through the supplied SEG7 decoder.
// digits[0] -> HEX0 ... digits[5] -> HEX5; digitOn[i] = 0 blanks that display.

module hex_display_top (
    input  logic            clk,
    input  logic            resetN,
    input  logic [5:0][3:0] digits,
    input  logic [5:0]      digitOn,
    output logic [6:0]      HEX0,
    output logic [6:0]      HEX1,
    output logic [6:0]      HEX2,
    output logic [6:0]      HEX3,
    output logic [6:0]      HEX4,
    output logic [6:0]      HEX5
);

  SEG7 seg0 (.clk(clk), .resetN(resetN), .iDIG(digits[0]), .darkN(digitOn[0]), .oSEG(HEX0));
  SEG7 seg1 (.clk(clk), .resetN(resetN), .iDIG(digits[1]), .darkN(digitOn[1]), .oSEG(HEX1));
  SEG7 seg2 (.clk(clk), .resetN(resetN), .iDIG(digits[2]), .darkN(digitOn[2]), .oSEG(HEX2));
  SEG7 seg3 (.clk(clk), .resetN(resetN), .iDIG(digits[3]), .darkN(digitOn[3]), .oSEG(HEX3));
  SEG7 seg4 (.clk(clk), .resetN(resetN), .iDIG(digits[4]), .darkN(digitOn[4]), .oSEG(HEX4));
  SEG7 seg5 (.clk(clk), .resetN(resetN), .iDIG(digits[5]), .darkN(digitOn[5]), .oSEG(HEX5));

endmodule
