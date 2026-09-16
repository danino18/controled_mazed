// The eight best (score, candidate) pairs seen since the last clear, best
// first. An insertion takes one clock; on equal scores the entry stored first
// stays ahead, so the list equals a stable sort of the insertion order.

module top8_list
  import ml_pkg::*;
(
    input  logic                         clk,
    input  logic                         resetN,
    input  logic                         clear,
    input  logic                         insert,
    input  logic [FIT_W-1:0]             score,
    input  logic [CAND_W-1:0]            id,
    output logic [7:0][FIT_W-1:0]        scores,
    output logic [7:0][CAND_W-1:0]       ids,
    output logic [7:0]                   valid
);

  // position of the new entry = number of valid entries that are at least as good
  logic [7:0] ahead;
  logic [3:0] pos;

  always_comb begin
    for (int i = 0; i < 8; i++) ahead[i] = valid[i] && scores[i] >= score;
    pos = '0;
    for (int i = 0; i < 8; i++) pos = pos + 4'(ahead[i]);
  end

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      scores <= '0;
      ids    <= '0;
      valid  <= '0;
    end else if (clear) begin
      valid <= '0;
    end else if (insert && pos < 4'd8) begin
      for (int i = 0; i < 8; i++) begin
        if (i == int'(pos)) begin
          scores[i] <= score;
          ids[i]    <= id;
          valid[i]  <= 1'b1;
        end else if (i > int'(pos)) begin      // i >= 1 here: shift down
          scores[i] <= scores[(i + 7) % 8];
          ids[i]    <= ids[(i + 7) % 8];
          valid[i]  <= valid[(i + 7) % 8];
        end
      end
    end
  end

endmodule
