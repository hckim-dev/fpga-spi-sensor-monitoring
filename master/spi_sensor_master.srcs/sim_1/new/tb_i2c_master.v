`timescale 1ns / 1ps

module tb_i2c_master;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg start = 1'b0;
  reg [6:0] address = 7'h3C;
  reg tx_valid = 1'b0;
  wire tx_ready;
  reg [7:0] tx_data = 8'b0;
  reg tx_last = 1'b0;
  reg [7:0] control_byte = 8'h40;
  wire busy;
  wire done;
  wire error;
  tri1 scl;
  tri1 sda;
  reg peer_sda_low = 1'b0;
  reg hold_sda_low = 1'b0;
  reg hold_scl_low = 1'b0;
  reg peer_enabled = 1'b1;
  reg active = 1'b0;
  integer bit_count = 0;
  integer byte_count = 0;
  integer nack_index = -1;
  integer starts = 0;
  integer stops = 0;
  integer failures = 0;
  integer cases = 0;
  integer accepted = 0;
  reg [7:0] shift = 8'b0;
  reg [7:0] received [0:255];
  time last_rise = 0;
  time last_fall = 0;
  time start_at = 0;
  time previous_stop = 0;
  reg abort_expected = 1'b0;

  i2c_master u_i2c_master (
    .clk(clk),
    .rst(rst),
    .start(start),
    .address(address),
    .tx_valid(tx_valid),
    .tx_ready(tx_ready),
    .tx_data(tx_data),
    .tx_last(tx_last),
    .busy(busy),
    .done(done),
    .error(error),
    .scl(scl),
    .sda(sda)
  );
  assign sda = peer_sda_low || hold_sda_low ? 1'b0 : 1'bz;
  assign scl = hold_scl_low ? 1'b0 : 1'bz;
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

  // ACK만 구동하는 비합성 Slave이며 주소와 Payload를 직렬 Pin에서 복호화한다.
  always @(negedge sda) begin
    if (scl && !rst && peer_enabled) begin
      active = 1;
      bit_count = 0;
      byte_count = 0;
      shift = 0;
      starts = starts + 1;
      start_at = $time;
      if (previous_stop != 0) check($time - previous_stop >= 5000, "bus free at least 5us");
    end
  end

  always @(posedge sda) begin
    if (scl && active && !rst) begin
      active = 0;
      stops = stops + 1;
      previous_stop = $time;
      if (!abort_expected) check($time - last_rise >= 5000, "stop setup at least 5us");
    end
  end

  always @(posedge scl) begin
    if (active && !rst) begin
      check($time - last_fall >= 5000, "SCL low at least 5us");
      bit_count = bit_count + 1;
      if (bit_count <= 8) begin
        shift = {shift[6:0], sda};
        if (bit_count == 8) begin
          received[byte_count] = shift;
          byte_count = byte_count + 1;
        end
      end
      last_rise = $time;
    end
  end

  always @(negedge scl) begin
    if (active && !rst) begin
      if (bit_count == 0) begin
        check($time - start_at >= 5000, "start hold at least 5us");
      end else if (!abort_expected) begin
        check($time - last_rise >= 5000, "SCL high at least 5us");
      end
      if (bit_count == 8) begin
        peer_sda_low = byte_count - 1 != nack_index;
      end else if (bit_count == 9) begin
        peer_sda_low = 0;
        bit_count = 0;
      end
      last_fall = $time;
    end
  end

  always @(posedge clk) begin
    if (!rst && tx_valid && tx_ready) accepted = accepted + 1;
    #1;
    if (!rst) begin
      check(scl !== 1'bx && sda !== 1'bx, "no active-high drive conflict");
      if (hold_scl_low) check(scl === 1'b0, "released clock respects external low");
      if (hold_sda_low) check(sda === 1'b0, "released data respects external low");
    end
  end

  task reset_core;
    begin
      @(negedge clk);
      rst = 1;
      start = 0;
      tx_valid = 0;
      peer_sda_low = 0;
      hold_scl_low = 0;
      hold_sda_low = 0;
      active = 0;
      previous_stop = 0;
      @(posedge clk);
      #2;
      check(!busy && !done && !error && scl && sda, "reset releases bus without completion");
      @(negedge clk);
      rst = 0;
      peer_enabled = 1;
      nack_index = -1;
      abort_expected = 0;
    end
  endtask

  task begin_packet;
    input [6:0] target;
    begin
      @(negedge clk);
      address = target;
      start = 1;
      @(negedge clk);
      start = 0;
      address = 7'h10;
      check(busy, "packet accepted");
    end
  endtask

  task send_bytes;
    input integer count;
    input final_last;
    integer index;
    integer limit;
    reg took_byte;
    begin
      for (index = 0; index < count; index = index + 1) begin
        @(negedge clk);
        tx_valid = 1;
        tx_data = index == 0 ? control_byte : index[7:0] ^ 8'hA5;
        tx_last = final_last && index == count - 1;
        took_byte = 0;
        limit = 0;
        while (!took_byte && busy && limit < 2000001) begin
          @(posedge clk);
          if (tx_ready) took_byte = 1;
          #2;
          limit = limit + 1;
        end
        check(took_byte, "bounded payload handshake");
        @(negedge clk);
        tx_valid = 0;
        tx_data = 8'hFF;
      end
    end
  endtask

  task finish_packet;
    input expected_error;
    integer limit;
    begin
      limit = 0;
      while (!done && limit < 2000005) begin
        @(posedge clk);
        #2;
        limit = limit + 1;
      end
      check(done && !busy && error === expected_error, "bounded result and error status");
      check(!u_i2c_master.scl_low && !u_i2c_master.sda_low, "result releases both bus drivers");
      @(posedge clk);
      #2;
      check(!done, "done one cycle wide");
      cases = cases + 1;
    end
  endtask

  task good_packet;
    input [6:0] target;
    input integer length;
    integer index;
    begin
      begin_packet(target);
      send_bytes(length, 1);
      finish_packet(0);
      check(byte_count == length + 1 && received[0] === {target, 1'b0}, "address write bit and exact byte count");
      for (index = 0; index < length; index = index + 1) begin
        check(received[index+1] === (index == 0 ? control_byte : index[7:0] ^ 8'hA5), "MSB-first payload and latched byte");
      end
    end
  endtask

  integer stops_before;
  integer accepted_before;
  integer starts_before;
  time requested_at;
  initial begin
    $timeformat(-9, 0, "ns", 12);
    reset_core;
    good_packet(7'h3C, 3);
    good_packet(7'h3D, 1);
    control_byte = 8'h00;
    good_packet(7'h3C, 2);
    control_byte = 8'h40;

    // Busy 요청은 폐기하고, 유한한 Clock Stretch 뒤 같은 Packet을 마친다.
    begin_packet(7'h3C);
    starts_before = starts;
    fork
      begin
        send_bytes(2, 1);
        finish_packet(0);
      end
      begin
        @(negedge scl);
        @(negedge clk);
        start = 1;
        hold_scl_low = 1;
        repeat (1000) @(posedge clk);
        @(negedge clk);
        start = 0;
        hold_scl_low = 0;
      end
    join
    check(starts == starts_before + 1, "busy start not queued");
    begin_packet(7'h3C);
    wait (tx_ready);
    repeat (1000) @(posedge clk);
    check(!scl && busy && !error && byte_count == 1, "finite byte supply wait holds SCL low");
    send_bytes(1, 1);
    finish_packet(0);
    good_packet(7'h3C, 129);

    nack_index = 0;
    stops_before = stops;
    begin_packet(7'h3C);
    finish_packet(1);
    check(byte_count == 1 && stops == stops_before + 1, "address NACK terminates with STOP");
    nack_index = 2;
    begin_packet(7'h3C);
    send_bytes(2, 1);
    finish_packet(1);
    nack_index = 1;
    begin_packet(7'h3C);
    send_bytes(1, 0);
    finish_packet(1);
    check(byte_count == 2, "middle payload NACK prevents next byte request");
    nack_index = -1;
    good_packet(7'h3C, 1);

    accepted_before = accepted;
    begin_packet(7'h3C);
    send_bytes(129, 0);
    finish_packet(1);
    check(accepted - accepted_before == 129 && byte_count == 130, "payload limit rejects missing last without extra byte");

    // Bus Busy·Clock 정지·Byte 공급 정지는 모두 20ms 안에 실패한다.
    reset_core;
    peer_enabled = 0;
    hold_sda_low = 1;
    repeat (5) @(posedge clk);
    begin_packet(7'h3C);
    requested_at = $time - 5;
    finish_packet(1);
    check($time - requested_at == 20000012, "bus watchdog exactly 20ms then one-cycle done check");
    hold_sda_low = 0;
    reset_core;
    begin_packet(7'h3C);
    @(negedge scl);
    hold_scl_low = 1;
    abort_expected = 1;
    finish_packet(1);
    hold_scl_low = 0;
    reset_core;
    begin_packet(7'h3C);
    finish_packet(1);
    good_packet(7'h3C, 2);

    begin_packet(7'h3C);
    @(posedge scl);
    #1002;
    reset_core;
    repeat (1000) @(posedge clk);
    check(!done && !busy, "reset cancellation has no delayed completion");
    good_packet(7'h3D, 2);
    if (failures == 0) begin
      $display("I2C_MASTER_TEST_PASS cases=%0d", cases);
    end else begin
      $display("I2C_MASTER_TEST_FAIL failures=%0d", failures);
    end
    $finish;
  end

  initial begin
    #150000000;
    $display("I2C_MASTER_TEST_FAIL global timeout");
    $finish;
  end
endmodule
