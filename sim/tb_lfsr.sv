// Checks lfsr_rng: full period of 65535 steps, never zero, seeding (a zero
// seed is replaced), and roughly balanced bits.
`timescale 1ns / 1ps

module tb_lfsr;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic        step = 1'b0, seedLoad = 1'b0;
  logic [15:0] seed = '0;
  logic [15:0] rnd;

  lfsr_rng dut (.clk(clk), .resetN(resetN), .step(step), .seedLoad(seedLoad), .seed(seed), .rnd(rnd));

  int errors = 0;

  initial begin
    logic [15:0] first;
    int period, ones [16];
    bit seen [65536];

    repeat (2) @(negedge clk);
    resetN = 1'b1;
    @(negedge clk);
    first = rnd;
    foreach (seen[i]) seen[i] = 0;
    step = 1'b1;
    period = 0;
    do begin
      @(negedge clk);
      period++;
      if (rnd == 16'h0000) begin errors++; $display("FAIL: LFSR reached zero"); break; end
      if (seen[rnd] && rnd != first) begin errors++; $display("FAIL: state repeated early"); break; end
      seen[rnd] = 1;
      for (int b = 0; b < 16; b++) ones[b] += rnd[b];
    end while (rnd != first && period < 70000);
    step = 1'b0;
    if (period != 65535) begin errors++; $display("FAIL: period %0d, expected 65535", period); end
    for (int b = 0; b < 16; b++)
      if (ones[b] < 32700 || ones[b] > 32836) begin errors++; $display("FAIL: bit %0d set %0d times", b, ones[b]); end

    seed = 16'h1234;
    seedLoad = 1'b1;
    @(negedge clk);
    seedLoad = 1'b0;
    if (rnd != 16'h1234) begin errors++; $display("FAIL: seed not loaded"); end
    seed = 16'h0000;
    seedLoad = 1'b1;
    @(negedge clk);
    seedLoad = 1'b0;
    if (rnd == 16'h0000) begin errors++; $display("FAIL: zero seed accepted"); end

    $display("INFO: period %0d steps", period);
    if (errors == 0) $display("PASS: tb_lfsr");
    else             $display("FAIL: tb_lfsr (%0d errors)", errors);
    $finish;
  end

endmodule
