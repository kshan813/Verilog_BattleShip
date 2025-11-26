module seven_segment_display (
    input  wire clk,
    input  wire HIT,
    input  wire FAIL,
    output reg [6:0] seg,
    output reg [3:0] an
);

    // ============================================================
    // 1) Hold HIT/FAIL for longer (about 0.5 seconds)
    // ============================================================
    reg [25:0] hold_timer = 0;         // for 100 MHz clock ? 0.5s ? 50,000,000
    reg [1:0]  latched_state = 0;      // 0=none, 1=HIT, 2=FAIL

    always @(posedge clk) begin
        // If a new hit/miss occurs, latch and reset timer
        if (HIT) begin
            latched_state <= 2'd1;
            hold_timer <= 26'd50_000_000;   // ~0.5 second
        end else if (FAIL) begin
            latched_state <= 2'd2;
            hold_timer <= 26'd50_000_000;
        end
        // Countdown timer
        else if (hold_timer > 0)
            hold_timer <= hold_timer - 1;
        else
            latched_state <= 0;  // time expired ? clear
    end

    // ============================================================
    // 2) Slow digit multiplex clock (~1kHz)
    // ============================================================
    reg [15:0] div = 0;
    reg slow_tick = 0;

    always @(posedge clk) begin
        div <= div + 1;
        slow_tick <= (div == 0);
    end

    // ============================================================
    // 3) Digit counter
    // ============================================================
    reg [1:0] counter = 0;
    always @(posedge clk) begin
        if (slow_tick)
            counter <= counter + 1;
    end

    // Digit enable
    always @(*) begin
        case (counter)
            2'd0: an = 4'b1110;
            2'd1: an = 4'b1101;
            2'd2: an = 4'b1011;
            2'd3: an = 4'b0111;
        endcase
    end

    // ============================================================
    // 4) Select which message to show (latched)
    // ============================================================
    always @(*) begin
        case (latched_state)
            2'd1: seg = decode_hit(counter);
            2'd2: seg = decode_fail(counter);
            default: seg = 7'b1111111;   // blank
        endcase
    end


    // ----- HIT -----
    // Display:  [H] [I] [T] [blank]  (active-low segment encoding)
    function [6:0] decode_hit;
        input [1:0] pos;
        begin
            case (pos)
                2'd3: decode_hit = 7'b0001001; // H
                2'd2: decode_hit = 7'b1111001; // I
                2'd1: decode_hit = 7'b0000011; // T
                2'd0: decode_hit = 7'b1111111; // blank
                default: decode_hit = 7'b1111111;
            endcase
        end
    endfunction


    // ----- FAIL -----
    // Display: [F] [A] [I] [L]
    function [6:0] decode_fail;
        input [1:0] pos;
        begin
            case (pos)
                2'd3: decode_fail = 7'b0001110; // F
                2'd2: decode_fail = 7'b0001000; // A
                2'd1: decode_fail = 7'b1111001; // I
                2'd0: decode_fail = 7'b1000111; // L
                default: decode_fail = 7'b1111111;
            endcase
        end
    endfunction

endmodule

