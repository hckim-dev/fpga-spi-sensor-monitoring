`timescale 1ns / 1ps

module tb_sensor_display;
  reg clk = 1'b0;
  reg rst = 1'b1;
  wire spi_start;
  wire [79:0] spi_tx_frame;
  wire spi_busy;
  wire spi_done;
  wire spi_error;
  wire [79:0] spi_rx_frame;
  wire [6:0] spi_rx_bits;
  wire spi_cs_n;
  wire spi_sclk;
  wire spi_mosi;
  wire spi_miso;
  reg [79:0] reply_frame = 80'h00A50300EB0258012335;
  reg peer_reset = 1'b0;
  wire signed [15:0] temperature;
  wire [15:0] humidity;
  wire [15:0] distance;
  wire [1:0] sensor_valid;
  wire link_valid;
  wire link_stale;
  wire [2:0] last_error;
  wire [7:0] debug_rx_byte;
  wire report_update;
  wire sample_toggle;

  // SPI Timing은 실설정, Poll과 Stale만 각각 1ms와 3ms로 줄인다.
  sensor_reader #(
    .POLL_CYCLES(100000),
    .STALE_CYCLES(300000)
  ) u_sensor_reader (
    .clk(clk),
    .rst(rst),
    .spi_start(spi_start),
    .spi_tx_frame(spi_tx_frame),
    .spi_busy(spi_busy),
    .spi_done(spi_done),
    .spi_error(spi_error),
    .spi_rx_frame(spi_rx_frame),
    .spi_rx_bits(spi_rx_bits),
    .temperature(temperature),
    .humidity(humidity),
    .distance(distance),
    .sensor_valid(sensor_valid),
    .link_valid(link_valid),
    .link_stale(link_stale),
    .last_error(last_error),
    .debug_rx_byte(debug_rx_byte),
    .report_update(report_update),
    .sample_toggle(sample_toggle)
  );

  spi_master u_spi_master (
    .clk(clk),
    .rst(rst),
    .start(spi_start),
    .tx_frame(spi_tx_frame),
    .busy(spi_busy),
    .done(spi_done),
    .error(spi_error),
    .rx_frame(spi_rx_frame),
    .rx_bits(spi_rx_bits),
    .spi_cs_n(spi_cs_n),
    .spi_sclk(spi_sclk),
    .spi_mosi(spi_mosi),
    .spi_miso(spi_miso)
  );

  spi_sensor_peer u_spi_sensor_peer (
    .spi_cs_n(spi_cs_n),
    .spi_sclk(spi_sclk),
    .spi_mosi(spi_mosi),
    .spi_miso(spi_miso),
    .reply_frame(reply_frame),
    .peer_reset(peer_reset)
  );

  reg [1:0] display_sel = 2'b0;
  wire [3:0] an;
  wire [6:0] seg;
  wire dp;

  fnd_controller u_fnd_controller (
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
  integer frames = 0;
  integer cycles = 0;
  integer last_start = 0;
  integer last_digit_zero = 0;
  reg [15:0] observed_digits = 16'b0;
  reg [3:0] observed_points = 4'b0;
  reg [6:0] old_seg = 7'b1111111;
  reg old_dp = 1'b1;
  reg [3:0] old_an = 4'b1111;

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

  function [3:0] decode;
    input [6:0] pattern;
    begin
      case (pattern)
        7'b1000000: decode = 0;
        7'b1111001: decode = 1;
        7'b0100100: decode = 2;
        7'b0110000: decode = 3;
        7'b0011001: decode = 4;
        7'b0010010: decode = 5;
        7'b0000010: decode = 6;
        7'b1111000: decode = 7;
        7'b0000000: decode = 8;
        7'b0010000: decode = 9;
        7'b1111111: decode = 10;
        7'b0111111: decode = 11;
        default: decode = 15;
      endcase
    end
  endfunction

  always @(posedge clk) begin
    cycles = cycles + 1;
    if (!rst && spi_start) begin
      if (last_start != 0) begin
        check(cycles - last_start == 100000, "display scan does not delay SPI poll");
      end
      last_start = cycles;
      frames = frames + 1;
    end
    #1;
    if (!rst) begin
      if ({seg, dp} !== {old_seg, old_dp}) begin
        check(an == 15 && old_an == 15, "integration break before segment change");
      end
      if (an == 14 && old_an == 15) begin
        if (last_digit_zero != 0) begin
          check(cycles - last_digit_zero == 100000, "default full scan exactly 1ms");
        end
        last_digit_zero = cycles;
      end
    end
    old_an = an;
    old_seg = seg;
    old_dp = dp;
  end

  task expect_display;
    input [15:0] digits;
    input [3:0] points;
    integer index;
    begin
      // 최대 한 Scan의 반영 지연 뒤 완성된 다음 Scan을 관측한다.
      repeat (100005) @(posedge clk);
      @(negedge an[0]);
      #2;
      observed_digits[3:0] = decode(seg);
      observed_points[0] = !dp;
      for (index = 1; index < 4; index = index + 1) begin
        @(negedge an[index]);
        #2;
        observed_digits[index*4 +: 4] = decode(seg);
        observed_points[index] = !dp;
      end
      check(observed_digits === digits && observed_points === points,
            "SPI result reaches expected physical display glyphs");
      cases = cases + 1;
    end
  endtask

  initial begin
    $timeformat(-9, 0, "ns", 12);
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 0;
    expect_display(16'hA235, 2);
    display_sel = 1;
    expect_display(16'hA600, 2);
    display_sel = 2;
    expect_display(16'hA291, 0);
    reply_frame = 80'h00A503FFC901C4007B2E;
    display_sel = 0;
    expect_display(16'hAB55, 2);
    reply_frame = 80'h00A50300EA0258012335;
    expect_display(16'hBBBB, 0);
    check(!link_valid && last_error == 4, "corrupt SPI frame invalidates display");
    expect_display(16'hBBBB, 0);
    check(link_stale && !link_valid, "continued errors reach stale during scanning");
    reply_frame = 80'h00A50300EB0258012335;
    expect_display(16'hA235, 2);
    check(link_valid && !link_stale, "valid SPI frame restores display");
    check(frames >= 10, "SPI continues throughout display changes and errors");
    if (failures == 0) begin
      $display("SENSOR_DISPLAY_TEST_PASS cases=%0d frames=%0d", cases, frames);
    end else begin
      $display("SENSOR_DISPLAY_TEST_FAIL failures=%0d", failures);
    end
    $finish;
  end

  initial begin
    #25000000;
    $display("SENSOR_DISPLAY_TEST_FAIL global timeout");
    $finish;
  end
endmodule
