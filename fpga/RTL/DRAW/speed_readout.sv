// Draws the world-speed level (0..7) as a single digit in the top-left
// corner during READY/PLAY/HIT -- a small, testing-only readout so holding
// Numpad 4/6 can be confirmed visually.
//
// Deliberately a standalone module with its own tiny font ROM read, instead
// of one more text_pkg line: adding a 23rd entry to line_cfg's case statement
// crashes Quartus 17's Verific elaborator (confirmed empirically -- 22
// entries synthesizes cleanly, 23 does not). One extra small ROM read port
// is a far cheaper price than fighting that tool limit. Latency: 3 clocks,
// matching every other drawing layer.

module speed_readout
  import palette_pkg::*, game_state_pkg::*;
(
    input  logic        clk,
    input  logic        resetN,
    input  logic [10:0] pixelX,
    input  logic [10:0] pixelY,
    input  logic [2:0]  screen,
    input  logic [2:0]  speedLevel,   // 0..7
    output logic        drawingRequest,
    output color_t      RGBout
);

  localparam int X0 = 8;
  localparam int Y0 = 8;

  logic inCell;
  logic shown;
  logic [2:0] glyphX, glyphY;

  assign shown  = (screen == ST_READY) || (screen == ST_PLAY) || (screen == ST_HIT);
  assign inCell = shown && pixelX >= X0 && pixelX < X0 + 8 && pixelY >= Y0 && pixelY < Y0 + 8;
  assign glyphX = pixelX[2:0];
  assign glyphY = pixelY[2:0];

  logic        valid1;
  logic [11:0] address;   // {code - 0x20, glyphY, glyphX}, matching font.mif's layout

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      valid1  <= 1'b0;
      address <= '0;
    end else begin
      valid1  <= inCell;
      address <= {6'((8'h30 + 8'(speedLevel)) - 8'h20), glyphY, glyphX};
    end
  end

  logic ink;

  lpm_rom #(
      .lpm_width             (1),
      .lpm_widthad           (12),
      .lpm_numwords          (4096),
      .lpm_file              ("RTL/MIF/font.mif"),
      .lpm_type              ("LPM_ROM"),
      .lpm_address_control   ("REGISTERED"),
      .lpm_outdata           ("UNREGISTERED"),
      .intended_device_family("Cyclone V")
  ) rom (
      .address(address),
      .inclock(clk),
      .q      (ink)
  );

  logic valid2;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      valid2 <= 1'b0;
      RGBout <= TRANSPARENT;
    end else begin
      valid2 <= valid1;
      RGBout <= (valid2 && ink) ? C_TEXT_DIM : TRANSPARENT;
    end
  end

  assign drawingRequest = (RGBout != TRANSPARENT);

endmodule
