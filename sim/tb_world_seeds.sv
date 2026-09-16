// World seeds (decision D3) and the simulation-speed throttle.
//
// world_seeds:
//   - every training seed has bit 15 = 0 and is never 0
//   - no seed repeats within 32,767 draws (the full period), so certainly not
//     within 255 generations x 2 worlds; the period is exactly 32,767
//   - the same RUN ID gives the same sequence; different RUN IDs give different
//     sequences; RUN ID 0 still gives a valid sequence
//   - A_g != B_g and A_g != A_{g+1} for 255 generations
// fixed seeds (ml_pkg): 4 validation + 8 test seeds, all with bit 15 = 1, all different
// sim_throttle: the interval between step starts is exactly sim_period(level)
// for every level (MAX: back to back), including a step that takes longer.
`timescale 1ns / 1ps

module tb_world_seeds;
  import ml_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic        load = 1'b0, draw = 1'b0;
  logic [15:0] runId = '0;
  logic [15:0] seed;

  world_seeds dut (.clk(clk), .resetN(resetN), .load(load), .runId(runId), .draw(draw), .seed(seed));

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 20) $display("FAIL: %s", msg);
  endtask

  task automatic start(input logic [15:0] id);
    @(negedge clk);
    runId = id;
    load  = 1'b1;
    @(negedge clk);
    load  = 1'b0;
  endtask

  task automatic next(output logic [15:0] s);
    @(negedge clk);
    draw = 1'b1;
    @(negedge clk);
    draw = 1'b0;
    s = seed;
  endtask

  // ---------------------------------------------------------------- throttle
  logic [2:0] level = 3'd0;
  logic       stepGo, stepTaken;
  int         busyFor = 0;

  sim_throttle throttle (.clk(clk), .resetN(resetN), .level(level), .stepTaken(stepTaken), .stepGo(stepGo));

  // a simulator that starts a step whenever allowed and stays busy busyLen clocks
  int busyLen = 48;
  assign stepTaken = stepGo && busyFor == 0;
  always @(posedge clk) begin
    if (stepTaken)        busyFor <= busyLen;
    else if (busyFor > 0) busyFor <= busyFor - 1;
  end

  initial begin
    logic [15:0] s, a, b, prevA;
    logic [15:0] firstRun [16];
    bit          seen [logic [15:0]];
    int          period;

    repeat (3) @(negedge clk);
    resetN = 1'b1;

    // ---- full period and no repeats
    start(16'h3F2C);
    for (int i = 0; i < 16; i++) begin
      next(s);
      firstRun[i] = s;
    end
    start(16'h3F2C);
    period = 0;
    seen.delete();
    for (int i = 0; i < 32767; i++) begin
      next(s);
      if (i < 16 && s != firstRun[i]) fail($sformatf("RUN ID 3F2C draw %0d: %04h, first time %04h", i, s, firstRun[i]));
      if (s[15]) fail($sformatf("training seed %04h has bit 15 set", s));
      if (s == 16'h0000) fail("training seed 0");
      if (seen.exists(s)) fail($sformatf("seed %04h repeated after %0d draws", s, i));
      seen[s] = 1;
    end
    next(s);
    if (s != firstRun[0]) fail($sformatf("period is not 32,767 (draw 32,768 = %04h)", s));
    else $display("INFO: 32,767 different training seeds, then the sequence repeats");

    // ---- generations: A_g, B_g
    start(16'h1234);
    prevA = 16'h0000;
    for (int g = 0; g < 255; g++) begin
      next(a);
      next(b);
      if (a == b) fail($sformatf("generation %0d: A = B = %04h", g, a));
      if (a == prevA) fail($sformatf("generation %0d: A repeats the previous A", g));
      prevA = a;
    end

    // ---- different RUN IDs, RUN ID 0
    begin
      int same;
      same = 0;
      start(16'h1235);
      for (int i = 0; i < 16; i++) begin
        next(s);
        if (s == firstRun[i]) same++;
      end
      if (same > 1) fail($sformatf("RUN IDs 3F2C and 1235 share %0d of 16 seeds", same));
      start(16'h0000);
      next(s);
      if (s == 16'h0000 || s[15]) fail($sformatf("RUN ID 0 gave seed %04h", s));
      start(16'h8000);          // bit 15 of the RUN ID only; the state must still be non-zero
      next(s);
      if (s == 16'h0000 || s[15]) fail($sformatf("RUN ID 8000 gave seed %04h", s));
    end

    // ---- fixed validation and test seeds
    for (int i = 0; i < 12; i++) begin
      logic [15:0] v;
      v = FIXED_SEEDS[16 * i +: 16];
      if (!v[15]) fail($sformatf("fixed seed %0d = %04h has bit 15 = 0", i, v));
      for (int j = 0; j < i; j++)
        if (FIXED_SEEDS[16 * j +: 16] == v) fail($sformatf("fixed seeds %0d and %0d are equal", i, j));
    end
    $display("INFO: V1..V4 = %04h %04h %04h %04h", FIXED_SEEDS[15:0], FIXED_SEEDS[31:16], FIXED_SEEDS[47:32], FIXED_SEEDS[63:48]);

    // ---- throttle
    for (int lv = 0; lv < 8; lv++) begin
      int last, gapMin, gapMax, n, t;
      level = 3'(lv);
      repeat (2) @(posedge clk iff stepTaken);
      last = -1; gapMin = 1 << 30; gapMax = 0; n = 0; t = 0;
      while (n < ((lv < 3) ? 3 : 20)) begin
        @(posedge clk);
        t++;
        if (stepTaken) begin
          if (last >= 0) begin
            if (t - last < gapMin) gapMin = t - last;
            if (t - last > gapMax) gapMax = t - last;
            n++;
          end
          last = t;
        end
      end
      if (lv == 7) begin
        if (gapMin != busyLen + 1 || gapMax != busyLen + 1) fail($sformatf("MAX: steps %0d..%0d clocks apart", gapMin, gapMax));
      end else if (gapMin != int'(sim_period(3'(lv))) || gapMax != int'(sim_period(3'(lv))))
        fail($sformatf("level %0d: steps %0d..%0d clocks apart, expected %0d", lv, gapMin, gapMax, sim_period(3'(lv))));
      $display("INFO: sim level %0d: a step every %0d clocks (%0d steps/s)", lv, gapMin, 31500000 / gapMin);
    end
    // a step longer than the period does not lose the credit
    level = 3'd6;          // 424 clocks
    busyLen = 600;
    repeat (2) @(posedge clk iff stepTaken);
    begin
      int t;
      t = 0;
      @(posedge clk);
      while (!stepTaken) begin
        @(posedge clk);
        t++;
      end
      if (t != busyLen) fail($sformatf("after a long step the next one started %0d clocks later", t + 1));
    end

    if (errors == 0) $display("PASS: tb_world_seeds");
    else             $display("FAIL: tb_world_seeds (%0d errors)", errors);
    $finish;
  end

endmodule
