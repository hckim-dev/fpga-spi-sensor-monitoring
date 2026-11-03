`timescale 1ns / 1ps

module tb_uart_reporter;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg receiver_rst = 1'b1;
  reg report_update = 1'b0;
  reg signed [15:0] temperature = 235;
  reg [15:0] humidity = 600;
  reg [15:0] distance = 291;
  reg [1:0] sensor_valid = 3;
  reg link_valid = 1'b1;
  reg link_stale = 1'b0;
  reg [2:0] last_error = 0;
  reg oled_fault = 1'b0;
  wire tx;
  wire busy;
  wire received;
  wire [7:0] received_data;
  wire framing_error;
  integer failures = 0;
  integer cases = 0;
  integer count = 0;
  integer consumed = 0;
  reg [7:0] bytes [0:4095];

  uart_reporter #(
    .BIT_CYCLES(8)
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
    .tx(tx),
    .busy(busy)
  );
  uart_rx_model #(
    .BIT_CYCLES(8)
  ) u_uart_rx_model (
    .clk(clk),
    .rst(receiver_rst),
    .rx(tx),
    .valid(received),
    .data(received_data),
    .framing_error(framing_error)
  );
  always #5 clk = ~clk;

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
    if (!rst && busy) begin
      check(u_uart_reporter.message_length <= 64, "line fits 64 bytes");
    end
    if (rst) begin
      count = 0;
    end else if (received) begin
      check(!framing_error && count < 4096, "valid received UART byte");
      bytes[count] = received_data;
      count = count + 1;
    end
  end

  task update;
    begin
      @(negedge clk);
      report_update = 1;
      @(negedge clk);
      report_update = 0;
    end
  endtask

  task expect_text;
    input [511:0] text;
    integer length;
    integer i;
    integer timeout;
    begin
      length = 0;
      for (i = 0; i < 64; i = i + 1) begin
        if (text[i*8 +: 8] != 0) length = i + 1;
      end
      timeout = 0;
      while (count < consumed + length && timeout < 100000) begin
        @(posedge clk);
        #2;
        timeout = timeout + 1;
      end
      check(count >= consumed + length, "bounded report completion");
      for (i = 0; i < length; i = i + 1) begin
        if (bytes[consumed+i] !== text[(length-1-i)*8 +: 8]) begin
          $display("BYTE_MISMATCH offset=%0d actual=%h expected=%h", i,
              bytes[consumed+i], text[(length-1-i)*8 +: 8]);
          check(0, "exact report text");
        end
      end
      consumed = consumed + length;
      cases = cases + 1;
    end
  endtask

  task wait_idle;
    begin
      wait (!busy);
      repeat (200) @(posedge clk);
      #2;
      check(count == consumed, "only latest pending report emitted");
    end
  endtask

  integer reason;
  initial begin
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 0;
    receiver_rst = 0;
    update;
    repeat (50) @(posedge clk);
    temperature = -55;
    humidity = 452;
    distance = 123;
    update;
    temperature = -200;
    humidity = 1000;
    distance = 400;
    update;
    @(negedge clk);
    oled_fault = 1;
    expect_text({8'h0D, 8'h0A, "T=23.5C H=60.0% D=291cm L=OK O=OK", 8'h0D, 8'h0A});
    expect_text({"T=-20.0C H=100.0% D=400cm L=OK O=ERR", 8'h0D, 8'h0A});
    wait_idle;
    @(negedge clk);
    oled_fault = 0;
    expect_text({"T=-20.0C H=100.0% D=400cm L=OK O=OK", 8'h0D, 8'h0A});
    wait_idle;

    sensor_valid = 1;
    update;
    expect_text({"T=-20.0C H=100.0% D=--cm L=OK O=OK", 8'h0D, 8'h0A});
    wait_idle;
    sensor_valid = 2;
    update;
    expect_text({"T=--C H=--% D=400cm L=OK O=OK", 8'h0D, 8'h0A});
    wait_idle;

    sensor_valid = 0;
    update;
    expect_text({"T=--C H=--% D=--cm L=OK O=OK", 8'h0D, 8'h0A});
    wait_idle;
    link_valid = 0;
    for (reason = 0; reason < 8; reason = reason + 1) begin
      last_error = reason[2:0];
      link_stale = reason == 7;
      update;
      case (reason)
        0: expect_text({"T=--C H=--% D=--cm L=ERR:NONE O=OK", 8'h0D, 8'h0A});
        1: expect_text({"T=--C H=--% D=--cm L=ERR:TIMEOUT O=OK", 8'h0D, 8'h0A});
        2: expect_text({"T=--C H=--% D=--cm L=ERR:LENGTH O=OK", 8'h0D, 8'h0A});
        3: expect_text({"T=--C H=--% D=--cm L=ERR:HEADER O=OK", 8'h0D, 8'h0A});
        4: expect_text({"T=--C H=--% D=--cm L=ERR:XOR O=OK", 8'h0D, 8'h0A});
        5: expect_text({"T=--C H=--% D=--cm L=ERR:RESERVED O=OK", 8'h0D, 8'h0A});
        6: expect_text({"T=--C H=--% D=--cm L=ERR:RANGE O=OK", 8'h0D, 8'h0A});
        7: expect_text({"T=--C H=--% D=--cm L=ERR:STALE O=OK", 8'h0D, 8'h0A});
      endcase
      wait_idle;
    end

    sensor_valid = 3;
    link_valid = 1;
    link_stale = 0;
    last_error = 0;
    temperature = 0;
    humidity = 0;
    distance = 2;
    update;
    temperature = 600;
    humidity = 1000;
    distance = 400;
    update;
    wait (!busy && u_uart_reporter.pending_valid);
    temperature = -1;
    humidity = 1;
    distance = 10;
    update;
    expect_text({"T=0.0C H=0.0% D=2cm L=OK O=OK", 8'h0D, 8'h0A});
    expect_text({"T=-0.1C H=0.1% D=10cm L=OK O=OK", 8'h0D, 8'h0A});
    wait_idle;

    temperature = 600;
    humidity = 1000;
    distance = 400;
    update;
    expect_text({"T=60.0C H=100.0% D=400cm L=OK O=OK", 8'h0D, 8'h0A});
    wait_idle;
    temperature = -200;
    last_error = 5;
    link_valid = 0;
    @(negedge clk);
    oled_fault = 1;
    expect_text({"T=-20.0C H=100.0% D=400cm L=ERR:RESERVED O=ERR", 8'h0D, 8'h0A});
    wait_idle;
    last_error = 0;
    link_valid = 1;
    @(negedge clk);
    oled_fault = 0;
    expect_text({"T=-20.0C H=100.0% D=400cm L=OK O=OK", 8'h0D, 8'h0A});
    wait_idle;
    temperature = -1;
    humidity = 1;
    distance = 10;

    update;
    temperature = 235;
    update;
    repeat (100) @(posedge clk);
    @(negedge clk);
    rst = 1;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 0;
    consumed = 0;
    repeat (1000) @(posedge clk);
    check(!busy && tx, "reset cancels current and pending reports");
    consumed = count;
    update;
    expect_text({8'h0D, 8'h0A, "T=23.5C H=0.1% D=10cm L=OK O=OK", 8'h0D, 8'h0A});
    wait_idle;

    // 수신기는 Reset하지 않고 즉시 새 갱신을 주어 Quiet 구간과 CRLF를 검사한다.
    update;
    repeat (20) @(posedge clk);
    @(negedge clk);
    rst = 1;
    oled_fault = 1;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 0;
    wait (u_uart_reporter.recovery_count == 0);
    #2;
    consumed = count;
    expect_text({8'h0D, 8'h0A, "T=23.5C H=0.1% D=10cm L=OK O=ERR", 8'h0D, 8'h0A});
    wait_idle;

    if (failures == 0) begin
      $display("UART_REPORTER_TEST_PASS cases=%0d", cases);
    end else begin
      $display("UART_REPORTER_TEST_FAIL failures=%0d", failures);
    end
    $finish;
  end

  initial begin
    #2000000;
    $display("UART_REPORTER_TEST_FAIL global timeout");
    $finish;
  end
endmodule
