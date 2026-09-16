// Marks which BCD digits to show so that leading zeros are blanked.
// The ones digit (digits[0]) is always shown.

module leading_zero_blank #(
    parameter int DIGITS = 3
) (
    input  logic [DIGITS-1:0][3:0] digits,
    output logic [DIGITS-1:0]      digitOn
);

  logic [DIGITS:0] higherNonZero;   // any digit above position i is non-zero

  assign higherNonZero[DIGITS] = 1'b0;

  genvar i;
  generate
    for (i = 0; i < DIGITS; i++) begin : digit
      assign higherNonZero[i] = higherNonZero[i+1] || (digits[i] != 4'd0);
      if (i == 0) begin : ones
        assign digitOn[i] = 1'b1;
      end else begin : upper
        assign digitOn[i] = higherNonZero[i];
      end
    end
  endgenerate

endmodule
