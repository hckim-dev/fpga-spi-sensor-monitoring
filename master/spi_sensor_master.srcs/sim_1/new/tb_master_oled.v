`timescale 1ns / 1ps

module tb_master_oled;
  reg clk = 1'b0;
  reg btn_c = 1'b0;
  reg [1:0] display_sel = 2'b0;
  reg [79:0] reply_frame = 80'h00A50300EB0258012335;
  wire spi_miso;
  wire spi_mosi;
  wire spi_sclk;
  wire spi_cs_n;
  wire tx;
  wire [15:0] led;
  wire [3:0] an;
  wire [6:0] seg;
  wire dp;
  tri1 oled_scl;
  tri1 oled_sda;
  reg oled_present = 1'b1;
  wire received;
  wire [7:0] received_data;
  wire framing_error;
  wire rst = u_spi_sensor_master_top.rst;
  wire spi_start = u_spi_sensor_master_top.spi_start;
  wire uart_busy = u_spi_sensor_master_top.uart_busy;
  wire link_valid = led[15];
  wire link_stale = led[14];

  spi_sensor_master_top #(
      .POLL_CYCLES(100000),
      .STALE_CYCLES(300000),
      .OLED_POWERUP_CYCLES(20),
      .OLED_RETRY_CYCLES(1000),
      .OLED_I2C_HALF_CYCLES(10),
      .OLED_I2C_WATCHDOG_CYCLES(100000)
  ) u_spi_sensor_master_top (
      .clk(clk),
      .btn_c(btn_c),
      .display_sel(display_sel),
      .spi_miso(spi_miso),
      .spi_cs_n(spi_cs_n),
      .spi_sclk(spi_sclk),
      .spi_mosi(spi_mosi),
      .uart_tx(tx),
      .led(led),
      .an(an),
      .seg(seg),
      .dp(dp),
      .oled_scl(oled_scl),
      .oled_sda(oled_sda)
  );
  spi_sensor_peer u_spi_sensor_peer (
      .spi_cs_n(spi_cs_n),
      .spi_sclk(spi_sclk),
      .spi_mosi(spi_mosi),
      .spi_miso(spi_miso),
      .reply_frame(reply_frame),
      .peer_reset(1'b0)
  );
  ssd1306_model u_ssd1306_model (
      .scl(oled_scl),
      .sda(oled_sda),
      .present(oled_present),
      .address(7'h3C),
      .nack_data(1'b0),
      .nack_page(3'd0)
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
  reg previous_sample_toggle = 1'b0;

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
    if (rst) last_start = 0;
    if (!rst && spi_start) begin
      if (last_start != 0) begin
        check(cycles - last_start == 100000, "SPI poll continues every 1ms during UART");
      end
      last_start = cycles;
      frames = frames + 1;
      if (uart_busy) saw_busy_poll = 1'b1;
    end
    if (rst) begin
      line = 0;
      line_length = 0;
    end
    if (!rst && received) begin
      check(!framing_error && line_length < 64, "valid UART framing and bounded line");
      line = {line[503:0], received_data};
      line_length = line_length + 1;
      if (received_data == 8'h0A) begin
        if (line_length > 2) begin
          check(
              line === {"T=--C H=--% D=--cm L=ERR:NONE O=ERR", 8'h0D, 8'h0A} ||
                line === {"T=23.5C H=60.0% D=291cm L=OK O=ERR", 8'h0D, 8'h0A} ||
                line === {"T=23.5C H=60.0% D=291cm L=OK O=OK", 8'h0D, 8'h0A} ||
                line === {"T=--C H=--% D=--cm L=ERR:XOR O=ERR", 8'h0D, 8'h0A} ||
                line === {"T=--C H=--% D=--cm L=ERR:STALE O=ERR", 8'h0D, 8'h0A},
              "every UART line uses one coherent reader snapshot");
          last_line = line;
          lines = lines + 1;
        end
        line = 0;
        line_length = 0;
      end
    end
  end

  always @(posedge clk) begin
    #1;
    if (rst) begin
      previous_sample_toggle = 1'b0;
    end else begin
      if (!spi_cs_n) check(led[12], "busy LED during selected SPI frame");
      if (u_spi_sensor_master_top.spi_done) check(!led[12], "busy LED clears after transport gap");
      if (u_spi_sensor_master_top.report_update) begin
        if (u_spi_sensor_master_top.last_error == 0) begin
          check(led[10] === !previous_sample_toggle, "sample LED toggles only on valid frame");
        end else begin
          check(led[10] === previous_sample_toggle, "error leaves sample LED unchanged");
        end
        previous_sample_toggle = led[10];
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
      check(last_line === expected && lines > before_lines,
            "expected SPI result reported over UART");
      cases = cases + 1;
    end
  endtask

  initial begin
    #1;
    check(rst, "power-on reset");
    expect_line({"T=23.5C H=60.0% D=291cm L=OK O=OK", 8'h0D, 8'h0A});
    check(!led[11] && led[15] && led[9:8] == 3, "OLED success reaches LED and UART");
    check(u_ssd1306_model.frames >= 2 && u_ssd1306_model.ram[128+18] == 8'h42,
          "SPI value reaches OLED RAM as temperature 23.5");
    oled_present = 0;
    wait (led[11]);
    check(led[15] && !led[14] && !led[13] && led[9:8] == 3,
          "OLED NACK does not invalidate SPI sensor record");
    expect_line({"T=23.5C H=60.0% D=291cm L=OK O=ERR", 8'h0D, 8'h0A});
    oled_present = 1;
    expect_line({"T=23.5C H=60.0% D=291cm L=OK O=OK", 8'h0D, 8'h0A});
    check(!led[11] && led[15] && frames > lines && saw_busy_poll,
          "OLED retry and UART output never backpressure SPI");
    check(u_ssd1306_model.failures == 0, "OLED packet checks");
    if (failures == 0) begin
      $display("MASTER_OLED_TEST_PASS cases=%0d spi_frames=%0d oled_frames=%0d uart_lines=%0d",
               cases, frames, u_ssd1306_model.frames, lines);
    end else begin
      $display("MASTER_OLED_TEST_FAIL failures=%0d", failures);
    end
    $finish;
  end

  initial begin
    #60000000;
    $display("MASTER_OLED_TEST_FAIL global timeout");
    $finish;
  end
endmodule
