// Geometric collision between the bird's hitbox and every active coral column.
// Uses rectangles only, independent of the artwork, and works without a
// raster scan so the same module can later drive a headless simulator.

module collision_detect
  import game_params_pkg::*;
(
    input  logic                         clk,
    input  logic                         resetN,
    input  logic                         tickCheck,
    input  logic signed [10:0]           birdY,
    input  logic [NUM_COLUMNS-1:0]       active,
    input  logic [NUM_COLUMNS-1:0][10:0] colX,
    input  logic [NUM_COLUMNS-1:0][9:0]  gapTop,
    input  logic [NUM_COLUMNS-1:0][9:0]  gapBottom,
    output logic                         collision,   // updated on tickCheck
    output logic [NUM_COLUMNS-1:0]       hitColumn
);

  localparam int HB_LEFT  = BIRD_X + BIRD_HB_X0;
  localparam int HB_RIGHT = BIRD_X + BIRD_HB_X1;

  int hbTop;
  int hbBottom;
  logic [NUM_COLUMNS-1:0] hit;

  assign hbTop    = int'(birdY) + BIRD_HB_Y0;
  assign hbBottom = int'(birdY) + BIRD_HB_Y1;

  genvar i;
  generate
    for (i = 0; i < NUM_COLUMNS; i++) begin : column
      int  coreLeft, coreRight, safeTop, safeBottom;
      logic xOverlap, yOutside;

      assign coreLeft   = int'($signed(colX[i])) + CORAL_CORE_INSET;
      assign coreRight  = int'($signed(colX[i])) + CORAL_W - 1 - CORAL_CORE_INSET;
      assign safeTop    = int'(gapTop[i]) - CORAL_TIP_FORGIVE;      // rows above this are coral
      assign safeBottom = int'(gapBottom[i]) + CORAL_TIP_FORGIVE;   // rows from here down are coral
      assign xOverlap   = (HB_RIGHT >= coreLeft) && (HB_LEFT <= coreRight);
      assign yOutside   = (hbTop < safeTop) || (hbBottom >= safeBottom);
      assign hit[i]     = active[i] && xOverlap && yOutside;
    end
  endgenerate

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      collision <= 1'b0;
      hitColumn <= '0;
    end else if (tickCheck) begin
      collision <= |hit;
      hitColumn <= hit;
    end
  end

endmodule
