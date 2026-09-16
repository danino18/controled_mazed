// Current and best score, both kept as 3 BCD digits so the seven-segment
// decoders and the text renderer can use them without any conversion.
// The best score survives restarts and menus; only a reset clears it.

module score_bcd (
    input  logic            clk,
    input  logic            resetN,
    input  logic            clearScore,   // a new round starts
    input  logic            addPoint,     // one coral column passed
    input  logic            commitBest,   // the round ended
    output logic [2:0][3:0] score,
    output logic [2:0][3:0] best,
    output logic            newBest       // the last round beat the best score
);

  bcd_counter #(.DIGITS(3)) current (
      .clk      (clk),
      .resetN   (resetN),
      .clear    (clearScore),
      .increment(addPoint),
      .digits   (score),
      .saturated()
  );

  // BCD digits compare correctly as one binary number because every digit is 0..9.
  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      best    <= '0;
      newBest <= 1'b0;
    end else if (clearScore) begin
      newBest <= 1'b0;
    end else if (commitBest && (score > best)) begin
      best    <= score;
      newBest <= 1'b1;
    end
  end

endmodule
