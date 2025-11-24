`timescale 1ns / 1ps
module Battleship(
    input  wire clk, reset,

    // PMOD JSTK
    input  wire MISO,
    output wire MOSI, SS, SCLK,

    // VGA
    output wire hsync, vsync,
    output wire [3:0] red, green, blue
);

// ============================================================================
//  JOYSTICK INTERFACE
// ============================================================================
wire sndRec;
wire [7:0] sndData;
wire [39:0] jstkData;

PmodJSTK joystick(
    .CLK(clk),
    .RST(reset),
    .sndRec(sndRec),
    .DIN(sndData),
    .MISO(MISO),
    .SS(SS),
    .SCLK(SCLK),
    .MOSI(MOSI),
    .DOUT(jstkData)
);

assign sndData = {6'b100000, 2'b00};

ClkDiv_5Hz joyclk(
    .CLK(clk),
    .RST(reset),
    .CLKOUT(sndRec)
);

// joystick analog ? digital movement
wire [9:0] joy_x = {jstkData[9:8],  jstkData[23:16]};
wire [9:0] joy_y = {jstkData[25:24], jstkData[39:32]};

wire joy_btn_C = jstkData[0];
wire joy_btn_Z = jstkData[2];

// ============================================================================
//  CURSOR CONTROL
// ============================================================================
reg [3:0] sel_row = 4'd4;
reg [3:0] sel_col = 4'd4;

reg joy_left, joy_right, joy_up, joy_down;

reg counter = 0;

always @(posedge clk) begin
    joy_left  <= (joy_x < 10'd350);
    joy_right <= (joy_x > 10'd650);
    joy_up    <= (joy_y < 10'd350);
    joy_down  <= (joy_y > 10'd650);
end

reg [20:0] move_div;
always @(posedge clk) move_div <= move_div + 1;

wire move_tick = (move_div == 0);

always @(posedge clk) begin
    if (reset) begin
        sel_row <= 4'd4;
        sel_col <= 4'd4;
    end else if (move_tick) begin
        if (joy_left  && sel_col > 0) sel_col <= sel_col - 1;
        if (joy_right && sel_col < 8) sel_col <= sel_col + 1;
        if (joy_up    && sel_row > 0) sel_row <= sel_row - 1;
        if (joy_down  && sel_row < 8) sel_row <= sel_row + 1;
    end
end

// pulses
reg prev_C, prev_Z;
always @(posedge clk) begin prev_C <= joy_btn_C; prev_Z <= joy_btn_Z; end

wire place_pulse = joy_btn_C & ~prev_C;
wire fire_pulse  = joy_btn_Z & ~prev_Z;

// ============================================================================
//  VGA SIGNAL
// ============================================================================
wire video_on, p_tick;
wire [9:0] x, y;

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

// ============================================================================
//  BATTLESHIP GAME LOGIC
// ============================================================================
localparam EMPTY=0, SHIP=1, MISS=2, HIT=3;

reg [1:0] grid_p1[0:8][0:8];
reg [1:0] grid_p2[0:8][0:8];

reg placing_phase = 1;      // toggle using corner trick
reg active_player  = 0;     // always player1 for single player
reg player_view    = 0;     // always view player1 grid
reg show_blank     = 0;

integer r, c;
always @(posedge clk) begin
    if (reset) begin
        for (r=0; r<9; r=r+1)
            for (c=0; c<9; c=c+1) begin
                grid_p1[r][c] <= EMPTY;
                grid_p2[r][c] <= EMPTY;
            end
    end else begin
        // placing
        if (placing_phase && place_pulse)
            grid_p1[sel_row][sel_col] <= SHIP;

        // firing
        if (!placing_phase && fire_pulse) begin
            case (grid_p2[sel_row][sel_col])
                SHIP:  grid_p2[sel_row][sel_col] <= HIT;
                EMPTY: grid_p2[sel_row][sel_col] <= MISS;
            endcase
        end
    end
end

// ============================================================================
//  VGA RENDERING + CURSOR
// ============================================================================
localparam BOARD_X=80, BOARD_Y=40, CELL_SIZE=40;

wire in_board_x = (x>=BOARD_X && x<BOARD_X+CELL_SIZE*9);
wire in_board_y = (y>=BOARD_Y && y<BOARD_Y+CELL_SIZE*9);

wire [3:0] cur_col = in_board_x ? ((x-BOARD_X)/CELL_SIZE) : 4'd15;
wire [3:0] cur_row = in_board_y ? ((y-BOARD_Y)/CELL_SIZE) : 4'd15;

wire cursor_active = (cur_row == sel_row && cur_col == sel_col);

reg [1:0] show_cell_state;

always @(*) begin
    if (!video_on)
        show_cell_state = EMPTY;
    else if (!(in_board_x && in_board_y))
        show_cell_state = EMPTY;
    else
        show_cell_state = grid_p1[cur_row][cur_col];
end

wire [5:0] local_x = (x - (BOARD_X + cur_col*CELL_SIZE));
wire [5:0] local_y = (y - (BOARD_Y + cur_row*CELL_SIZE));
wire cell_border = (local_x < 2 || local_x >= CELL_SIZE-2 ||
                    local_y < 2 || local_y >= CELL_SIZE-2);

reg [3:0] red_reg, green_reg, blue_reg;

always @(*) begin
    // background
    red_reg=0; green_reg=0; blue_reg=0;

    if (!video_on) begin
        {red_reg,green_reg,blue_reg} = 12'h000;
    end
    else if (!(in_board_x && in_board_y)) begin
        {red_reg,green_reg,blue_reg} = 12'h004; // dark blue
    end
    else begin
        if (cursor_active) begin
            // ===========================
            //  CURSOR HIGHLIGHT COLOR
            // ===========================
            red_reg = 4'd12;
            green_reg = 4'd12;
            blue_reg = 4'd0;
        end
        else begin
            case (show_cell_state)
                EMPTY: begin
                    if (cell_border)
                        {red_reg,green_reg,blue_reg} = 12'h888;
                    else
                        {red_reg,green_reg,blue_reg} = 12'h006;
                end
                SHIP: begin
                    if (cell_border)
                        {red_reg,green_reg,blue_reg} = 12'h666;
                    else
                        {red_reg,green_reg,blue_reg} = 12'h0A0;
                end
                MISS: begin
                    if (cell_border)
                        {red_reg,green_reg,blue_reg} = 12'h666;
                    else
                        {red_reg,green_reg,blue_reg} = 12'hCCC;
                end
                HIT: begin
                    if (cell_border)
                        {red_reg,green_reg,blue_reg} = 12'hA33;
                    else
                        {red_reg,green_reg,blue_reg} = 12'hC00;
                end
            endcase
        end
    end
end

assign red   = red_reg;
assign green = green_reg;
assign blue  = blue_reg;

endmodule


