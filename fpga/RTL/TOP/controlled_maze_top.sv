// Controlled Maze - board top level (DE10-Standard).
// Board-specific parts only: PLL, reset synchroniser, precompiled keyboard
// block, precompiled audio codec block.
// The game itself, including the audio sample generator, is in game_system.

module controlled_maze_top (
    input  logic        CLOCK_50,
    input  logic        resetN_pin,     // KEY[0], active low
    input  logic        PS2_CLK,
    input  logic        PS2_DAT,
    input  logic        SW0,            // global mute (audio only)
    output logic [9:0]  LEDR,
    output logic [6:0]  HEX0,
    output logic [6:0]  HEX1,
    output logic [6:0]  HEX2,
    output logic [6:0]  HEX3,
    output logic [6:0]  HEX4,
    output logic [6:0]  HEX5,
    output logic [28:0] OVGA,
    // audio codec (WM8731-class): the codec is the I2S clock master, so
    // ADCLRCK/BCLK are inputs here; I2C_SCLK/SDAT configure the codec into
    // playback mode and must always be wired (unconfigured = silent codec).
    input  logic        AUD_ADCLRCK,
    input  logic        AUD_BCLK,
    output logic        AUD_DACDAT,
    output logic        AUD_XCK,
    output logic        AUD_I2C_SCLK,
    inout  logic        AUD_I2C_SDAT
);

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

  logic [8:0] keyCode;
  logic       keyMake;
  logic       keyBreak;

  kbd_wrapper keyboard (
      .clk    (clk),
      .resetN (resetN),
      .PS2_CLK(PS2_CLK),
      .PS2_DAT(PS2_DAT),
      .keyCode(keyCode),
      .make   (keyMake),
      .brakk  (keyBreak)
  );

  logic [15:0] audioSample;

  game_system game (
      .clk        (clk),
      .resetN     (resetN),
      .keyCode    (keyCode),
      .keyMake    (keyMake),
      .keyBreak   (keyBreak),
      .muteSw     (SW0),
      .OVGA       (OVGA),
      .HEX0       (HEX0),
      .HEX1       (HEX1),
      .HEX2       (HEX2),
      .HEX3       (HEX3),
      .HEX4       (HEX4),
      .HEX5       (HEX5),
      .LEDR       (gameLeds),
      .audioSample(audioSample)
  );

  // The same mono sample drives both channels (the supplied demo does the same).
  audio_codec_controller codec (
      .CLOCK31_5    (clk),
      .resetN       (resetN),
      .AUD_ADCLRCK  (AUD_ADCLRCK),
      .AUD_BCLK     (AUD_BCLK),
      .dacdata_left (audioSample),
      .dacdata_right(audioSample),
      .AUD_DACDAT   (AUD_DACDAT),
      .AUD_XCK      (AUD_XCK),
      .AUD_I2C_SCLK (AUD_I2C_SCLK),
      .adcdata_left (),
      .adcdata_right(),
      .AUD_I2C_SDAT (AUD_I2C_SDAT)
  );

  assign LEDR = {gameLeds[9:1], pllLocked};

endmodule
