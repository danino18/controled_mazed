// Horizontal motion of the coral columns and their random opening centres
// (logic only). Everything here is independent of the player: the maze offset
// is applied afterwards by gap_place. This is why several on-chip training
// lanes can share one column_track and still see exactly the world a single
// player would see.
//
// Active columns are spaced CORAL_WRAP_W / count apart and re-enter on the
// right after leaving on the left, each time with a new random opening.

module column_track
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
    input  logic [15:0]                         rnd,
    output logic [NUM_COLUMNS-1:0]              active,
    output logic [NUM_COLUMNS-1:0][10:0]        colX,         // left edge of the art (signed)
    output logic [NUM_COLUMNS-1:0][8:0]         gapBase,      // opening centre before the maze offset
    output logic                                passPulse     // one column passed the bird
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
      logic [8:0]         base;
      logic               passed;
      logic [6:0]         rndBits;
      int                 xPx;

      assign active[i]  = (i < columnCount);
      assign nextXFx    = xFx - 19'(worldStep);
      assign rndBits    = 7'({rnd, rnd} >> (i * 5));
      assign xPx        = int'(xFx >>> FIXED_SHIFT);
      assign colX[i]    = 11'(xPx);
      assign gapBase[i] = base;

      // The column counts once its collision core is entirely left of the bird's hitbox.
      assign passedNow[i] = tickCheck && run && active[i] && !passed &&
                            (xPx + CORAL_W - CORAL_CORE_INSET <= BIRD_X + BIRD_HB_X0);

      always_ff @(posedge clk or negedge resetN) begin
        if (!resetN) begin
          xFx    <= 19'(FIRST_X * FX);
          base   <= 9'(GAP_BASE_MIN);
          passed <= 1'b0;
        end else if (restart) begin
          xFx    <= 19'((FIRST_X + i * int'(spacing)) * FX);
          base   <= 9'(GAP_BASE_MIN) + 9'(rndBits);
          passed <= 1'b0;
        end else begin
          if (tickMove && run) begin
            if (nextXFx < LEFT_LIMIT_FX) begin
              xFx    <= nextXFx + 19'(WRAP_FX);
              base   <= 9'(GAP_BASE_MIN) + 9'(rndBits);
              passed <= 1'b0;
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
    if (!resetN) passPulse <= 1'b0;
    else         passPulse <= |passedNow;
  end

endmodule
