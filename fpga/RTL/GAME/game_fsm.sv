// Top-level game state machine.
//
//   MENU_DIFF --Enter--> MENU_OBST --Enter--> READY --timer--> PLAY
//       ^                                       ^                |
//       |                                       |            collision
//       +---- Enter on MAIN MENU ---- GAME_OVER +--Enter on      v
//                                        ^       RESTART        HIT
//                                        +-------- timer --------+
//
// Menus: Up/Down move the cursor (clamped), Enter confirms. Entering a menu
// puts the cursor on the previous choice. GAME_OVER ignores Enter for a short
// moment so a key pressed during the crash cannot skip the score screen.
// Timed states count frames (tick = one pulse per frame).
//
// Additions for the AI modes (M9):
//   trainMode  Enter on the obstacle menu only records the training world
//              (pulse trainStart) and returns to the first menu.
//   autoStart  from the first menu, start a round with the given settings
//              (WATCH AI); taken on a tick, so the round always starts at the
//              same point of a frame.
//   abort      back to the first menu from any screen (KEY1).

module game_fsm
  import game_state_pkg::*;
#(
    parameter int READY_FRAMES     = 88,     // ~1.2 s of "GET READY"
    parameter int HIT_FRAMES       = 51,     // ~0.7 s freeze after a crash
    parameter int OVER_LOCK_FRAMES = 36      // ~0.5 s before GAME OVER accepts Enter
) (
    input  logic       clk,
    input  logic       resetN,
    input  logic       tick,
    input  logic       upPulse,
    input  logic       downPulse,
    input  logic       enterPulse,
    input  logic       collision,     // valid on tick
    input  logic       trainMode,
    input  logic       autoStart,
    input  logic [1:0] autoDifficulty,
    input  logic [1:0] autoColumns,   // 1..3
    input  logic       abort,
    output logic [2:0] state,
    output logic [1:0] difficulty,    // DIFF_EASY / DIFF_MEDIUM / DIFF_HARD
    output logic [1:0] columnCount,   // 1..3
    output logic [1:0] menuCursor,
    output logic [7:0] stateFrames,   // frames spent in the current state (saturates)
    output logic       roundStart,    // one clock: new round (reset world, bird, score)
    output logic       roundOver,     // one clock: the round ended in a crash
    output logic       menuStart,     // one clock: a menu screen was entered
    output logic       trainStart     // one clock: the training world was chosen
);

  logic [1:0] cursorMax;
  assign cursorMax = (state == ST_GAME_OVER) ? 2'd1 : 2'd2;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      state       <= ST_MENU_DIFF;
      difficulty  <= DIFF_EASY;
      columnCount <= 2'd1;
      menuCursor  <= 2'd0;
      stateFrames <= '0;
      roundStart  <= 1'b0;
      roundOver   <= 1'b0;
      menuStart   <= 1'b1;
      trainStart  <= 1'b0;
    end else begin
      roundStart <= 1'b0;
      roundOver  <= 1'b0;
      menuStart  <= 1'b0;
      trainStart <= 1'b0;

      if (tick && stateFrames != 8'hFF) stateFrames <= stateFrames + 8'd1;

      // cursor movement on menu screens
      if (state == ST_MENU_DIFF || state == ST_MENU_OBST || state == ST_GAME_OVER) begin
        if (upPulse && menuCursor != 2'd0)             menuCursor <= menuCursor - 2'd1;
        else if (downPulse && menuCursor != cursorMax) menuCursor <= menuCursor + 2'd1;
      end

      case (state)
        ST_MENU_DIFF: begin
          if (autoStart && tick) begin
            difficulty  <= autoDifficulty;
            columnCount <= autoColumns;
            roundStart  <= 1'b1;
            state       <= ST_READY;
            stateFrames <= '0;
          end else if (enterPulse) begin
            difficulty  <= menuCursor;
            menuCursor  <= columnCount - 2'd1;
            state       <= ST_MENU_OBST;
            stateFrames <= '0;
          end
        end

        ST_MENU_OBST: begin
          if (enterPulse) begin
            columnCount <= menuCursor + 2'd1;
            stateFrames <= '0;
            if (trainMode) begin
              trainStart <= 1'b1;
              menuCursor <= difficulty;
              state      <= ST_MENU_DIFF;
            end else begin
              roundStart <= 1'b1;
              state      <= ST_READY;
            end
          end
        end

        ST_READY: begin
          if (tick && stateFrames >= 8'(READY_FRAMES - 1)) begin
            state       <= ST_PLAY;
            stateFrames <= '0;
          end
        end

        ST_PLAY: begin
          if (tick && collision) begin
            roundOver   <= 1'b1;
            state       <= ST_HIT;
            stateFrames <= '0;
          end
        end

        ST_HIT: begin
          if (tick && stateFrames >= 8'(HIT_FRAMES - 1)) begin
            menuCursor  <= 2'd0;
            state       <= ST_GAME_OVER;
            stateFrames <= '0;
          end
        end

        ST_GAME_OVER: begin
          if (enterPulse && stateFrames >= 8'(OVER_LOCK_FRAMES)) begin
            stateFrames <= '0;
            if (menuCursor == 2'd0) begin        // RESTART, same settings
              roundStart <= 1'b1;
              state      <= ST_READY;
            end else begin                       // MAIN MENU
              menuCursor <= difficulty;
              menuStart  <= 1'b1;
              state      <= ST_MENU_DIFF;
            end
          end
        end

        default: begin
          state       <= ST_MENU_DIFF;
          menuCursor  <= 2'd0;
          stateFrames <= '0;
        end
      endcase

      if (abort) begin
        roundStart  <= 1'b0;
        roundOver   <= 1'b0;
        trainStart  <= 1'b0;
        menuStart   <= 1'b1;
        menuCursor  <= difficulty;
        state       <= ST_MENU_DIFF;
        stateFrames <= '0;
      end
    end
  end

endmodule
