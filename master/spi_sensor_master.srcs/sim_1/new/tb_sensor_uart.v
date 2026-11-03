`timescale 1ns / 1ps

module tb_sensor_uart;
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

  wire tx;
  wire uart_busy;
  wire received;
  wire [7:0] received_data;
  wire framing_error;
  uart_reporter u_uart_reporter (
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
    .oled_fault(1'b0),
    .tx(tx),
    .busy(uart_busy)
  );
  uart_rx_model u_uart_rx_model (
    .clk(clk),
    .rst(rst),
    .rx(tx),
    .valid(received),
    .data(received_data),
    .framing_error(framing_error)
  );
  always #5 clk = ~clk;
  integer failures = 0;
  integer cases = 0;
  integer frames = 0;
  integer cycles = 0;
  integer last_start = 0;
  integer lines = 0;
  integer line_length = 0;
  reg [511:0] line = 512'b0;
  reg [511:0] last_line = 512'b0;
  reg saw_busy_poll = 1'b0;

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

  always @(posedge clk) begin
    cycles = cycles + 1;
    if (!rst && spi_start) begin
      if (last_start != 0) begin
        check(cycles - last_start == 100000, "SPI poll continues every 1ms during UART");
      end
      last_start = cycles;
      frames = frames + 1;
      if (uart_busy) saw_busy_poll = 1'b1;
    end
    if (!rst && received) begin
      check(!framing_error && line_length < 64, "valid UART framing and bounded line");
      line = {line[503:0], received_data};
      line_length = line_length + 1;
      if (received_data == 8'h0A) begin
        if (line_length > 2) begin
          check(line === {"T=23.5C H=60.0% D=291cm L=OK O=OK", 8'h0D, 8'h0A} ||
                line === {"T=-5.5C H=45.2% D=123cm L=OK O=OK", 8'h0D, 8'h0A} ||
                line === {"T=--C H=--% D=--cm L=ERR:XOR O=OK", 8'h0D, 8'h0A} ||
                line === {"T=--C H=--% D=--cm L=ERR:STALE O=OK", 8'h0D, 8'h0A},
                "every UART line uses one coherent reader snapshot");
          last_line = line;
          lines = lines + 1;
        end
        line = 0;
        line_length = 0;
      end
    end
  end

  task expect_line;
    input [511:0] expected;
    integer timeout;
    integer before_lines;
    begin
      before_lines = lines;
      timeout = 0;
      while ((lines == before_lines || last_line !== expected) && timeout < 2000000) begin
        @(posedge clk);
        #2;
        timeout = timeout + 1;
      end
      check(last_line === expected && lines > before_lines, "expected SPI result reported over UART");
      cases = cases + 1;
    end
  endtask

  initial begin
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 0;
    expect_line({"T=23.5C H=60.0% D=291cm L=OK O=OK", 8'h0D, 8'h0A});
    reply_frame = 80'h00A503FFC901C4007B2E;
    expect_line({"T=-5.5C H=45.2% D=123cm L=OK O=OK", 8'h0D, 8'h0A});
    reply_frame = 80'h00A50300EA0258012335;
    expect_line({"T=--C H=--% D=--cm L=ERR:XOR O=OK", 8'h0D, 8'h0A});
    check(link_stale && !link_valid, "errors still reach stale while UART drains messages");
    reply_frame = 80'h00A50300EB0258012335;
    expect_line({"T=23.5C H=60.0% D=291cm L=OK O=OK", 8'h0D, 8'h0A});
    check(link_valid && !link_stale && saw_busy_poll && frames > lines,
          "UART preserves latest state without backpressure to SPI");
    if (failures == 0) begin
      $display("SENSOR_UART_TEST_PASS cases=%0d frames=%0d lines=%0d", cases, frames, lines);
    end else begin
      $display("SENSOR_UART_TEST_FAIL failures=%0d", failures);
    end
    $finish;
  end

  initial begin
    #80000000;
    $display("SENSOR_UART_TEST_FAIL global timeout");
    $finish;
  end
endmodule
