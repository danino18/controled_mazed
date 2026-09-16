// Fixed-point neural network: nn_sched + nn_datapath against an integer
// reference model written independently from the RTL.
//
//   - every 8x8 signed product (65,536 cases)
//   - hard-tanh saturation and truncation at the boundaries
//   - evaluation length: the action updates NN_GENES + 2 clocks after start
//   - 20,000 random networks and inputs, including extreme weights:
//     action, output sum and all hidden outputs, plus the accumulator bound
//   - the hand-set demo network (RTL/MIF/nn_demo.mif) at its decision edges
//   - enable = 0 freezes the unit, clear returns the action to HOLD
`timescale 1ns / 1ps

module tb_nn;
  import ml_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  // weight memory: registered address, unregistered output (like the M10K RAMs)
  logic [7:0] genes [NN_GENES];
  logic [GENE_ADDR_W-1:0] geneAddr, addrReg;
  logic [7:0] gene;

  always @(posedge clk) addrReg <= geneAddr;
  assign gene = (addrReg < NN_GENES) ? genes[addrReg] : 8'hXX;

  logic                      start = 1'b0;
  logic                      opLoad, opAdd, latchH, decide, busy;
  logic [3:0]                inSel;
  logic [2:0]                hIdx;
  logic                      enable = 1'b1, clear = 1'b0;
  logic [NN_INPUTS-1:0][7:0] feat;
  logic [1:0]                act;
  logic signed [ACC_W-1:0]   y;
  logic [NN_HIDDEN-1:0][7:0] hidden;

  // direct control for the multiply and saturation tests
  logic                      manual = 1'b0;
  logic                      mLoad = 1'b0, mAdd = 1'b0, mLatch = 1'b0;
  logic [3:0]                mSel = '0;
  logic [7:0]                mGene = '0;

  nn_sched sched (
      .clk(clk), .resetN(resetN), .start(start), .geneAddr(geneAddr),
      .opLoad(opLoad), .opAdd(opAdd), .inSel(inSel), .latchH(latchH), .hIdx(hIdx),
      .decide(decide), .busy(busy));

  nn_datapath dut (
      .clk(clk), .resetN(resetN), .enable(enable), .clear(clear),
      .gene(manual ? mGene : gene), .feat(feat),
      .opLoad(manual ? mLoad : opLoad), .opAdd(manual ? mAdd : opAdd),
      .inSel(manual ? mSel : inSel), .latchH(manual ? mLatch : latchH),
      .hIdx(manual ? 3'd0 : hIdx), .decide(manual ? 1'b0 : decide),
      .act(act), .y(y), .hidden(hidden));

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 20) $display("FAIL: %s", msg);
  endtask

  // ---------------------------------------------------------------- reference model
  function automatic int s8(input logic [7:0] v);
    return int'($signed(v));
  endfunction

  int refH [NN_HIDDEN];
  int refY;
  int refAct;
  int maxAbsAcc = 0;

  function automatic void reference(input logic [7:0] g [NN_GENES], input logic [NN_INPUTS-1:0][7:0] f);
    int a, t;
    for (int j = 0; j < NN_HIDDEN; j++) begin
      a = s8(g[5 * j]) * 64;
      for (int i = 0; i < NN_INPUTS; i++) a += s8(f[i]) * s8(g[5 * j + 1 + i]);
      if ((a < 0 ? -a : a) > maxAbsAcc) maxAbsAcc = (a < 0 ? -a : a);
      t = (a >= 0) ? a / 32 : -((-a + 31) / 32);      // floor(a / 32)
      refH[j] = (t > 64) ? 64 : (t < -64) ? -64 : t;
    end
    a = s8(g[30]) * 64;
    for (int j = 0; j < NN_HIDDEN; j++) a += refH[j] * s8(g[31 + j]);
    if ((a < 0 ? -a : a) > maxAbsAcc) maxAbsAcc = (a < 0 ? -a : a);
    refY   = a;
    refAct = (a > 512) ? 2 : (a < -512) ? 1 : 0;
  endfunction

  task automatic evaluate(output int clocksToDecide);
    int n;
    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    n = 1;
    while (!decide) begin
      @(negedge clk);
      n++;
    end
    @(negedge clk);          // act/y registered on the decide clock
    clocksToDecide = n;
  endtask

  task automatic check_against_reference(input string what);
    reference(genes, feat);
    if (int'(act) != refAct) fail($sformatf("%s: action %0d, expected %0d (y %0d)", what, act, refAct, refY));
    if (int'(y) != refY)     fail($sformatf("%s: output sum %0d, expected %0d", what, y, refY));
    for (int j = 0; j < NN_HIDDEN; j++)
      if (s8(hidden[j]) != refH[j]) fail($sformatf("%s: h%0d = %0d, expected %0d", what, j, s8(hidden[j]), refH[j]));
  endtask

  // ---------------------------------------------------------------- manual datapath steps
  task automatic step(input logic load, input logic add, input logic latch, input logic [3:0] sel, input logic [7:0] g);
    @(negedge clk);
    mLoad = load; mAdd = add; mLatch = latch; mSel = sel; mGene = g;
    @(negedge clk);
    mLoad = 0; mAdd = 0; mLatch = 0;
  endtask

  // Build an accumulator value from a bias and one product, then latch h0.
  task automatic check_squash(input int bias, input int f0, input int w0);
    int a, t, expect_h;
    a = bias * 64 + f0 * w0;
    t = (a >= 0) ? a / 32 : -((-a + 31) / 32);
    expect_h = (t > 64) ? 64 : (t < -64) ? -64 : t;
    feat[0] = 8'(f0);
    step(1, 0, 0, 4'd0, 8'(bias));
    step(0, 1, 0, 4'd0, 8'(w0));
    step(0, 0, 1, 4'd0, 8'd0);
    if (s8(hidden[0]) != expect_h)
      fail($sformatf("hard-tanh of %0d: h = %0d, expected %0d", a, s8(hidden[0]), expect_h));
  endtask

  initial begin
    int clocks;
    int seed;
    int ups, downs, holds;
    seed = 1;

    feat = '0;
    for (int g = 0; g < NN_GENES; g++) genes[g] = 8'd0;
    repeat (3) @(negedge clk);
    resetN = 1'b1;

    // ---- every product: acc = 0 (bias 0), add f * w, check through y = acc via decide
    manual = 1'b1;
    for (int a = -128; a < 128; a++) begin
      for (int b = -128; b < 128; b++) begin
        feat[1] = 8'(a);
        @(negedge clk);
        mLoad = 1; mAdd = 0; mGene = 8'd0;
        @(negedge clk);
        mLoad = 0; mAdd = 1; mSel = 4'd1; mGene = 8'(b);
        @(negedge clk);
        mAdd = 0;
        if (int'(dut.acc) != a * b) begin
          fail($sformatf("product %0d * %0d = %0d", a, b, int'(dut.acc)));
        end
      end
    end
    $display("INFO: all 65,536 products checked");

    // ---- hard-tanh boundaries (h = floor(acc / 32), clamped to +-64)
    check_squash(0, 64, 32);       // acc 2048 -> 64
    check_squash(0, 65, 32);       // 2080 -> 65 -> 64
    check_squash(1, 64, 32);       // 2112 -> 66 -> 64
    check_squash(0, -64, 32);      // -2048 -> -64
    check_squash(0, -65, 32);      // -2080 -> -65 -> -64
    check_squash(0, 1, 31);        // 31 -> 0
    check_squash(0, -1, 1);        // -1 -> -1 (truncation toward minus infinity)
    check_squash(0, -1, 32);       // -32 -> -1
    check_squash(0, -1, 33);       // -33 -> -2
    check_squash(127, 127, 127);   // largest positive
    check_squash(-128, -128, 127); // most negative
    manual = 1'b0;

    // ---- evaluation length
    evaluate(clocks);
    if (clocks != NN_GENES + 2) fail($sformatf("the action updated %0d clocks after start, expected %0d", clocks, NN_GENES + 2));
    if (busy) fail("still busy after the evaluation");

    // ---- random networks (every 8th uses only extreme values)
    ups = 0; downs = 0; holds = 0;
    for (int n = 0; n < 20000; n++) begin
      for (int g = 0; g < NN_GENES; g++) begin
        genes[g] = 8'($urandom(seed));
        seed = seed + 1;
        if (n % 8 == 0) genes[g] = genes[g][0] ? 8'h80 : 8'h7F;
        else if (n % 8 == 1) genes[g] = 8'($signed(genes[g]) >>> 3);   // small weights
      end
      for (int i = 0; i < NN_INPUTS; i++) begin
        feat[i] = 8'($urandom(seed));
        seed = seed + 1;
        if (n % 8 == 0) feat[i] = feat[i][0] ? 8'h80 : 8'h7F;
      end
      evaluate(clocks);
      check_against_reference($sformatf("network %0d", n));
      case (act)
        ACT_UP:   ups++;
        ACT_DOWN: downs++;
        default:  holds++;
      endcase
    end
    $display("INFO: 20,000 random networks: %0d UP, %0d DOWN, %0d HOLD; largest |sum| %0d (limit %0d)",
             ups, downs, holds, maxAbsAcc, (1 << (ACC_W - 1)) - 1);
    if (maxAbsAcc >= (1 << (ACC_W - 1))) fail("accumulator range exceeded");
    if (maxAbsAcc < 60000) fail("extreme networks did not reach the expected sum range");
    if (holds == 0 || ups == 0 || downs == 0) fail("not every action occurred");

    // ---- demo network: UP when e_next + 4 * v_rel (px) is clearly positive
    $readmemh("RTL/MIF/nn_demo.hex", genes);
    feat = '0;
    feat[0] = 8'd9;   evaluate(clocks); if (act != ACT_UP)   fail("demo: e_next = 18 px should be UP");
    feat[0] = 8'd8;   evaluate(clocks); if (act != ACT_HOLD) fail("demo: e_next = 16 px should be HOLD");
    feat[0] = -8'd8;  evaluate(clocks); if (act != ACT_HOLD) fail("demo: e_next = -16 px should be HOLD");
    feat[0] = -8'd9;  evaluate(clocks); if (act != ACT_DOWN) fail("demo: e_next = -18 px should be DOWN");
    feat[0] = 8'd40; feat[2] = -8'd64;   // 80 px below, maze already moving up at 4 px/frame
    evaluate(clocks); if (act != ACT_UP) fail("demo: far error with damping should still be UP");
    feat[0] = 8'd16; feat[2] = -8'd64;   // 32 px below, closing fast: stop early
    evaluate(clocks); if (act != ACT_HOLD) fail("demo: damping should release the key");
    feat = '0;
    for (int n = 0; n < 200; n++) begin
      for (int i = 0; i < NN_INPUTS; i++) feat[i] = 8'($urandom(seed));
      seed = seed + 1;
      evaluate(clocks);
      check_against_reference("demo network");
    end

    // ---- enable and clear
    feat[0] = 8'd100; feat[2] = 8'd0;
    evaluate(clocks);
    if (act != ACT_UP) fail("setup for the freeze test");
    enable = 1'b0;
    feat[0] = -8'd100;
    evaluate(clocks);
    if (act != ACT_UP) fail("a disabled unit changed its action");
    enable = 1'b1;
    evaluate(clocks);
    if (act != ACT_DOWN) fail("re-enabled unit did not update");
    @(negedge clk);
    clear = 1'b1;
    @(negedge clk);
    clear = 1'b0;
    if (act != ACT_HOLD) fail("clear did not return the action to HOLD");

    if (errors == 0) $display("PASS: tb_nn");
    else             $display("FAIL: tb_nn (%0d errors)", errors);
    $finish;
  end

endmodule
