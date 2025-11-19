// battleship_top.sv
`timescale 1ns / 1ps
module Battleship(
    input  wire        clk,           // main board clock (100 MHz typical on Basys3)
    input  wire        reset,         // synchronous reset (active high)
    // board control
    input  wire [3:0]  sel_row,       // 0..8 selected row
    input  wire [3:0]  sel_col,       // 0..8 selected column
    input  wire        place_pulse,   // pulse: place ship at sel coord (during placing_phase)
    input  wire        fire_pulse,    // pulse: fire at sel coord (during gameplay)
    input  wire        placing_phase, // 1 = currently placing ships, 0 = firing phase
    input  wire        active_player, // 0 = player1 is acting, 1 = player2 acting
    input  wire        player_view,   // 0 = display player1 board, 1 = display player2 board
    input  wire        show_blank,    // 1 = blank screen between turns

    // VGA outputs
    output wire        hsync,
    output wire        vsync,
    output wire [3:0]  red,
    output wire [3:0]  green,
    output wire [3:0]  blue
);

    // Use your provided vga_sync module (must be in project)
    wire        video_on;
    wire [9:0]  x;
    wire [9:0]  y;
    wire        p_tick;
    
    vga_sync vga(
        .clk(clk),
        .reset(reset),
        .hsync(hsync),
        .vsync(vsync),
        .video_on(video_on),
        .p_tick(p_tick),
        .x(x),
        .y(y)
    );

    // ---------- cell/state encoding ----------
    localparam [1:0] EMPTY = 2'b00;
    localparam [1:0] SHIP  = 2'b01;
    localparam [1:0] MISS  = 2'b10;
    localparam [1:0] HIT   = 2'b11;

    // ---------- internal 9x9 grids ----------
    // grid_p1[row][col]
    reg [1:0] grid_p1 [0:8][0:8];
    reg [1:0] grid_p2 [0:8][0:8];

    integer r, c;

    // synchronous reset -> clear grids
    always @(posedge clk) begin
        if (reset) begin
            for (r = 0; r < 9; r = r + 1)
                for (c = 0; c < 9; c = c + 1) begin
                    grid_p1[r][c] <= EMPTY;
                    grid_p2[r][c] <= EMPTY;
                end
        end else begin
            // Placement: set SHIP on active player's own grid
            if (placing_phase && place_pulse) begin
                if (sel_row < 9 && sel_col < 9) begin
                    if (!active_player) begin
                        // player 1 places
                        grid_p1[sel_row][sel_col] <= SHIP;
                    end else begin
                        // player 2 places
                        grid_p2[sel_row][sel_col] <= SHIP;
                    end
                end
            end

            // Fire: updates opponent's grid (hit or miss)
            if (!placing_phase && fire_pulse) begin
                if (sel_row < 9 && sel_col < 9) begin
                    if (!active_player) begin
                        // player1 fires -> modifies player2's board
                        case (grid_p2[sel_row][sel_col])
                            SHIP: grid_p2[sel_row][sel_col] <= HIT;
                            EMPTY: grid_p2[sel_row][sel_col] <= MISS;
                            default: grid_p2[sel_row][sel_col] <= grid_p2[sel_row][sel_col];
                        endcase
                    end else begin
                        // player2 fires -> modifies player1's board
                        case (grid_p1[sel_row][sel_col])
                            SHIP: grid_p1[sel_row][sel_col] <= HIT;
                            EMPTY: grid_p1[sel_row][sel_col] <= MISS;
                            default: grid_p1[sel_row][sel_col] <= grid_p1[sel_row][sel_col];
                        endcase
                    end
                end
            end
        end
    end

    // ---------- VGA rendering ----------
    // We'll render a centered 9x9 board with each cell being CELL_SIZE pixels square.
    // Tweak BOARD_X, BOARD_Y, CELL_SIZE to fit the 640x480 area.
    localparam integer BOARD_X    = 80;  // left pixel of board on screen
    localparam integer BOARD_Y    = 40;  // top pixel of board on screen
    localparam integer CELL_SIZE  = 40;  // pixel size of each cell -> 9*40 = 360 width, fits 640

    // clamp values (if you change sizes, ensure they fit within 640x480)
    // compute which cell (if any) current x,y hits
    wire in_board_x = (x >= BOARD_X) && (x < BOARD_X + CELL_SIZE*9);
    wire in_board_y = (y >= BOARD_Y) && (y < BOARD_Y + CELL_SIZE*9);

    // cell indices for current pixel (0..8)
    wire [3:0] cur_col = in_board_x ? ((x - BOARD_X) / CELL_SIZE) : 4'd15;
    wire [3:0] cur_row = in_board_y ? ((y - BOARD_Y) / CELL_SIZE) : 4'd15;

    // select which board to show
    reg [1:0] show_cell_state;
    always @(*) begin
        if (!video_on || show_blank) begin
            show_cell_state = EMPTY; // blank or off-screen -> treat as empty
        end else if (!(in_board_x && in_board_y)) begin
            show_cell_state = EMPTY;
        end else begin
            if (!player_view) begin
                // show player 1's board
                show_cell_state = grid_p1[cur_row][cur_col];
            end else begin
                // show player 2's board
                show_cell_state = grid_p2[cur_row][cur_col];
            end
        end
    end

    // color mapping for a pixel belonging to a cell:
    // ship  -> green (on owner's view during placement you'd probably want to show ships)
    // miss  -> white
    // hit   -> red
    // empty -> dark blue background and cell borders
    // Also draw grid lines: thin border within cell

    // compute local pixel inside cell for drawing borders
    wire [5:0] local_x = (in_board_x && in_board_y) ? (x - (BOARD_X + cur_col*CELL_SIZE)) : 6'd0;
    wire [5:0] local_y = (in_board_x && in_board_y) ? (y - (BOARD_Y + cur_row*CELL_SIZE)) : 6'd0;

    // grid line thickness
    localparam integer BORDER_T = 2;

    wire cell_border = (local_x < BORDER_T) || (local_x >= CELL_SIZE - BORDER_T) ||
                       (local_y < BORDER_T) || (local_y >= CELL_SIZE - BORDER_T);

    // final rgb outputs (4-bit each)
    reg [3:0] red_reg, green_reg, blue_reg;
    always @(*) begin
        // default background (outside board)
        red_reg   = 4'd0;
        green_reg = 4'd0;
        blue_reg  = 4'd0;

        if (!video_on || show_blank) begin
            // black when blanking
            red_reg = 4'd0; green_reg = 4'd0; blue_reg = 4'd0;
        end else if (!(in_board_x && in_board_y)) begin
            // background / play area: dark blue
            red_reg   = 4'd0;
            green_reg = 4'd0;
            blue_reg  = 4'd4;
        end else begin
            // we are inside the board area
            case (show_cell_state)
                EMPTY: begin
                    if (cell_border) begin
                        // cell border color (light gray)
                        red_reg = 4'd8; green_reg = 4'd8; blue_reg = 4'd8;
                    end else begin
                        // empty cell interior (dark blue)
                        red_reg = 4'd0; green_reg = 4'd0; blue_reg = 4'd6;
                    end
                end
                SHIP: begin
                    // show ship as GREEN
                    if (cell_border) begin
                        red_reg = 4'd6; green_reg = 4'd6; blue_reg = 4'd6;
                    end else begin
                        red_reg = 4'd0; green_reg = 4'd10; blue_reg = 4'd0;
                    end
                end
                MISS: begin
                    // MISS -> white
                    if (cell_border) begin
                        red_reg = 4'd6; green_reg = 4'd6; blue_reg = 4'd6;
                    end else begin
                        red_reg = 4'd12; green_reg = 4'd12; blue_reg = 4'd12;
                    end
                end
                HIT: begin
                    // HIT -> red
                    if (cell_border) begin
                        red_reg = 4'd10; green_reg = 4'd3; blue_reg = 4'd3;
                    end else begin
                        red_reg = 4'd12; green_reg = 4'd0; blue_reg = 4'd0;
                    end
                end
                default: begin
                    red_reg = 4'd0; green_reg = 4'd0; blue_reg = 4'd0;
                end
            endcase
        end
    end

    assign red   = red_reg;
    assign green = green_reg;
    assign blue  = blue_reg;

endmodule


