// Random numbers of the genetic algorithm: 32-bit xorshift (13, 17, 5),
// period 2^32 - 1. Seeded from the RUN ID and separate from the world seeds,
// so the choice of training worlds never depends on the evolution.

module xorshift32 (
    input  logic        clk,
    input  logic        resetN,
    input  logic        load,
    input  logic [15:0] runId,
    input  logic        step,
    output logic [31:0] rnd
);

  function automatic logic [31:0] next(input logic [31:0] s);
    logic [31:0] x;
    x = s;
    x = x ^ (x << 13);
    x = x ^ (x >> 17);
    x = x ^ (x << 5);
    return x;
  endfunction

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN)   rnd <= 32'h2545_F491;
    else if (load) rnd <= {runId, ~runId} ^ 32'h9E37_79B9;    // never 0: the two halves differ
    else if (step) rnd <= next(rnd);
  end

endmodule
