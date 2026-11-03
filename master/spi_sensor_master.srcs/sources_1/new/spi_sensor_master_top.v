`timescale 1ns / 1ps

module spi_sensor_master_top #(
  parameter integer POLL_CYCLES = 10000000,
  parameter integer STALE_CYCLES = 50000000,
  parameter integer DIGIT_CYCLES = 25000,
  parameter integer UART_BIT_CYCLES = 868,
  parameter integer OLED_POWERUP_CYCLES = 10000000,
  parameter integer OLED_RETRY_CYCLES = 50000000,
  parameter integer OLED_I2C_HALF_CYCLES = 500,
  parameter integer OLED_I2C_WATCHDOG_CYCLES = 2000000
) (
  input wire clk,
  input wire btn_c,
  input wire [1:0] display_sel,
  input wire spi_miso,
  output wire spi_cs_n,
  output wire spi_sclk,
  output wire spi_mosi,
  output wire uart_tx,
  output wire [15:0] led,
  output wire [3:0] an,
  output wire [6:0] seg,
  output wire dp,
  inout wire oled_scl,
  inout wire oled_sda
);
  wire rst;
  (* ASYNC_REG = "TRUE" *) reg [1:0] display_meta;
  (* ASYNC_REG = "TRUE" *) reg [1:0] display_synced;
  wire spi_start;
  wire [79:0] spi_tx_frame;
  wire spi_busy;
  wire spi_done;
  wire spi_error;
  wire [79:0] spi_rx_frame;
  wire [6:0] spi_rx_bits;
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
  wire uart_busy;
  wire oled_fault;
  wire oled_busy;

  reset_sync u_reset_sync (
    .clk(clk),
    .arst(btn_c),
    .rst(rst)
  );

  always @(posedge clk) begin
    if (rst) begin
      display_meta <= 2'b0;
      display_synced <= 2'b0;
    end else begin
      display_meta <= display_sel;
      display_synced <= display_meta;
    end
  end

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

  sensor_reader #(
    .POLL_CYCLES(POLL_CYCLES),
    .STALE_CYCLES(STALE_CYCLES)
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

  fnd_controller #(
    .DIGIT_CYCLES(DIGIT_CYCLES)
  ) u_fnd_controller (
    .clk(clk),
    .rst(rst),
    .display_sel(display_synced),
    .temperature(temperature),
    .humidity(humidity),
    .distance(distance),
    .sensor_valid(sensor_valid),
    .an(an),
    .seg(seg),
    .dp(dp)
  );

  oled_display #(
    .POWERUP_CYCLES(OLED_POWERUP_CYCLES),
    .RETRY_CYCLES(OLED_RETRY_CYCLES),
    .I2C_HALF_PERIOD_CYCLES(OLED_I2C_HALF_CYCLES),
    .I2C_WATCHDOG_CYCLES(OLED_I2C_WATCHDOG_CYCLES)
  ) u_oled_display (
    .clk(clk),
    .rst(rst),
    .report_update(report_update),
    .temperature(temperature),
    .humidity(humidity),
    .distance(distance),
    .sensor_valid(sensor_valid),
    .link_valid(link_valid),
    .link_stale(link_stale),
    .last_error(last_error),
    .oled_fault(oled_fault),
    .busy(oled_busy),
    .scl(oled_scl),
    .sda(oled_sda)
  );

  uart_reporter #(
    .BIT_CYCLES(UART_BIT_CYCLES)
  ) u_uart_reporter (
    .clk(clk),
    .rst(rst),
    .report_update(report_update),
    .temperature(temperature),
    .humidity(humidity),
    .distance(distance),
    .sensor_valid(sensor_valid),
    .link_valid(link_valid),
    .link_stale(link_stale),
    .last_error(last_error),
    .oled_fault(oled_fault),
    .tx(uart_tx),
    .busy(uart_busy)
  );

  assign led = {link_valid, link_stale, last_error != 3'd0, spi_busy,
      oled_fault, sample_toggle, sensor_valid, debug_rx_byte};
endmodule
