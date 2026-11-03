`timescale 1ns / 1ps

module tb_sensor_transaction;
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

  always #5 clk = ~clk;

  integer failures = 0;
  integer cases = 0;
  integer rises = 0;
  integer falls = 0;
  integer reports = 0;
  reg [79:0] captured_tx = 80'b0;
  reg abort_expected = 1'b0;
  time cs_end = 0;
  reg saw_cs_end = 1'b0;

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

  always @(negedge spi_cs_n) begin
    if (!rst) begin
      if (saw_cs_end) begin
        check($time - cs_end >= 10000, "repeated transaction high gap");
      end
      rises = 0;
      falls = 0;
      captured_tx = 80'b0;
    end
  end

  always @(posedge spi_sclk) begin
    if (!spi_cs_n) begin
      rises = rises + 1;
      captured_tx = {captured_tx[78:0], spi_mosi};
    end
  end

  always @(negedge spi_sclk) begin
    if (!spi_cs_n) begin
      falls = falls + 1;
    end
  end

  always @(posedge spi_cs_n) begin
    cs_end = $time;
    saw_cs_end = 1'b1;
    if (!rst && !abort_expected) begin
      check(rises == 80 && falls == 80, "transaction has 80 complete SPI cycles");
      check(captured_tx === 80'h01000000000000000000, "wire command and dummy bytes");
    end
  end

  always @(posedge clk) begin
    #1;
    if (!rst && report_update) begin
      reports = reports + 1;
      if (last_error != 3'd7) begin
        check(spi_cs_n && !spi_busy, "frame commits after transport and high gap");
      end
    end
  end

  task wait_report;
    integer limit;
    begin
      @(posedge clk);
      #2;
      limit = 0;
      while ((!report_update || last_error == 3'd7) && limit < 400000) begin
        @(posedge clk);
        #2;
        limit = limit + 1;
      end
      check(report_update && last_error != 3'd7, "bounded transaction report");
    end
  endtask

  task expect_good;
    input [79:0] frame;
    begin
      wait_report;
      check(link_valid && !link_stale && last_error == 0, "normal transaction link state");
      check({temperature, humidity, distance, sensor_valid} === {frame[55:8], frame[57:56]},
            "wire frame decoded atomically");
      cases = cases + 1;
    end
  endtask

  task expect_bad;
    input [2:0] reason;
    reg [47:0] before_values;
    begin
      before_values = {temperature, humidity, distance};
      wait_report;
      check(!link_valid && sensor_valid == 0 && last_error === reason,
            "bad transaction rejected with expected reason");
      check({temperature, humidity, distance} === before_values, "bad transaction preserves values");
      cases = cases + 1;
    end
  endtask

  task reset_master;
    begin
      @(negedge clk);
      rst = 1'b1;
      repeat (3) @(posedge clk);
      @(negedge clk);
      rst = 1'b0;
    end
  endtask

  integer reports_before;
  initial begin
    $timeformat(-9, 0, "ns", 12);
    reset_master;
    expect_good(80'h00A50300EB0258012335);
    reply_frame = 80'h00A503FFC901C4007B2E;
    expect_good(80'h00A503FFC901C4007B2E);
    reply_frame = 80'h00A500000000000000A5;
    expect_good(80'h00A500000000000000A5);
    reply_frame = 80'h00A50200EB0258012334;
    expect_good(80'h00A50200EB0258012334);
    reply_frame = 80'h00A50100EB0258012337;
    expect_good(80'h00A50100EB0258012337);
    reply_frame = 80'h00A503000000000002A4;
    expect_good(80'h00A503000000000002A4);
    reply_frame = 80'h00A503025803E8019086;
    expect_good(80'h00A503025803E8019086);
    reply_frame = 80'h00A503FF380000000263;
    expect_good(80'h00A503FF380000000263);

    // 응답 원본을 전송 중 바꿔도 현재 응답과 다음 응답이 섞이지 않는다.
    reply_frame = 80'h00A50300EB0258012335;
    @(negedge spi_cs_n);
    wait (rises == 20);
    reply_frame = 80'h00A503FFC901C4007B2E;
    expect_good(80'h00A50300EB0258012335);
    expect_good(80'h00A503FFC901C4007B2E);
    reply_frame = 80'h00A50300EA0258012335;
    expect_bad(4);
    reply_frame = 80'h00A50300EB03E9012385;
    expect_bad(6);
    reply_frame = 80'h00A50700EB0258012331;
    expect_bad(5);
    reply_frame = 80'b0;
    expect_bad(3);
    reply_frame = {80{1'b1}};
    force spi_miso = 1'b1;
    expect_bad(3);
    release spi_miso;
    reply_frame = 80'h00A50300EB0258012335;
    expect_good(80'h00A50300EB0258012335);

    // Header 전의 상대 Reset은 오류로 처리하고 다음 초기 응답을 수락한다.
    @(negedge spi_cs_n);
    wait (rises == 4);
    peer_reset = 1'b1;
    expect_bad(3);
    peer_reset = 1'b0;
    reply_frame = 80'h00A500000000000000A5;
    expect_good(80'h00A500000000000000A5);

    // 부분 전송과 SCLK High Reset은 결과를 알리지 않고 새 요청으로 복구한다.
    reply_frame = 80'h00A50300EB0258012335;
    @(negedge spi_cs_n);
    wait (falls == 37);
    abort_expected = 1'b1;
    reports_before = reports;
    reset_master;
    check(reports == reports_before && !link_valid, "37-clock reset discards partial transaction");
    abort_expected = 1'b0;
    expect_good(80'h00A50300EB0258012335);
    @(negedge spi_cs_n);
    wait (rises == 20);
    #1000;
    abort_expected = 1'b1;
    reports_before = reports;
    reset_master;
    check(reports == reports_before && !link_valid, "high-phase reset cancels without report");
    abort_expected = 1'b0;
    expect_good(80'h00A50300EB0258012335);

    // 실제 Core의 독립 Watchdog를 통과한 오류도 Reader가 폐기해야 한다.
    @(negedge spi_cs_n);
    wait (rises == 12);
    #1000;
    abort_expected = 1'b1;
    force u_spi_master.phase_count = 0;
    wait (spi_cs_n);
    release u_spi_master.phase_count;
    expect_bad(1);
    abort_expected = 1'b0;
    expect_good(80'h00A50300EB0258012335);

    if (failures == 0) begin
      $display("SENSOR_TRANSACTION_TEST_PASS cases=%0d reports=%0d", cases, reports);
    end else begin
      $display("SENSOR_TRANSACTION_TEST_FAIL failures=%0d", failures);
    end
    $finish;
  end

  initial begin
    #40000000;
    $display("SENSOR_TRANSACTION_TEST_FAIL global timeout");
    $finish;
  end
endmodule
