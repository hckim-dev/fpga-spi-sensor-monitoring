`timescale 1ns / 1ps

module tb_spi_master;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg start = 1'b0;
  reg [79:0] tx_frame = 80'b0;
  wire busy, done, error;
  wire [79:0] rx_frame;
  wire [ 6:0] rx_bits;
  wire spi_cs_n, spi_sclk, spi_mosi, spi_miso;

  spi_master u_spi_master (
      .clk(clk),
      .rst(rst),
      .start(start),
      .tx_frame(tx_frame),
      .busy(busy),
      .done(done),
      .error(error),
      .rx_frame(rx_frame),
      .rx_bits(rx_bits),
      .spi_cs_n(spi_cs_n),
      .spi_sclk(spi_sclk),
      .spi_mosi(spi_mosi),
      .spi_miso(spi_miso)
  );
  always #5 clk = ~clk;

  // 센서 수집 없이 직렬 응답만 만드는 비합성 모델이다.
  reg [79:0] slave_frame = 80'b0;
  reg [79:0] expected_mosi = 80'b0;
  reg [79:0] captured_mosi = 80'b0;
  reg slave_miso = 1'b0;
  integer miso_delay_ns = 0;
  integer rises = 0, falls = 0;
  reg model_active = 1'b0;
  reg expect_abort = 1'b0;
  reg saw_cs_end = 1'b0;
  time cs_begin = 0, cs_end = 0, last_rise = 0, last_fall = 0;
  assign spi_miso = spi_cs_n ? 1'bz : slave_miso;

  integer failures = 0, cases = 0;
  integer accepted = 0, completed = 0, cancelled = 0;
  integer request_completed_before = 0;
  reg outstanding = 1'b0;
  reg previous_done = 1'b0;
  reg stable_result = 1'b0;
  reg [79:0] saved_rx = 80'b0;
  reg [6:0] saved_bits = 7'd0;
  reg saved_error = 1'b0;

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
      if (saw_cs_end) check($time - cs_end >= 10000, "CS high gap >= 10us");
      check(spi_sclk === 1'b0, "SCLK idle low at selection");
      model_active = 1'b1;
      rises = 0;
      falls = 0;
      captured_mosi = 80'b0;
      cs_begin = $time;
      slave_miso <= #(miso_delay_ns) slave_frame[79];
    end
  end

  always @(posedge spi_sclk) begin
    if (model_active && !spi_cs_n) begin
      if (!expect_abort) begin
        if (rises == 0) check($time - cs_begin == 5000, "CS setup exactly 5us");
        else check($time - last_fall == 5000, "SCLK low exactly 5us; no byte pause");
      end
      rises = rises + 1;
      check(rises <= 80, "no extra rising edge");
      captured_mosi = {captured_mosi[78:0], spi_mosi};
      last_rise = $time;
    end
  end

  always @(negedge spi_sclk) begin
    if (model_active && !spi_cs_n) begin
      if (!expect_abort) check($time - last_rise == 5000, "SCLK high exactly 5us");
      falls = falls + 1;
      last_fall = $time;
      if (rises < 80) slave_miso <= #(miso_delay_ns) slave_frame[79-rises];
      else slave_miso <= #(miso_delay_ns) 1'b0;
    end
  end

  always @(posedge spi_cs_n) begin
    if (model_active) begin
      model_active = 1'b0;
      cs_end = $time;
      saw_cs_end = 1'b1;
      if (!expect_abort) begin
        check(rises == 80 && falls == 80, "80 complete clock cycles per frame");
        check($time - last_fall == 5000, "CS hold exactly 5us");
        check(captured_mosi === expected_mosi, "MSB-first MOSI and latched request");
        check($time - cs_begin == 805000, "normal selected duration 805us");
      end
    end
  end

  // 수락은 Clock Edge에서, 완료는 Non-blocking 반영 후 검사한다.
  always @(posedge clk) begin
    if (rst) begin
      outstanding   = 1'b0;
      stable_result = 1'b0;
    end else if (start && !busy) begin
      accepted = accepted + 1;
      check(!outstanding, "only one outstanding request");
      outstanding   = 1'b1;
      stable_result = 1'b0;
    end
    #1;
    if (rst) begin
      check(!done, "reset does not complete a request");
    end else begin
      check(!(done && previous_done), "done is one clock wide");
      if (done) begin
        check(outstanding, "done requires an accepted request");
        check(!busy && spi_cs_n && !spi_sclk, "done only after returning idle");
        check($time - cs_end >= 10000, "completion after CS high gap");
        completed = completed + 1;
        outstanding = 1'b0;
        stable_result = 1'b1;
        saved_rx = rx_frame;
        saved_bits = rx_bits;
        saved_error = error;
      end else if (stable_result) begin
        check(rx_frame === saved_rx && rx_bits === saved_bits && error === saved_error,
              "completed result stable until next accepted request");
      end
    end
    previous_done = done;
  end

  task wait_idle;
    integer cycles;
    begin
      cycles = 0;
      while (busy !== 1'b0 && cycles < 250000) begin
        @(posedge clk);
        #2;
        cycles = cycles + 1;
      end
      check(!busy, "bounded return to idle");
    end
  endtask

  task reset_core;
    integer before_reset;
    begin
      expect_abort = 1'b1;
      before_reset = completed;
      @(negedge clk);
      rst   = 1'b1;
      start = 1'b0;
      @(posedge clk);
      #2;
      check(spi_cs_n && !spi_sclk && !spi_mosi && busy && !done,
            "synchronous reset restores safe pins and initial gap");
      check(rx_bits == 0 && rx_frame == 0 && !error, "reset clears result");
      repeat (2) @(posedge clk);
      @(negedge clk);
      rst = 1'b0;
      wait_idle;
      check(completed == before_reset, "no spurious completion after reset gap");
      expect_abort = 1'b0;
    end
  endtask

  task begin_frame;
    input [79:0] send_frame;
    input [79:0] reply_frame;
    input integer delay_ns;
    input abort_case;
    begin
      wait_idle;
      @(negedge clk);
      expected_mosi = send_frame;
      slave_frame = reply_frame;
      miso_delay_ns = delay_ns;
      expect_abort = abort_case;
      request_completed_before = completed;
      tx_frame = send_frame;
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
    end
  endtask

  task finish_frame;
    input [79:0] expected_reply;
    input expected_error;
    integer cycles;
    begin
      cycles = 0;
      while (done !== 1'b1 && cycles < 250000) begin
        @(posedge clk);
        #2;
        cycles = cycles + 1;
      end
      check(done, "bounded completion");
      check(completed == request_completed_before + 1, "one completion per request");
      check(error === expected_error, "expected transport error status");
      if (!expected_error) begin
        check(rx_bits == 80, "normal received bit count");
        check(rx_frame === expected_reply, "MISO frame including first and last bit");
      end else check(rx_bits < 80, "partial timeout result not reported as complete");
      @(posedge clk);
      #2;
      check(!done, "done cleared next clock");
      cases = cases + 1;
    end
  endtask

  task normal_frame;
    input [79:0] send_frame;
    input [79:0] reply_frame;
    input integer delay_ns;
    begin
      begin_frame(send_frame, reply_frame, delay_ns, 1'b0);
      finish_frame(reply_frame, 1'b0);
    end
  endtask

  task cancel_in_phase;
    input integer phase;
    begin
      begin_frame(80'h01000000000000000000, 80'h00A50300EB0258012335, 1000, 1'b1);
      case (phase)
        0: #1000;  // CS 준비
        1: begin
          wait (rises == 13);
          #1000;
        end  // 전송 High
        2: begin
          wait (falls == 13);
          #1000;
        end  // 전송 Low
        3: begin
          wait (falls == 80);
          #1000;
        end  // CS 유지
        4: begin
          wait (spi_cs_n);
          #1000;
        end  // CS 비선택 대기
      endcase
      cancelled = cancelled + 1;
      reset_core;
      normal_frame(80'h01000000000000000000, 80'h00A50300EB0258012335, 1000);
    end
  endtask

  task timeout_in_phase;
    input high_phase;
    begin
      begin_frame(80'h01000000000000000000, 80'h00A50300EB0258012335, 1000, 1'b1);
      if (high_phase) wait (rises == 12);
      else wait (falls == 12);
      #1000;
      // System Clock은 유지하고 SPI 진행만 멈추는 오류를 주입한다.
      force u_spi_master.phase_count = 0;
      wait (spi_cs_n);
      #2;
      check(cs_end - cs_begin == 2000010, "independent watchdog expires strictly after 2ms");
      check(!spi_sclk && !spi_mosi && error && busy, "timeout safe pins then gap");
      release u_spi_master.phase_count;
      finish_frame(80'b0, 1'b1);
      normal_frame(80'h01000000000000000000, 80'h00A50300EB0258012335, 1000);
    end
  endtask

  integer accepted_before;
  initial begin
    $timeformat(-9, 0, "ns", 12);
    reset_core;

    // 초기 Gap의 요청이 나중에 재실행되지 않는지 확인한다.
    @(negedge clk);
    rst = 1'b1;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    start = 1'b1;
    accepted_before = accepted;
    @(negedge clk);
    start = 1'b0;
    wait_idle;
    check(accepted == accepted_before && !done, "request during initial gap ignored");

    normal_frame(80'h01000000000000000000, 80'h00A50300EB0258012335, 0);
    normal_frame(80'h01000000000000000000, 80'h00A503FFC901C4007B2E, 1000);
    normal_frame(80'h80000000000000000001, 80'h80000000000000000001, 1000);
    normal_frame(80'b0, 80'b0, 1000);
    normal_frame({80{1'b1}}, {80{1'b1}}, 1000);

    begin_frame(80'h13579BDF02468ACE55AA, 80'hFEDCBA98765432108001, 1000, 1'b0);
    accepted_before = accepted;
    wait (rises == 10);
    @(negedge clk);
    tx_frame = 80'b0;
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    tx_frame = {80{1'b1}};
    finish_frame(80'hFEDCBA98765432108001, 1'b0);
    check(accepted == accepted_before, "busy request ignored");
    repeat (2000) @(posedge clk);
    #2;
    check(!busy && spi_cs_n, "ignored busy request not queued");

    cancel_in_phase(0);
    cancel_in_phase(1);
    cancel_in_phase(2);
    cancel_in_phase(3);
    cancel_in_phase(4);
    timeout_in_phase(1'b1);
    timeout_in_phase(1'b0);

    repeat (2000) @(posedge clk);
    #2;
    check(accepted == completed + cancelled, "every request completed or reset-cancelled");
    if (failures == 0)
      $display(
          "SPI_MASTER_TEST_PASS cases=%0d accepted=%0d completed=%0d cancelled=%0d",
          cases,
          accepted,
          completed,
          cancelled
      );
    else $display("SPI_MASTER_TEST_FAIL failures=%0d", failures);
    $finish;
  end

  initial begin
    #30000000;
    $display("SPI_MASTER_TEST_FAIL global timeout");
    $finish;
  end
endmodule
