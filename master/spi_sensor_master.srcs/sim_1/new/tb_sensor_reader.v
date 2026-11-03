`timescale 1ns / 1ps

module tb_sensor_reader;
  localparam integer POLL_CYCLES = 40;
  localparam integer STALE_CYCLES = 200;

  reg clk = 1'b0;
  reg rst = 1'b1;
  wire spi_start;
  wire [79:0] spi_tx_frame;
  reg spi_busy = 1'b1;
  reg spi_done = 1'b0;
  reg spi_error = 1'b0;
  reg [79:0] spi_rx_frame = 80'b0;
  reg [6:0] spi_rx_bits = 7'd0;
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

  always #5 clk = ~clk;

  integer failures = 0;
  integer cases = 0;
  integer cycles = 0;
  integer requests = 0;
  integer reports = 0;
  integer last_request_cycle = 0;
  integer success_cycle = 0;
  reg previous_start = 1'b0;
  reg previous_update = 1'b0;
  reg [55:0] previous_record = 56'b0;
  wire [55:0] record = {temperature, humidity, distance, sensor_valid,
      link_valid, link_stale, last_error, sample_toggle};

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

  // Frame은 Byte 순서대로 조립하고 예상 XOR를 별도로 계산한다.
  function [79:0] packet;
    input [7:0] status;
    input [15:0] temp_value;
    input [15:0] hum_value;
    input [15:0] dist_value;
    reg [71:0] response;
    reg [7:0] checksum;
    integer i;
    begin
      response = {8'hA5, status, temp_value, hum_value, dist_value, 8'h00};
      checksum = 8'b0;
      for (i = 1; i < 9; i = i + 1) begin
        checksum = checksum ^ response[i*8 +: 8];
      end
      packet = {8'h00, response[71:8], checksum};
    end
  endfunction

  always @(posedge clk) begin
    cycles = cycles + 1;
    if (!rst) begin
      check(!(spi_start && previous_start), "start one cycle wide");
      if (spi_start) begin
        check(!spi_busy, "start requires idle SPI");
        check(spi_tx_frame === 80'h01000000000000000000, "fixed READ_SENSORS command");
        requests = requests + 1;
        last_request_cycle = cycles;
      end
    end
    previous_start = spi_start;
    #1;
    if (!rst) begin
      check(!(report_update && previous_update), "report_update one cycle wide");
      if (report_update) begin
        reports = reports + 1;
      end else begin
        check(record === previous_record, "record changes only with report_update");
      end
    end
    previous_update = report_update;
    previous_record = record;
  end

  task tick;
    begin
      @(posedge clk);
      #2;
    end
  endtask

  task reset_reader;
    begin
      @(negedge clk);
      rst = 1'b1;
      spi_busy = 1'b1;
      spi_done = 1'b0;
      tick;
      check(record == 0 && debug_rx_byte == 0 && !report_update && !spi_start,
            "reset clears record and requests");
      @(negedge clk);
      rst = 1'b0;
    end
  endtask

  task request;
    integer limit;
    begin
      @(negedge clk);
      spi_busy = 1'b0;
      #1;
      limit = 0;
      while (!spi_start && limit < POLL_CYCLES + 5) begin
        @(negedge clk);
        limit = limit + 1;
      end
      check(spi_start, "bounded poll request");
      tick;
      @(negedge clk);
      spi_busy = 1'b1;
    end
  endtask

  task complete;
    input [79:0] frame;
    input [6:0] bits;
    input transport_error;
    reg [55:0] before_record;
    begin
      @(negedge clk);
      before_record = record;
      spi_rx_frame = frame;
      spi_rx_bits = bits;
      spi_error = transport_error;
      spi_done = 1'b1;
      tick;
      check(record === before_record && !report_update, "done captures without partial update");
      @(negedge clk);
      spi_done = 1'b0;
      spi_rx_frame = ~frame;
      spi_rx_bits = 7'd0;
      spi_error = !transport_error;
      tick;
      check(report_update, "one atomic report from captured completion");
    end
  endtask

  task good_frame;
    input [79:0] frame;
    input [15:0] expected_temp;
    input [15:0] expected_hum;
    input [15:0] expected_dist;
    input [1:0] expected_valid;
    reg before_toggle;
    begin
      request;
      before_toggle = sample_toggle;
      complete(frame, 7'd80, 1'b0);
      check(temperature === expected_temp && humidity === expected_hum && distance === expected_dist,
            "decoded values and signed temperature match");
      check(sensor_valid === expected_valid && link_valid && !link_stale && last_error == 0,
            "valid frame updates link and sensor validity");
      check(sample_toggle !== before_toggle, "every good frame toggles sample");
      check(debug_rx_byte === frame[15:8], "complete frame debug byte");
      success_cycle = cycles;
      cases = cases + 1;
    end
  endtask

  task bad_frame;
    input [79:0] frame;
    input [6:0] bits;
    input transport_error;
    input [2:0] expected_error;
    reg [47:0] before_values;
    reg before_toggle;
    reg [7:0] before_debug;
    begin
      request;
      before_values = {temperature, humidity, distance};
      before_toggle = sample_toggle;
      before_debug = debug_rx_byte;
      complete(frame, bits, transport_error);
      check(last_error === expected_error && !link_valid && sensor_valid == 0,
            "error priority and invalidation");
      check({temperature, humidity, distance} === before_values && sample_toggle === before_toggle,
            "bad frame preserves values and sample toggle");
      if (bits == 80) begin
        check(debug_rx_byte === frame[15:8], "complete bad frame updates raw debug");
      end else begin
        check(debug_rx_byte === before_debug, "partial result preserves debug byte");
      end
      cases = cases + 1;
    end
  endtask

  integer before_requests;
  integer before_reports;
  integer first_request;
  reg [79:0] corrupt;
  initial begin
    $timeformat(-9, 0, "ns", 12);
    reset_reader;
    repeat (10) tick;
    check(requests == 0 && !spi_start, "initial SPI gap blocks first request");

    good_frame(80'h00A50300EB0258012335, 235, 600, 291, 2'b11);
    first_request = last_request_cycle;
    good_frame(80'h00A503FFC901C4007B2E, -16'sd55, 452, 123, 2'b11);
    check(last_request_cycle - first_request == POLL_CYCLES, "poll period starts at acceptance");
    good_frame(80'h00A500000000000000A5, 0, 0, 0, 2'b00);
    good_frame(80'h00A50200EB0258012334, 235, 600, 291, 2'b10);
    good_frame(80'h00A50100EB0258012337, 235, 600, 291, 2'b01);
    good_frame(80'h00A503000000000002A4, 0, 0, 2, 2'b11);
    good_frame(80'h00A503025803E8019086, 600, 1000, 400, 2'b11);
    good_frame(80'h00A503FF380000000263, -16'sd200, 0, 2, 2'b11);
    good_frame(packet(0, 16'hFFFF, 16'hFFFF, 16'hFFFF), 16'hFFFF, 16'hFFFF, 16'hFFFF, 0);
    good_frame(packet(1, 235, 600, 16'hFFFF), 235, 600, 16'hFFFF, 1);
    good_frame(packet(2, 16'h8000, 16'hFFFF, 2), 16'h8000, 16'hFFFF, 2, 2);
    good_frame(80'hFFA50300EB0258012335, 235, 600, 291, 3);

    bad_frame(80'h00A50300EA0258012335, 80, 0, 4);
    bad_frame(80'h00A50300EB03E9012385, 80, 0, 6);
    bad_frame(80'h00A50700EB0258012331, 80, 0, 5);
    bad_frame(80'b0, 80, 0, 3);
    bad_frame({80{1'b1}}, 80, 0, 3);
    bad_frame(80'b0, 37, 1, 1);
    bad_frame(80'b0, 37, 0, 2);
    bad_frame(80'b0, 79, 0, 2);
    bad_frame(80'b0, 81, 0, 2);
    bad_frame(80'b0, 0, 0, 2);
    bad_frame(80'b0, 127, 0, 2);
    bad_frame(packet(3, -16'sd201, 0, 2), 80, 0, 6);
    bad_frame(packet(3, 601, 0, 2), 80, 0, 6);
    bad_frame(packet(3, 16'h8000, 0, 2), 80, 0, 6);
    bad_frame(packet(3, 0, 1001, 2), 80, 0, 6);
    bad_frame(packet(3, 0, 0, 1), 80, 0, 6);
    bad_frame(packet(3, 0, 0, 401), 80, 0, 6);
    bad_frame(80'b0, 80, 1, 1);
    corrupt = packet(7, 601, 1001, 401) ^ 80'h01;
    bad_frame(corrupt, 80, 0, 4);
    bad_frame(packet(7, 601, 1001, 401), 80, 0, 5);
    good_frame(80'h00A50300EB0258012335, 235, 600, 291, 3);

    // Poll 만료 중 Busy가 길어져도 한 요청만 남기고 새 주기를 시작한다.
    before_requests = requests;
    repeat (POLL_CYCLES * 3) tick;
    check(requests == before_requests && !spi_start, "busy poll does not queue requests");
    request;
    first_request = last_request_cycle;
    complete(80'h00A50300EB0258012335, 80, 0);
    request;
    check(last_request_cycle - first_request == POLL_CYCLES, "delayed request restarts poll timer");
    complete(80'h00A50300EB0258012335, 80, 0);
    cases = cases + 1;

    // 성공 반영 Edge부터 정확히 STALE_CYCLES를 센다.
    success_cycle = cycles;
    before_reports = reports;
    repeat (STALE_CYCLES - 1) tick;
    check(!link_stale && link_valid && reports == before_reports, "fresh immediately before stale boundary");
    tick;
    check(link_stale && !link_valid && sensor_valid == 0 && last_error == 7 && report_update,
          "exact stale boundary invalidates once");
    repeat (STALE_CYCLES * 3) tick;
    check(link_stale && reports == before_reports + 1, "saturated age does not wrap or repeat update");
    good_frame(80'h00A50300EB0258012335, 235, 600, 291, 3);
    cases = cases + 1;

    // Stale 경계와 같은 Edge의 성공은 정상 수신으로, 오류는 오류 이유로 반영한다.
    request;
    while (cycles < success_cycle + STALE_CYCLES - 2) tick;
    complete(80'h00A503FFC901C4007B2E, 80, 0);
    check(cycles == success_cycle + STALE_CYCLES && !link_stale && link_valid && last_error == 0,
          "success wins at exact stale boundary");
    success_cycle = cycles;
    request;
    while (cycles < success_cycle + STALE_CYCLES - 2) tick;
    complete(80'b0, 80, 0);
    check(cycles == success_cycle + STALE_CYCLES && link_stale && !link_valid && last_error == 3,
          "frame error keeps age moving and preserves reason at stale boundary");
    cases = cases + 1;

    good_frame(80'h00A50300EB0258012335, 235, 600, 291, 3);
    bad_frame(80'b0, 80, 0, 3);
    bad_frame(80'b0, 37, 1, 1);
    bad_frame(80'h00A50300EA0258012335, 80, 0, 4);
    while (cycles < success_cycle + STALE_CYCLES - 1) tick;
    check(!link_stale, "repeated errors do not advance stale boundary");
    tick;
    check(link_stale && report_update && last_error == 7,
          "repeated errors cannot postpone stale boundary");
    cases = cases + 1;

    reset_reader;
    repeat (STALE_CYCLES - 1) tick;
    check(!link_stale && last_error == 0, "startup before stale has no error");
    tick;
    check(link_stale && last_error == 7, "startup with no success becomes stale");
    cases = cases + 1;

    // WAIT_TRANSFER와 CHECK_FRAME의 Reset은 받은 결과를 폐기한다.
    reset_reader;
    request;
    reset_reader;
    check(!report_update && !link_valid, "reset cancels transfer");
    request;
    @(negedge clk);
    spi_done = 1'b1;
    spi_rx_frame = 80'h00A50300EB0258012335;
    spi_rx_bits = 80;
    spi_error = 0;
    tick;
    reset_reader;
    repeat (3) tick;
    check(!report_update && temperature == 0 && !link_valid, "reset discards captured frame");
    good_frame(80'h00A50300EB0258012335, 235, 600, 291, 3);
    cases = cases + 1;

    // 보류 요청이 없는 완료 신호는 상태를 바꾸지 않는다.
    before_reports = reports;
    @(negedge clk);
    spi_done = 1'b1;
    repeat (3) tick;
    @(negedge clk);
    spi_done = 1'b0;
    check(reports == before_reports, "unsolicited done ignored");
    cases = cases + 1;

    if (failures == 0) begin
      $display("SENSOR_READER_TEST_PASS cases=%0d requests=%0d reports=%0d", cases, requests, reports);
    end else begin
      $display("SENSOR_READER_TEST_FAIL failures=%0d", failures);
    end
    $finish;
  end

  initial begin
    #1000000;
    $display("SENSOR_READER_TEST_FAIL global timeout");
    $finish;
  end
endmodule
