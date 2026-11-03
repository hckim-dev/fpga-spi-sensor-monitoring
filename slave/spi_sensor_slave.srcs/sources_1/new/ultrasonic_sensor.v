`timescale 1ns / 1ps
module ultrasonic_sensor(
    input clk,
    input reset,
    input echo,
    input start_trig,
    output reg trig,
    output reg [8:0] distance
    );

    parameter IDLE = 2'b00;
    parameter START_SIGNAL = 2'b01;
    parameter WAIT_HIGH = 2'b10;
    parameter READ_DATA = 2'b11;

    reg [1:0] state;
    wire tick;
    reg [14:0] tick_cnt;

    tick_generator # (
        .INPUT_FREQ(100_000_000),   // 100MHz
        .TICK_Hz(1000)  // 1KHz
    ) u_tick_1Hz (
        .clk(clk),
        .reset(reset),
        .tick(tick)
    );

    always @(posedge clk, posedge reset) begin
        if(reset) begin 
            state <= IDLE;
            trig <= 0;
            distance <= 14'b0;
            tick_cnt <= 0;
        end else if(tick) begin
            case(state)
                IDLE: begin
                    if(start_trig) begin
                        trig <= 1;
                        tick_cnt<=0;
                        state <= START_SIGNAL;
                    end 
                end
                START_SIGNAL : begin
                    if(tick_cnt == 10) begin
                        trig <= 0;
                        tick_cnt<= 0;
                        state <= WAIT_HIGH;
                    end else begin
                        tick_cnt <= tick_cnt + 1;
                    end
                end
                WAIT_HIGH : begin
                    if(echo) begin 
                        tick_cnt <= 0;
                        state <= READ_DATA;
                    end else if(tick_cnt > 10_000) begin
                        state <= IDLE;
                    end else begin
                        tick_cnt <= tick_cnt + 1;
                    end
                end
                READ_DATA : begin
                    if(!echo) begin 
                        distance <= tick_cnt / 58;
                        state <= IDLE;
                    end else if(tick_cnt > 10_000) begin
                        state <= IDLE;
                    end else begin
                        tick_cnt <= tick_cnt + 1;
                    end
                end
                default : state <= IDLE;
            endcase
        end
    end
endmodule