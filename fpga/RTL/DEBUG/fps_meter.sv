// Debug: counts startOfFrame pulses over one second and holds the result in BCD.
// Used to measure the real VGA frame rate on the board.

module fps_meter #(
    parameter int CLOCKS_PER_SECOND = 31_500_000
) (
    input  logic            clk,
    input  logic            resetN,
    input  logic            startOfFrame,
    output logic [2:0][3:0] fpsBcd
);

  int unsigned     tickCount;
  logic            secondTick;
  logic [2:0][3:0] framesThisSecond;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      tickCount  <= 0;
      secondTick <= 1'b0;
    end else begin
      secondTick <= 1'b0;
      if (tickCount == CLOCKS_PER_SECOND - 1) begin
        tickCount  <= 0;
        secondTick <= 1'b1;
      end else begin
        tickCount <= tickCount + 1;
      end
    end
  end

  bcd_counter #(.DIGITS(3)) frameCounter (
      .clk      (clk),
      .resetN   (resetN),
      .clear    (secondTick),
      .increment(startOfFrame),
      .digits   (framesThisSecond),
      .saturated()
  );

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      fpsBcd <= '0;
    end else if (secondTick) begin
      fpsBcd <= framesThisSecond;
    end
  end

endmodule
