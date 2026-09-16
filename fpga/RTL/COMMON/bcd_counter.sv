// Multi-digit BCD up-counter that saturates at all nines.
// digits[0] is the ones digit. clear has priority over increment.

module bcd_counter #(
    parameter int DIGITS = 3
) (
    input  logic                    clk,
    input  logic                    resetN,
    input  logic                    clear,
    input  logic                    increment,
    output logic [DIGITS-1:0][3:0]  digits,
    output logic                    saturated
);

  logic [DIGITS:0]           carry;
  logic [DIGITS-1:0][3:0]    nextDigits;
  logic [DIGITS-1:0]         isNine;

  assign carry[0] = 1'b1;

  genvar i;
  generate
    for (i = 0; i < DIGITS; i++) begin : digit
      assign isNine[i]     = (digits[i] == 4'd9);
      assign carry[i+1]    = carry[i] && isNine[i];
      assign nextDigits[i] = !carry[i] ? digits[i] :
                             isNine[i] ? 4'd0 : digits[i] + 4'd1;
    end
  endgenerate

  assign saturated = &isNine;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      digits <= '0;
    end else if (clear) begin
      digits <= '0;
    end else if (increment && !saturated) begin
      digits <= nextDigits;
    end
  end

endmodule
