// Checks bcd_counter against an integer model over its full range, and
// leading_zero_blank for every counter value.
`timescale 1ns / 1ps

module tb_bcd;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic            clear = 1'b0;
  logic            increment = 1'b0;
  logic [2:0][3:0] digits;
  logic            saturated;
  logic [2:0]      digitOn;

  bcd_counter #(.DIGITS(3)) dut (
      .clk(clk), .resetN(resetN), .clear(clear), .increment(increment),
      .digits(digits), .saturated(saturated));

  leading_zero_blank #(.DIGITS(3)) blank (.digits(digits), .digitOn(digitOn));

  int errors = 0;

  function automatic int as_int(input logic [2:0][3:0] d);
    return d[2] * 100 + d[1] * 10 + d[0];
  endfunction

  task automatic check_value(input int expected);
    logic [2:0] expectedOn;
    expectedOn[0] = 1'b1;
    expectedOn[1] = (expected >= 10);
    expectedOn[2] = (expected >= 100);
    if (as_int(digits) !== expected || digits[0] > 9 || digits[1] > 9 || digits[2] > 9) begin
      errors++;
      $display("FAIL: counter %0h, expected %0d", digits, expected);
    end
    if (digitOn !== expectedOn) begin
      errors++;
      $display("FAIL: value %0d digitOn %b, expected %b", expected, digitOn, expectedOn);
    end
    if (saturated !== (expected == 999)) begin
      errors++;
      $display("FAIL: value %0d saturated=%b", expected, saturated);
    end
  endtask

  initial begin
    repeat (2) @(posedge clk);
    resetN = 1'b1;
    @(negedge clk);
    check_value(0);

    for (int n = 1; n <= 1005; n++) begin
      increment = 1'b1;
      @(negedge clk);
      check_value(n > 999 ? 999 : n);
    end
    increment = 1'b0;

    // clear has priority over increment
    clear = 1'b1;
    increment = 1'b1;
    @(negedge clk);
    check_value(0);
    clear = 1'b0;
    increment = 1'b0;
    @(negedge clk);
    check_value(0);

    if (errors == 0) $display("PASS: tb_bcd");
    else             $display("FAIL: tb_bcd (%0d errors)", errors);
    $finish;
  end

endmodule
