`timescale 1ns / 1ps

module tb_fnd_controller;
  localparam integer DIGIT_CYCLES = 8;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg [1:0] display_sel = 2'b0;
  reg signed [15:0] temperature = 16'sd235;
  reg [15:0] humidity = 16'd600;
  reg [15:0] distance = 16'd291;
  reg [1:0] sensor_valid = 2'b11;
  wire [3:0] an;
  wire [6:0] seg;
  wire dp;

  fnd_controller #(
    .DIGIT_CYCLES(DIGIT_CYCLES)
  ) u_fnd_controller (
    .clk(clk),
    .rst(rst),
    .display_sel(display_sel),
    .temperature(temperature),
    .humidity(humidity),
    .distance(distance),
    .sensor_valid(sensor_valid),
    .an(an),
    .seg(seg),
    .dp(dp)
  );

  always #5 clk = ~clk;
  integer failures = 0;
  integer cases = 0;
  integer cycles = 0;
  integer last_on = 0;
  integer expected_index = 0;
  reg saw_on = 1'b0;
  reg [3:0] previous_an = 4'b1111;
  reg [6:0] previous_seg = 7'b1111111;
  reg previous_dp = 1'b1;

  task check;
    input condition;
    input [767:0] message;
    begin
      if (condition !== 1'b1) begin
        failures = failures + 1;
        $display("FAIL @ %0t: %0s", $time, message);
      end
    end
  endtask

  // 기대 Segment는 켜져야 하는 a~g 목록으로 독립 정의한다.
  function [6:0] expected_segment;
    input [3:0] digit;
    begin
      case (digit)
        0: expected_segment = ~7'b0111111;
        1: expected_segment = ~7'b0000110;
        2: expected_segment = ~7'b1011011;
        3: expected_segment = ~7'b1001111;
        4: expected_segment = ~7'b1100110;
        5: expected_segment = ~7'b1101101;
        6: expected_segment = ~7'b1111101;
        7: expected_segment = ~7'b0000111;
        8: expected_segment = ~7'b1111111;
        9: expected_segment = ~7'b1101111;
        11: expected_segment = ~7'b1000000;
        default: expected_segment = ~7'b0000000;
      endcase
    end
  endfunction

  always @(posedge clk) begin
    cycles = cycles + 1;
    #1;
    if (rst) begin
      check(an == 4'b1111 && seg == 7'b1111111 && dp, "reset turns all outputs off");
      saw_on = 1'b0;
      expected_index = 0;
    end else begin
      check(an == 4'b1111 || an == 4'b1110 || an == 4'b1101 ||
            an == 4'b1011 || an == 4'b0111, "at most one active-low digit");
      if ({seg, dp} !== {previous_seg, previous_dp}) begin
        check(an == 4'b1111 && previous_an == 4'b1111, "segments change only after digit off");
      end
      if (an != 4'b1111 && an != previous_an) begin
        check(previous_an == 4'b1111 && seg === previous_seg && dp === previous_dp,
              "segments stable before digit enable");
        check(an === ~(4'b0001 << expected_index), "digit order 0 to 3");
        expected_index = (expected_index + 1) % 4;
        if (saw_on) begin
          check(cycles - last_on == DIGIT_CYCLES, "exact digit period");
        end
        last_on = cycles;
        saw_on = 1'b1;
      end
    end
    previous_an = an;
    previous_seg = seg;
    previous_dp = dp;
  end

  task read_scan;
    input [15:0] expected_digits;
    input [3:0] expected_points;
    integer index;
    begin
      @(negedge an[0]);
      #2;
      for (index = 0; index < 4; index = index + 1) begin
        if (index != 0) begin
          @(negedge an[index]);
          #2;
        end
        check(seg === expected_segment(expected_digits[index*4 +: 4]), "expected glyph at physical digit");
        check(dp === !expected_points[index], "expected decimal point");
      end
      cases = cases + 1;
    end
  endtask

  task show;
    input [1:0] selection;
    input [15:0] temp_value;
    input [15:0] hum_value;
    input [15:0] dist_value;
    input [1:0] valid;
    input [15:0] digits;
    input [3:0] points;
    begin
      @(negedge clk);
      display_sel = selection;
      temperature = temp_value;
      humidity = hum_value;
      distance = dist_value;
      sensor_valid = valid;
      read_scan(digits, points);
    end
  endtask

  integer digit;
  integer value;
  reg [15:0] expected_digits;
  initial begin
    $timeformat(-9, 0, "ns", 12);
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    read_scan(16'hA235, 4'b0010);
    show(0, -16'sd55, 600, 291, 3, 16'hAB55, 2);
    show(0, -16'sd200, 600, 291, 3, 16'hB200, 2);
    show(0, -16'sd1, 600, 291, 3, 16'hAB01, 2);
    show(0, -16'sd99, 600, 291, 3, 16'hAB99, 2);
    show(0, -16'sd100, 600, 291, 3, 16'hB100, 2);
    show(0, 0, 0, 2, 3, 16'hAA00, 2);
    show(0, 600, 1000, 400, 3, 16'hA600, 2);
    show(1, 235, 600, 291, 3, 16'hA600, 2);
    show(1, 235, 1000, 291, 3, 16'h1000, 2);
    show(1, 235, 0, 291, 3, 16'hAA00, 2);
    show(2, 235, 600, 291, 3, 16'hA291, 0);
    show(2, 235, 600, 2, 3, 16'hAAA2, 0);
    show(2, 235, 600, 400, 3, 16'hA400, 0);
    show(3, 235, 600, 291, 3, 16'hA235, 2);
    show(0, 16'h8000, 16'hFFFF, 16'hFFFF, 0, 16'hBBBB, 0);
    show(1, 235, 600, 291, 2, 16'hBBBB, 0);
    show(2, 235, 600, 291, 1, 16'hBBBB, 0);
    for (digit = 0; digit < 10; digit = digit + 1) begin
      show(2, 235, 600, 120 + digit, 3, {4'hA, 4'h1, 4'h2, digit[3:0]}, 0);
    end

    // 유효 절댓값 전 범위를 나눗셈으로 계산해 BCD 변환과 대조한다.
    for (value = 0; value <= 1000; value = value + 1) begin
      expected_digits[15:12] = value >= 1000 ? 4'd1 : 4'd10;
      expected_digits[11:8] = value >= 100 ? (value / 100) % 10 : 4'd10;
      expected_digits[7:4] = (value / 10) % 10;
      expected_digits[3:0] = value % 10;
      show(1, 235, value[15:0], 291, 3, expected_digits, 2);
    end

    // Scan 중 선택·수치·Valid 변경은 다음 네 자리부터 반영한다.
    show(0, 235, 600, 291, 3, 16'hA235, 2);
    @(negedge an[0]);
    #2;
    @(negedge clk);
    display_sel = 2;
    distance = 400;
    sensor_valid = 0;
    @(negedge an[1]);
    #2;
    check(seg === expected_segment(3) && !dp, "old scan keeps decimal and value");
    @(negedge an[2]);
    #2;
    check(seg === expected_segment(2), "old scan keeps hundreds");
    @(negedge an[3]);
    #2;
    check(seg === expected_segment(10), "old scan keeps leading blank");
    read_scan(16'hBBBB, 0);

    @(negedge clk);
    rst = 1'b1;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    sensor_valid = 3;
    read_scan(16'hA400, 0);
    if (failures == 0) begin
      $display("FND_TEST_PASS cases=%0d", cases);
    end else begin
      $display("FND_TEST_FAIL failures=%0d", failures);
    end
    $finish;
  end

  initial begin
    #1000000;
    $display("FND_TEST_FAIL global timeout");
    $finish;
  end
endmodule
