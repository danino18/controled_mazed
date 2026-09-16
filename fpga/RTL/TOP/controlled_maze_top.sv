// Controlled Maze - board top level (DE10-Standard).
// Board-specific parts only: PLL, reset synchroniser, codec tie-offs.
// The game itself is in game_system.

module controlled_maze_top (
    input  logic        CLOCK_50,
    input  logic        resetN_pin,     // KEY[0], active low
    output logic [9:0]  LEDR,
    output logic [6:0]  HEX0,
    output logic [6:0]  HEX1,
    output logic [6:0]  HEX2,
    output logic [6:0]  HEX3,
    output logic [6:0]  HEX4,
    output logic [6:0]  HEX5,
    output logic [28:0] OVGA,
    output logic        AUD_XCK,        // audio codec master clock
    output logic        AUD_DACDAT      // audio codec DAC serial data
);

  // No audio yet. The WM8731 codec keeps its register settings when the FPGA is
  // reprogrammed, so its clock and data inputs are held low instead of floating.
  assign AUD_XCK    = 1'b0;
  assign AUD_DACDAT = 1'b0;

  // ---------------------------------------------------------------- clock / reset
  // As in the supplied demo, KEY[0] also resets the PLL; logic stays in reset until it relocks.
  logic clk;
  logic pllLocked;
  logic resetN;
  logic [9:0] gameLeds;

  CLK_31P5 pll (
      .refclk  (CLOCK_50),
      .rst     (~resetN_pin),
      .outclk_0(clk),
      .locked  (pllLocked)
  );

  reset_sync resetSync (
      .clk        (clk),
      .asyncResetN(resetN_pin & pllLocked),
      .resetN     (resetN)
  );

  game_system game (
      .clk   (clk),
      .resetN(resetN),
      .OVGA  (OVGA),
      .HEX0  (HEX0),
      .HEX1  (HEX1),
      .HEX2  (HEX2),
      .HEX3  (HEX3),
      .HEX4  (HEX4),
      .HEX5  (HEX5),
      .LEDR  (gameLeds)
  );

  assign LEDR = {gameLeds[9:1], pllLocked};

endmodule
