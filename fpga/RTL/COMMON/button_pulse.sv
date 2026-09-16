// A board push button (active low, bouncing) as a one-clock press pulse:
// two-flop synchroniser, then the level must stay the same for STABLE_CLOCKS
// before it is accepted (about 20 ms at 31.5 MHz), then a pulse on the press.

module button_pulse #(
    parameter int STABLE_CLOCKS = 630_000
) (
    input  logic clk,
    input  logic resetN,
    input  logic buttonN,     // raw pin, 0 = pressed
    output logic pressed,     // debounced level
    output logic pulse        // one clock when the button goes down
);

  localparam int CW = $clog2(STABLE_CLOCKS + 1);

  logic          sync1, sync2;
  logic          candidate;
  logic [CW-1:0] count;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      sync1     <= 1'b0;
      sync2     <= 1'b0;
      candidate <= 1'b0;
      count     <= '0;
      pressed   <= 1'b0;
      pulse     <= 1'b0;
    end else begin
      sync1 <= !buttonN;
      sync2 <= sync1;
      pulse <= 1'b0;
      if (sync2 != candidate) begin
        candidate <= sync2;
        count     <= '0;
      end else if (candidate != pressed) begin
        if (count == CW'(STABLE_CLOCKS - 1)) begin
          pressed <= candidate;
          pulse   <= candidate;
        end else begin
          count <= count + 1'b1;
        end
      end
    end
  end

endmodule
