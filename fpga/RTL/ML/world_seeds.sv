// Training world seeds (decision D3): a dedicated 15-bit maximal LFSR
// (x^15 + x^14 + 1), seeded from the RUN ID. Every draw advances it 15 steps,
// so all 15 bits are replaced, and a draw is a training seed {1'b0, state}.
// The period is 32,767 draws (15 and 32,767 share no factor), so no training
// world repeats within a run, and bit 15 = 0 keeps every training seed apart
// from the fixed validation and test seeds (bit 15 = 1, ml_pkg).
//
// This generator is separate from the genetic algorithm's random numbers, so
// the sequence of training worlds depends only on the RUN ID.

module world_seeds (
    input  logic        clk,
    input  logic        resetN,
    input  logic        load,       // start a run's sequence
    input  logic [15:0] runId,
    input  logic        draw,       // one clock: next seed
    output logic [15:0] seed        // the last drawn seed
);

  logic [14:0] state;

  function automatic logic [14:0] advance(input logic [14:0] s);
    logic [14:0] v;
    v = s;
    for (int k = 0; k < 15; k++) v = {v[13:0], v[14] ^ v[13]};
    return v;
  endfunction

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      state <= 15'h0001;
      seed  <= '0;
    end else if (load) begin
      state <= (runId[14:0] == 15'd0) ? {runId[15], 14'h2A5B} : runId[14:0];   // never all zero
      seed  <= '0;
    end else if (draw) begin
      state <= advance(state);
      seed  <= {1'b0, advance(state)};
    end
  end

endmodule
