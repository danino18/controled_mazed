// Player-adjustable world/coral scroll speed (Numpad 4 = faster, Numpad 6 =
// slower). Bounded to the same 8-level, 0.5 px/frame range the original
// switch-based design (M9) planned: 1.0..4.5 px/frame, so level 0 is never
// zero/negative and level 7 stays within the maze's own control authority
// (MAZE_STEP_MAX >= 4.5 px/frame is not required here -- the player, not the
// world, sets the pace; see DESIGN.md).
//
// While exactly one of speedUpHeld/speedDownHeld is asserted, the level moves
// by one step every STEP_FRAMES frames (a plain step, not an accelerating
// ramp, since "progressively/incrementally" only asks for one speed change at
// a time). Holding both, or neither, freezes the level where it is; releasing
// leaves it exactly where it was, with no decay. The level is not reset
// between rounds or menus, only by resetN, so a chosen pace persists like any
// other session setting.

module world_speed_control
  import game_params_pkg::*;
(
    input  logic       clk,
    input  logic       resetN,
    input  logic       tick,          // once per frame
    input  logic       speedUpHeld,
    input  logic       speedDownHeld,
    input  logic       load,          // set the level directly (WATCH AI: the trained speed)
    input  logic [2:0] loadLevel,
    output logic [2:0] speedLevel,    // 0..7, for the on-screen readout
    output logic [11:0] worldStep     // 1/64 px per frame, feeds obstacle_manager
);

  logic [3:0] holdFrames;
  logic       exactlyOne;

  assign exactlyOne = speedUpHeld ^ speedDownHeld;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      speedLevel <= 3'(WORLD_SPEED_LEVEL_RESET);
      holdFrames <= '0;
    end else if (load) begin
      speedLevel <= loadLevel;
      holdFrames <= '0;
    end else if (tick) begin
      if (exactlyOne) begin
        if (holdFrames >= 4'(WORLD_SPEED_STEP_FRAMES - 1)) begin
          holdFrames <= '0;
          if (speedUpHeld && speedLevel < 3'(WORLD_SPEED_LEVEL_MAX))
            speedLevel <= speedLevel + 3'd1;
          else if (speedDownHeld && speedLevel > 3'(WORLD_SPEED_LEVEL_MIN))
            speedLevel <= speedLevel - 3'd1;
        end else begin
          holdFrames <= holdFrames + 4'd1;
        end
      end else begin
        holdFrames <= '0;   // neither, or both: no change; next single hold starts a fresh step
      end
    end
  end

  assign worldStep = 12'(WORLD_STEP_BASE) + 12'(WORLD_STEP_INCREMENT) * 12'(speedLevel);

endmodule
