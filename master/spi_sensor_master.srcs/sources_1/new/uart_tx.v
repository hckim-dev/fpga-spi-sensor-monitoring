`timescale 1ns / 1ps

module uart_tx #(
  parameter integer BIT_CYCLES = 868
) (
  input wire clk,
  input wire rst,
  input wire start,
  input wire [7:0] data,
  output reg tx,
  output reg busy,
  output reg done
);
  function integer count_width;
    input integer maximum;
    integer value;
    begin
      value = maximum;
      count_width = 0;
      while (value > 0) begin
        count_width = count_width + 1;
        value = value >> 1;
      end
      if (count_width == 0) begin
        count_width = 1;
      end
    end
  endfunction

  localparam integer COUNT_WIDTH = count_width(BIT_CYCLES - 1);
  localparam [COUNT_WIDTH-1:0] BIT_LAST = BIT_CYCLES - 1;
  reg [COUNT_WIDTH-1:0] bit_count;
  reg [3:0] bit_index;
  reg [9:0] frame;

  // synthesis translate_off
  initial begin
    if (BIT_CYCLES < 1) begin
      $display("ERROR: uart_tx BIT_CYCLES must be positive");
      $finish;
    end
  end
  // synthesis translate_on

  always @(posedge clk) begin
    if (rst) begin
      tx <= 1'b1;
      busy <= 1'b0;
      done <= 1'b0;
      bit_count <= {COUNT_WIDTH{1'b0}};
      bit_index <= 4'b0;
      frame <= 10'b1111111111;
    end else begin
      done <= 1'b0;
      if (!busy) begin
        if (start) begin
          frame <= {1'b1, data, 1'b0};
          tx <= 1'b0;
          busy <= 1'b1;
          bit_count <= {COUNT_WIDTH{1'b0}};
          bit_index <= 4'b0;
        end
      end else if (bit_count == BIT_LAST) begin
        bit_count <= {COUNT_WIDTH{1'b0}};
        if (bit_index == 4'd9) begin
          tx <= 1'b1;
          busy <= 1'b0;
          done <= 1'b1;
        end else begin
          frame <= {1'b1, frame[9:1]};
          tx <= frame[1];
          bit_index <= bit_index + 1'b1;
        end
      end else begin
        bit_count <= bit_count + 1'b1;
      end
    end
  end
endmodule
