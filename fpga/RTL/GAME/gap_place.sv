// Places each column's opening: random centre plus the player's shared maze
// offset, clamped so the opening stays on screen. Purely combinational; this
// is the only part of the coral state that depends on the player.

module gap_place
  import game_params_pkg::*;
(
    input  logic [NUM_COLUMNS-1:0][8:0]  gapBase,     // opening centre before the offset
    input  logic signed [9:0]            mazeOffset,  // pixels, shared by all columns
    output logic [NUM_COLUMNS-1:0][9:0]  gapTop,      // first row of the opening
    output logic [NUM_COLUMNS-1:0][9:0]  gapBottom    // first row below the opening
);

  genvar i;
  generate
    for (i = 0; i < NUM_COLUMNS; i++) begin : column
      int centre;

      always_comb begin
        centre = int'(gapBase[i]) + int'(mazeOffset);
        if (centre < GAP_CENTER_MIN) centre = GAP_CENTER_MIN;
        if (centre > GAP_CENTER_MAX) centre = GAP_CENTER_MAX;
      end

      assign gapTop[i]    = 10'(centre - GAP_H / 2);
      assign gapBottom[i] = 10'(centre + GAP_H / 2);
    end
  endgenerate

endmodule
