`timescale 1ns / 1ps

module fnd_controller #(
    parameter integer DIGIT_CYCLES = 25000
) (
    input wire clk,
    input wire rst,
    input wire [1:0] display_sel,
    input wire signed [15:0] temperature,
    input wire [15:0] humidity,
    input wire [15:0] distance,
    input wire [1:0] sensor_valid,
    output reg [3:0] an,
    output reg [6:0] seg,
    output reg dp
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

  localparam integer COUNT_WIDTH = count_width(DIGIT_CYCLES - 1);
  localparam [COUNT_WIDTH-1:0] DIGIT_LAST = DIGIT_CYCLES - 1;
  localparam [3:0] BLANK = 4'd10;
  localparam [3:0] MINUS = 4'd11;

  reg [COUNT_WIDTH-1:0] scan_count;
  reg [1:0] digit_index;
  reg [15:0] scan_digits;
  reg [3:0] scan_points;
  reg [15:0] next_digits;
  reg [3:0] next_points;
  reg [15:0] magnitude;
  reg selected_valid;
  reg fractional;
  reg negative;
  reg [3:0] thousands;
  reg [3:0] hundreds;
  reg [3:0] tens;

  function [15:0] decimal_digits;
    input [9:0] value;
    reg [15:0] digits;
    integer bit_index;
    integer place;
    begin
      digits = 16'b0;
      for (bit_index = 9; bit_index >= 0; bit_index = bit_index - 1) begin
        for (place = 0; place < 4; place = place + 1) begin
          if (digits[place*4+:4] >= 4'd5) begin
            digits[place*4+:4] = digits[place*4+:4] + 4'd3;
          end
        end
        digits = {digits[14:0], value[bit_index]};
      end
      decimal_digits = digits;
    end
  endfunction

  // seg[6:0]은 g/f/e/d/c/b/a 순서이며 0일 때 점등한다.
  function [6:0] segment_pattern;
    input [3:0] digit;
    begin
      case (digit)
        4'd0: segment_pattern = 7'b1000000;
        4'd1: segment_pattern = 7'b1111001;
        4'd2: segment_pattern = 7'b0100100;
        4'd3: segment_pattern = 7'b0110000;
        4'd4: segment_pattern = 7'b0011001;
        4'd5: segment_pattern = 7'b0010010;
        4'd6: segment_pattern = 7'b0000010;
        4'd7: segment_pattern = 7'b1111000;
        4'd8: segment_pattern = 7'b0000000;
        4'd9: segment_pattern = 7'b0010000;
        MINUS: segment_pattern = 7'b0111111;
        default: segment_pattern = 7'b1111111;
      endcase
    end
  endfunction

  // synthesis translate_off
  initial begin
    if (DIGIT_CYCLES < 3) begin
      $display("ERROR: fnd_controller DIGIT_CYCLES must be at least 3");
      $finish;
    end
  end
  // synthesis translate_on

  always @* begin
    selected_valid = sensor_valid[0];
    fractional = 1'b1;
    negative = 1'b0;
    magnitude = humidity;
    case (display_sel)
      2'b01: begin
        magnitude = humidity;
      end
      2'b10: begin
        selected_valid = sensor_valid[1];
        fractional = 1'b0;
        magnitude = distance;
      end
      default: begin
        negative  = temperature < 16'sd0;
        magnitude = negative ? -temperature : temperature;
      end
    endcase

    // Reader가 허용한 표시 절댓값은 최대 1000이므로 10 Bit로 변환한다.
    next_digits = decimal_digits(magnitude[9:0]);
    thousands = next_digits[15:12];
    hundreds = next_digits[11:8];
    tens = next_digits[7:4];
    next_points = fractional ? 4'b0010 : 4'b0000;

    if (!selected_valid) begin
      next_digits = {MINUS, MINUS, MINUS, MINUS};
      next_points = 4'b0;
    end else begin
      if (thousands == 0) begin
        next_digits[15:12] = BLANK;
      end
      if (thousands == 0 && hundreds == 0) begin
        next_digits[11:8] = BLANK;
      end
      if (!fractional && thousands == 0 && hundreds == 0 && tens == 0) begin
        next_digits[7:4] = BLANK;
      end
      if (negative) begin
        if (hundreds != 0) begin
          next_digits[15:12] = MINUS;
        end else begin
          next_digits[11:8] = MINUS;
        end
      end
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      scan_count <= {COUNT_WIDTH{1'b0}};
      digit_index <= 2'b0;
      scan_digits <= {BLANK, BLANK, BLANK, BLANK};
      scan_points <= 4'b0;
      an <= 4'b1111;
      seg <= 7'b1111111;
      dp <= 1'b1;
    end else begin
      if (scan_count == DIGIT_LAST) begin
        scan_count  <= {COUNT_WIDTH{1'b0}};
        digit_index <= digit_index + 1'b1;
      end else begin
        scan_count <= scan_count + 1'b1;
      end

      // 네 자리 시작에서 고정한 표시를 OFF → 설정 → ON 순서로 출력한다.
      if (scan_count == 0) begin
        an <= 4'b1111;
        if (digit_index == 0) begin
          scan_digits <= next_digits;
          scan_points <= next_points;
        end
      end else if (scan_count == 1) begin
        seg <= segment_pattern(scan_digits[digit_index*4+:4]);
        dp  <= !scan_points[digit_index];
      end else if (scan_count == 2) begin
        an <= ~(4'b0001 << digit_index);
      end
    end
  end
endmodule
