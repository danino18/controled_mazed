// Checks score_bcd: counting, clearing, best-score update rules and newBest.
`timescale 1ns / 1ps

module tb_score;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic            clearScore = 1'b0, addPoint = 1'b0, commitBest = 1'b0;
  logic [2:0][3:0] score, best;
  logic            newBest;

  score_bcd dut (
      .clk(clk), .resetN(resetN), .clearScore(clearScore), .addPoint(addPoint),
      .commitBest(commitBest), .score(score), .best(best), .newBest(newBest));

  int errors = 0;

  function automatic int dec(input logic [2:0][3:0] d);
    return d[2] * 100 + d[1] * 10 + d[0];
  endfunction

  task automatic pulse(ref logic sig);
    @(negedge clk);
    sig = 1'b1;
    @(negedge clk);
    sig = 1'b0;
  endtask

  task automatic round(input int points, input int expBest, input bit expNew);
    pulse(clearScore);
    if (dec(score) != 0 || newBest) begin
      errors++;
      $display("FAIL: clear left score=%0d newBest=%b", dec(score), newBest);
    end
    repeat (points) pulse(addPoint);
    pulse(commitBest);
    if (dec(score) != points || dec(best) != expBest || newBest != expNew) begin
      errors++;
      $display("FAIL: round of %0d: score=%0d best=%0d newBest=%b, expected best=%0d newBest=%b",
               points, dec(score), dec(best), newBest, expBest, expNew);
    end
  endtask

  initial begin
    repeat (2) @(negedge clk);
    resetN = 1'b1;
    round(12, 12, 1);     // first round sets the best
    round(7, 12, 0);      // worse round keeps it
    round(12, 12, 0);     // equal is not a new best
    round(37, 37, 1);
    round(0, 37, 0);
    round(109, 109, 1);   // carries through tens and hundreds
    // a reset clears everything
    resetN = 1'b0;
    @(negedge clk);
    resetN = 1'b1;
    if (dec(best) != 0 || dec(score) != 0) begin
      errors++;
      $display("FAIL: reset did not clear the scores");
    end

    if (errors == 0) $display("PASS: tb_score");
    else             $display("FAIL: tb_score (%0d errors)", errors);
    $finish;
  end

endmodule
