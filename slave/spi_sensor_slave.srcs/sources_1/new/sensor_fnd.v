module sensor_fnd(
    input clk, reset,
    input [2:0] sw,
    input [63:0] snapshot,
    input trigger_seen, echo_seen,
    output reg [6:0] seg,
    output reg [3:0] an,
    output reg dp
);
    (* ASYNC_REG="TRUE" *) reg [2:0] sw_meta, sw_sync;
    reg [16:0] scan;
    reg [10:0] value;
    reg valid, fraction, negative;

    wire [15:0] temperature = snapshot[47:32];
    wire [3:0] scan_an;
    wire [7:0] scan_seg;
    fnd_controller controller (
        .clk(clk), .reset(reset), .tick(scan == 17'd99999),
        .in_data({3'b0, value}), .an(scan_an), .seg(scan_seg)
    );

    always @(posedge clk) begin
        sw_meta <= sw;
        sw_sync <= sw_meta;
        if (reset || scan == 17'd99999) scan <= 0;
        else scan <= scan + 1'b1;
    end

    always @* begin
        valid = 0;
        fraction = 0;
        negative = 0;
        value = 0;
        case (sw_sync)
            3'b001: begin
                valid = snapshot[48];
                fraction = 1;
                negative = temperature[15];
                value = negative ? -temperature : temperature;
            end
            3'b010: begin
                valid = snapshot[48];
                fraction = 1;
                value = snapshot[31:16];
            end
            3'b100: begin
                valid = snapshot[49];
                value = snapshot[15:0];
                if (!snapshot[49]) begin
                    valid = 1;
                    if (!trigger_seen) value = 1;
                    else if (!echo_seen) value = 2;
                    else value = 3;
                end
            end
            default: valid = 0;
        endcase

        an = 4'b1111;
        dp = 1;
        seg = 7'b1111111;
        if (!reset && sw_sync != 0) begin
            an = scan_an;
            if (!valid) seg = 7'b0111111;
            else case (scan_an)
                4'b1110: seg = scan_seg[6:0];
                4'b1101: begin
                    if (fraction || value >= 10 || (sw_sync == 3'b100 && !snapshot[49])) seg = scan_seg[6:0];
                    dp = !fraction;
                end
                4'b1011: begin
                    if (value >= 100 || (sw_sync == 3'b100 && !snapshot[49])) seg = scan_seg[6:0];
                    else if (negative) seg = 7'b0111111;
                end
                4'b0111: begin
                    if (value >= 1000 || (sw_sync == 3'b100 && !snapshot[49])) seg = scan_seg[6:0];
                    else if (negative && value >= 100) seg = 7'b0111111;
                end
                default: an = 4'b1111;
            endcase
        end
    end
endmodule

