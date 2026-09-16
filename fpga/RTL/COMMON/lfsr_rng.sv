// 16-bit Galois LFSR (x^16 + x^14 + x^13 + x^11 + 1), period 65535.
// Advances once per step pulse, so a round replays identically for the same seed.

module lfsr_rng (
    input  logic        clk,
    input  logic        resetN,
    input  logic        step,
    input  logic        seedLoad,
    input  logic [15:0] seed,
    output logic [15:0] rnd
);

  localparam logic [15:0] TAPS = 16'hB400;
  localparam logic [15:0] RESET_SEED = 16'hACE1;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      rnd <= RESET_SEED;
    end else if (seedLoad) begin
      rnd <= (seed == 16'h0000) ? RESET_SEED : seed;   // the all-zero state would lock up
    end else if (step) begin
      rnd <= (rnd >> 1) ^ (rnd[0] ? TAPS : 16'h0000);
    end
  end

endmodule
