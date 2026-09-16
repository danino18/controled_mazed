// State of the coral columns (logic only, no drawing).
//
// Each column has a horizontal position and a random opening centre. All
// columns share one vertical offset (mazeOffset), which is what the player
// controls, so they move up and down together. Active columns are spaced
// CORAL_WRAP_W / count apart and re-enter on the right after leaving on the left.

module obstacle_manager
  import game_params_pkg::*;
#(
    parameter int FIRST_X = CORAL_FIRST_X     // left edge of the first column when a round starts
) (
    input  logic                                clk,
    input  logic                                resetN,
    input  logic                                tickMove,
    input  logic                                tickCheck,
    input  logic                                run,          // world is moving
    input  logic                                restart,      // place the columns for a new round
    input  logic [1:0]                          columnCount,  // 1..3
    input  logic [11:0]                         worldStep,    // 1/64 px per frame
    input  logic signed [9:0]                   mazeOffset,   // pixels, shared by all columns
    input  logic [15:0]                         rnd,
    output logic [NUM_COLUMNS-1:0]              active,
    output logic [NUM_COLUMNS-1:0][10:0]        colX,         // left edge of the art (signed)
    output logic [NUM_COLUMNS-1:0][9:0]         gapTop,       // first row of the opening
    output logic [NUM_COLUMNS-1:0][9:0]         gapBottom,    // first row below the opening
    output logic                                scorePulse    // one column passed the bird
);

  localparam int FX = 1 << FIXED_SHIFT;
  localparam int LEFT_LIMIT_FX = -(CORAL_W * FX);   // column fully off screen
  localparam int WRAP_FX       = CORAL_WRAP_W * FX;

  // Spacing between neighbouring columns for the selected count.
  logic [9:0] spacing;
  always_comb begin
    case (columnCount)
      2'd3:    spacing = 10'(CORAL_WRAP_W / 3);
      2'd2:    spacing = 10'(CORAL_WRAP_W / 2);
      default: spacing = 10'(CORAL_WRAP_W);
    endcase
  end

  logic [NUM_COLUMNS-1:0] passedNow;

  genvar i;
  generate
    for (i = 0; i < NUM_COLUMNS; i++) begin : column
      logic signed [18:0] xFx;          // 1/64 px
      logic signed [18:0] nextXFx;
      logic [8:0]         gapBase;
      logic               passed;
      logic [6:0]         rndBits;
      int                 centre;
      int                 xPx;

      assign active[i] = (i < columnCount);
      assign nextXFx   = xFx - 19'(worldStep);
      assign rndBits   = 7'({rnd, rnd} >> (i * 5));
      assign xPx       = int'(xFx >>> FIXED_SHIFT);
      assign colX[i]   = 11'(xPx);

      always_comb begin
        centre = int'(gapBase) + int'(mazeOffset);
        if (centre < GAP_CENTER_MIN) centre = GAP_CENTER_MIN;
        if (centre > GAP_CENTER_MAX) centre = GAP_CENTER_MAX;
      end

      assign gapTop[i]    = 10'(centre - GAP_H / 2);
      assign gapBottom[i] = 10'(centre + GAP_H / 2);

      // The column counts once its collision core is entirely left of the bird's hitbox.
      assign passedNow[i] = tickCheck && run && active[i] && !passed &&
                            (xPx + CORAL_W - CORAL_CORE_INSET <= BIRD_X + BIRD_HB_X0);

      always_ff @(posedge clk or negedge resetN) begin
        if (!resetN) begin
          xFx     <= 19'(FIRST_X * FX);
          gapBase <= 9'(GAP_BASE_MIN);
          passed  <= 1'b0;
        end else if (restart) begin
          xFx     <= 19'((FIRST_X + i * int'(spacing)) * FX);
          gapBase <= 9'(GAP_BASE_MIN) + 9'(rndBits);
          passed  <= 1'b0;
        end else begin
          if (tickMove && run) begin
            if (nextXFx < LEFT_LIMIT_FX) begin
              xFx     <= nextXFx + 19'(WRAP_FX);
              gapBase <= 9'(GAP_BASE_MIN) + 9'(rndBits);
              passed  <= 1'b0;
            end else begin
              xFx <= nextXFx;
            end
          end
          if (passedNow[i]) passed <= 1'b1;
        end
      end
    end
  endgenerate

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) scorePulse <= 1'b0;
    else         scorePulse <= |passedNow;
  end

endmodule
