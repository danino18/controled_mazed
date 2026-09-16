// Asynchronous-assert, synchronous-release reset for one clock domain.

module reset_sync (
    input  logic clk,
    input  logic asyncResetN,
    output logic resetN
);

  logic stage1;

  always_ff @(posedge clk or negedge asyncResetN) begin
    if (!asyncResetN) begin
      stage1 <= 1'b0;
      resetN <= 1'b0;
    end else begin
      stage1 <= 1'b1;
      resetN <= stage1;
    end
  end

endmodule
