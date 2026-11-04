`timescale 1ns / 1ps

// 직렬 핀을 독립적으로 복호화하는 비합성 검증 모델이다.
module uart_rx_model #(
    parameter integer BIT_CYCLES = 868
) (
    input wire clk,
    input wire rst,
    input wire rx,
    output reg valid = 1'b0,
    output reg [7:0] data = 8'b0,
    output reg framing_error = 1'b0
);
  integer state = 0;
  integer count = 0;
  integer index = 0;
  reg [7:0] shift = 8'b0;

  always @(posedge clk) begin
    valid <= 1'b0;
    if (rst) begin
      state <= 0;
      count <= 0;
      index <= 0;
      framing_error <= 1'b0;
    end else begin
      case (state)
        0: begin
          if (!rx) begin
            state <= 1;
            count <= 0;
          end
        end
        1: begin
          if (count == BIT_CYCLES / 2 - 1) begin
            if (!rx) begin
              state <= 2;
              index <= 0;
            end else begin
              state <= 0;
            end
            count <= 0;
          end else begin
            count <= count + 1;
          end
        end
        2: begin
          if (count == BIT_CYCLES - 1) begin
            shift[index] <= rx;
            count <= 0;
            if (index == 7) begin
              state <= 3;
            end else begin
              index <= index + 1;
            end
          end else begin
            count <= count + 1;
          end
        end
        3: begin
          if (count == BIT_CYCLES - 1) begin
            framing_error <= !rx;
            data <= shift;
            valid <= 1'b1;
            state <= 0;
            count <= 0;
          end else begin
            count <= count + 1;
          end
        end
      endcase
    end
  end
endmodule
