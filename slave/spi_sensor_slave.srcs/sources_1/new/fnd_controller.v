`timescale 1ns / 1ps
module fnd_controller(input clk, reset, tick, [13:0]in_data, output [3:0]an, [7:0]seg);

    wire [1:0] w_sel;
    fnd_digit_select u_fnd_digit_select(.clk(clk), .reset(reset), .tick(tick), .sel(w_sel));

    wire [3:0]w_d1, w_d10, w_d100, w_d1000;
    bin2bcd4_digit u_bin2bcd4_digit(.in_data(in_data), .d1(w_d1), .d10(w_d10), .d100(w_d100), .d1000(w_d1000));

    fnd_digit_display u_fnd_digit_display(.sel(w_sel), .d1(w_d1), .d10(w_d10), .d100(w_d100), .d1000(w_d1000), .an(an), .seg(seg));
endmodule

// logic select 1_digit displaying fnd every 1ms, 
module fnd_digit_select(input clk, reset, tick, output reg[1:0] sel);
    
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            sel <= 0;
        end else begin
            if(tick) begin
                sel <= sel + 1;
            end
        end
    end
endmodule

// in_data : bin size express to 9999 in 14bit fnd
// 0000 ~ 9999 /digit number 0 ~ 9 bcd 4bit express
module bin2bcd4_digit(input [13:0] in_data, output [3:0]d1, [3:0]d10, [3:0]d100, [3:0]d1000);
    
    assign d1 = in_data % 10;
    assign d10 = (in_data / 10) % 10;
    assign d100 = (in_data / 100) % 10;
    assign d1000 = (in_data / 1000) % 10;
endmodule

module fnd_digit_display(input [1:0]sel, [3:0]d1, [3:0]d10, [3:0]d100, [3:0]d1000, output reg [3:0]an, reg [7:0]seg);

    reg [3:0] bcd_data;

    always @* begin
        case(sel)
            2'b00: begin
                bcd_data = d1;
                an = 4'b1110;
            end
            2'b01: begin
                bcd_data = d10;
                an = 4'b1101;
            end
            2'b10: begin
                bcd_data = d100;
                an = 4'b1011;
            end
            2'b11: begin
                bcd_data = d1000;
                an = 4'b0111;
            end
            default: begin
                bcd_data = 4'b0000;
                an = 4'b1111;
            end
        endcase
    end

    always @* begin
        case(bcd_data)
            4'd0: seg = 8'b11000000;   // 0
            4'd1: seg = 8'b11111001;   // 1
            4'd2: seg = 8'b10100100;   // 2
            4'd3: seg = 8'b10110000;   // 3
            4'd4: seg = 8'b10011001;   // 4
            4'd5: seg = 8'b10010010;   // 5
            4'd6: seg = 8'b10000010;   // 6
            4'd7: seg = 8'b11111000;   // 7
            4'd8: seg = 8'b10000000;   // 8
            4'd9: seg = 8'b10010000;   // 9
            default: seg = 8'b11111111;  // all off  
        endcase 
    end 
endmodule

