// 16-bit Galois LFSR (x^16 + x^14 + x^13 + x^11 + 1), period 65535.
//
// Each step pulse advances the register STEPS_PER_TICK shifts at once
// ("leap-forward"), so every frame sees 16 fresh bits instead of the previous
// value shifted by one. 16 and 65535 share no factor, so the period is still
// 65535 steps. A round replays identically for the same seed.

module lfsr_rng #(
    parameter int STEPS_PER_TICK = 16
) (
    input  logic        clk,
    input  logic        resetN,
    input  logic        step,
    input  logic        seedLoad,
    input  logic [15:0] seed,
    output logic [15:0] rnd
);

  localparam logic [15:0] TAPS = 16'hB400;
  localparam logic [15:0] RESET_SEED = 16'hACE1;

  function automatic logic [15:0] advance(input logic [15:0] state);
    logic [15:0] v;
    v = state;
    for (int k = 0; k < STEPS_PER_TICK; k++)
      v = (v >> 1) ^ (v[0] ? TAPS : 16'h0000);
    return v;
  endfunction

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      rnd <= RESET_SEED;
    end else if (seedLoad) begin
      rnd <= (seed == 16'h0000) ? RESET_SEED : seed;   // the all-zero state would lock up
    end else if (step) begin
      rnd <= advance(rnd);
    end
  end

endmodule
