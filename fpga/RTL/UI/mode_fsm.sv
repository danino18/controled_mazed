// Top-level mode selection: HUMAN PLAY, TRAIN AI, WATCH AI.
//
//   MODE_MENU --HUMAN--> GAME (keyboard steers; game_fsm menus, play, game over)
//             --TRAIN--> SETUP (game_fsm menus choose the world) --Enter--> TRAIN
//             --WATCH--> GAME with the AI steering, or NO_AI if no network exists
//   NO_AI     --TRAIN AI--> SETUP,  --MAIN MENU--> MODE_MENU
//   GAME      --MAIN MENU on GAME OVER, or KEY1--> MODE_MENU
//   SETUP     --KEY1--> MODE_MENU
//   TRAIN     --Enter or KEY1--> MODE_MENU   (training engine: M10)
//
// The key pulses given to this module are the raw ones; game_system routes the
// same keys to game_fsm only while gameKeys is high, so one press is never
// used twice (the routing is decided by the registered mode).

module mode_fsm
  import game_state_pkg::*, ui_pkg::*;
(
    input  logic       clk,
    input  logic       resetN,
    input  logic       upPulse,
    input  logic       downPulse,
    input  logic       enterPulse,
    input  logic       backPulse,     // KEY1
    input  logic       debugSw,       // SW1: AI debug overlay
    input  logic       watchValid,    // a network is available for WATCH AI
    input  logic [2:0] screen,        // game_fsm state
    input  logic       menuStart,     // game_fsm returned to its first menu
    input  logic       trainStart,    // game_fsm: world chosen for training
    output logic [2:0] mode,
    output logic [1:0] cursor,        // selected entry of the MODE / NO_AI menu
    output logic       aiMode,        // the AI steers the game
    output logic       trainMode,     // game_fsm's menus choose the training world
    output logic       gameKeys,      // keys reach game_fsm and the maze
    output logic       gameVisible,   // coral, game text and panels are drawn
    output logic       abortGame,     // one clock: game_fsm back to its first menu
    output logic [2:0] page           // char_screen page
);

  localparam logic [2:0] MD_MODE_MENU = 3'd0;
  localparam logic [2:0] MD_NO_AI     = 3'd1;
  localparam logic [2:0] MD_GAME      = 3'd2;
  localparam logic [2:0] MD_SETUP     = 3'd3;
  localparam logic [2:0] MD_TRAIN     = 3'd4;

  localparam logic [1:0] ITEM_HUMAN = 2'd0;
  localparam logic [1:0] ITEM_TRAIN = 2'd1;
  localparam logic [1:0] ITEM_WATCH = 2'd2;

  logic [1:0] cursorMax;
  logic       gameMenu;

  assign cursorMax = (mode == MD_NO_AI) ? 2'd1 : 2'd2;
  assign gameMenu  = (screen == ST_MENU_DIFF) || (screen == ST_MENU_OBST);

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      mode      <= MD_MODE_MENU;
      cursor    <= ITEM_HUMAN;
      aiMode    <= 1'b0;
      abortGame <= 1'b0;
    end else begin
      abortGame <= 1'b0;

      if (mode == MD_MODE_MENU || mode == MD_NO_AI) begin
        if (upPulse && cursor != 2'd0)             cursor <= cursor - 2'd1;
        else if (downPulse && cursor != cursorMax) cursor <= cursor + 2'd1;
      end

      case (mode)
        MD_MODE_MENU: begin
          if (enterPulse) begin
            case (cursor)
              ITEM_HUMAN: begin
                aiMode <= 1'b0;
                mode   <= MD_GAME;
              end
              ITEM_TRAIN: begin
                aiMode <= 1'b0;
                mode   <= MD_SETUP;
              end
              default: begin
                if (watchValid) begin
                  aiMode <= 1'b1;
                  mode   <= MD_GAME;
                end else begin
                  cursor <= 2'd0;
                  mode   <= MD_NO_AI;
                end
              end
            endcase
          end
        end

        MD_NO_AI: begin
          if (backPulse) begin
            cursor <= ITEM_WATCH;
            mode   <= MD_MODE_MENU;
          end else if (enterPulse) begin
            if (cursor == 2'd0) begin
              mode <= MD_SETUP;
            end else begin
              cursor <= ITEM_WATCH;
              mode   <= MD_MODE_MENU;
            end
          end
        end

        MD_GAME: begin
          if (backPulse) begin
            abortGame <= 1'b1;
            aiMode    <= 1'b0;
            cursor    <= aiMode ? ITEM_WATCH : ITEM_HUMAN;
            mode      <= MD_MODE_MENU;
          end else if (menuStart) begin     // MAIN MENU chosen on GAME OVER
            aiMode <= 1'b0;
            cursor <= aiMode ? ITEM_WATCH : ITEM_HUMAN;
            mode   <= MD_MODE_MENU;
          end
        end

        MD_SETUP: begin
          if (backPulse) begin
            abortGame <= 1'b1;
            cursor    <= ITEM_TRAIN;
            mode      <= MD_MODE_MENU;
          end else if (trainStart) begin
            mode <= MD_TRAIN;
          end
        end

        MD_TRAIN: begin
          if (backPulse || enterPulse) begin
            cursor <= ITEM_TRAIN;
            mode   <= MD_MODE_MENU;
          end
        end

        default: mode <= MD_MODE_MENU;
      endcase
    end
  end

  assign trainMode   = (mode == MD_SETUP);
  assign gameKeys    = (mode == MD_GAME) || (mode == MD_SETUP);
  assign gameVisible = (mode == MD_GAME) || (mode == MD_SETUP);

  always_comb begin
    case (mode)
      MD_MODE_MENU: page = PAGE_MODE;
      MD_NO_AI:     page = PAGE_NOAI;
      MD_SETUP:     page = PAGE_SETUP;
      MD_TRAIN:     page = PAGE_TRAINSTUB;
      default:      page = (aiMode && !gameMenu) ? (debugSw ? PAGE_WATCHDBG : PAGE_WATCH) : PAGE_NONE;
    endcase
  end

endmodule
