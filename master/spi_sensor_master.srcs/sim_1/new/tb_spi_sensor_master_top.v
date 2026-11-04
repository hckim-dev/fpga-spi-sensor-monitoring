`timescale 1ns / 1ps

module tb_spi_sensor_master_top;
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
  wire received;
  wire [7:0] received_data;
  wire framing_error;
  wire rst = u_spi_sensor_master_top.rst;
  wire spi_start = u_spi_sensor_master_top.spi_start;
  wire uart_busy = u_spi_sensor_master_top.uart_busy;
  wire link_valid = led[15];
  wire link_stale = led[14];

  spi_sensor_master_top #(
      .POLL_CYCLES (100000),
      .STALE_CYCLES(300000)
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
                line === {"T=-5.5C H=45.2% D=123cm L=OK O=ERR", 8'h0D, 8'h0A} ||
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

  function [6:0] expected_segment;
    input [3:0] digit;
    begin
      case (digit)
        0: expected_segment = 7'b1000000;
        1: expected_segment = 7'b1111001;
        2: expected_segment = 7'b0100100;
        3: expected_segment = 7'b0110000;
        4: expected_segment = 7'b0011001;
        5: expected_segment = 7'b0010010;
        6: expected_segment = 7'b0000010;
        7: expected_segment = 7'b1111000;
        8: expected_segment = 7'b0000000;
        9: expected_segment = 7'b0010000;
        11: expected_segment = 7'b0111111;
        default: expected_segment = 7'b1111111;
      endcase
    end
  endfunction

  task expect_display;
    input [15:0] digits;
    input [3:0] points;
    integer index;
    begin
      repeat (100005) @(posedge clk);
      @(negedge an[0]);
      #2;
      for (index = 0; index < 4; index = index + 1) begin
        if (index != 0) begin
          @(negedge an[index]);
          #2;
        end
        check(seg === expected_segment(digits[index*4+:4]) && dp === !points[index],
              "top-level FND glyph and decimal point");
      end
      cases = cases + 1;
    end
  endtask

  time released_at;
  initial begin
    #1;
    check(rst, "power-on reset without external button");
    @(posedge clk);
    #2;
    check(spi_cs_n && !spi_sclk && !spi_mosi && tx && an == 15 && seg == 127 && dp,
          "power-on safe peripheral outputs");
    check(!led[15] && !led[14] && !led[13] && led[12] && led[11] && led[9:0] == 0,
          "initial LED map and OLED unavailable status");
    expect_line({"T=23.5C H=60.0% D=291cm L=OK O=ERR", 8'h0D, 8'h0A});
    check(led[15] && !led[14] && !led[13] && led[11] && led[9:8] == 3 && led[7:0] == 8'h23,
          "normal SPI result reaches debug LEDs");
    expect_display(16'hA235, 2);
    @(negedge clk);
    #2;
    display_sel = 2;
    @(posedge clk);
    #1;
    check(u_spi_sensor_master_top.display_synced == 0, "selection waits first synchronizer edge");
    @(posedge clk);
    #1;
    check(u_spi_sensor_master_top.display_synced == 2, "selection releases after second edge");
    expect_display(16'hA291, 0);
    display_sel = 1;
    expect_display(16'hA600, 2);
    reply_frame = 80'h00A503FFC901C4007B2E;
    display_sel = 0;
    expect_line({"T=-5.5C H=45.2% D=123cm L=OK O=ERR", 8'h0D, 8'h0A});
    expect_display(16'hAB55, 2);
    reply_frame = 80'h00A50300EA0258012335;
    expect_line({"T=--C H=--% D=--cm L=ERR:XOR O=ERR", 8'h0D, 8'h0A});
    check(led[14] && led[13] && !led[15] && led[9:8] == 0 && led[7:0] == 8'h23,
          "error and stale invalidate LEDs while retaining raw debug byte");
    expect_display(16'hBBBB, 0);

    // SCLK High에서 누른 버튼은 모든 모듈을 공통 Reset으로 취소한다.
    @(negedge spi_cs_n);
    @(posedge spi_sclk);
    #1002;
    btn_c = 1;
    @(posedge clk);
    #2;
    check(rst && spi_cs_n && !spi_sclk && !spi_mosi && tx && an == 15 && seg == 127 && dp,
          "button reset cancels SPI, UART and FND together");
    check(led[15:13] == 0 && led[9:0] == 0, "button reset clears link and debug record");
    @(negedge clk);
    #2;
    btn_c = 0;
    @(posedge clk);
    #1;
    check(rst, "button release remains reset after first edge");
    @(posedge clk);
    #1;
    check(!rst, "button release after second edge");
    released_at = $time;
    reply_frame = 80'h00A50300EB0258012335;
    @(negedge spi_cs_n);
    check($time - released_at >= 10000, "reset recovery preserves SPI high gap");
    expect_line({"T=23.5C H=60.0% D=291cm L=OK O=ERR", 8'h0D, 8'h0A});
    expect_display(16'hA235, 2);
    check(link_valid && !link_stale && saw_busy_poll, "top recovers while outputs keep polling");
    if (failures == 0) begin
      $display("MASTER_TOP_TEST_PASS cases=%0d frames=%0d lines=%0d", cases, frames, lines);
    end else begin
      $display("MASTER_TOP_TEST_FAIL failures=%0d", failures);
    end
    $finish;
  end

  initial begin
    #100000000;
    $display("MASTER_TOP_TEST_FAIL global timeout");
    $finish;
  end
endmodule
