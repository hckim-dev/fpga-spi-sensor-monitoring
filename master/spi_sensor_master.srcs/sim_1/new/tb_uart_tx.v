`timescale 1ns / 1ps

module tb_uart_tx;
  localparam integer BIT_CYCLES = 868;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg start = 1'b0;
  reg [7:0] data = 8'b0;
  wire tx;
  wire busy;
  wire done;
  wire received;
  wire [7:0] received_data;
  wire framing_error;
  integer failures = 0;
  integer cases = 0;
  integer value;
  integer bit_number;
  integer cycle;
  reg [9:0] expected_frame;

  uart_tx u_uart_tx (
      .clk(clk),
      .rst(rst),
      .start(start),
      .data(data),
      .tx(tx),
      .busy(busy),
      .done(done)
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

  integer receive_count = 0;
  always @(posedge clk) begin
    if (received && !rst) begin
      receive_count = receive_count + 1;
      check(received_data === expected_frame[8:1] && !framing_error,
            "independent receiver matches byte");
    end
  end

  initial begin
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 0;
    for (value = 0; value < 256; value = value + 1) begin
      @(negedge clk);
      data = value[7:0];
      expected_frame = {1'b1, value[7:0], 1'b0};
      start = 1;
      @(posedge clk);
      #2;
      check(busy && !done && !tx, "accepted byte starts immediately");
      @(negedge clk);
      start = 0;
      data  = ~value[7:0];
      for (bit_number = 0; bit_number < 10; bit_number = bit_number + 1) begin
        for (cycle = 0; cycle < BIT_CYCLES; cycle = cycle + 1) begin
          check(tx === expected_frame[bit_number] && busy && !done, "8N1 exact bit duration");
          if (cycle == 0 && bit_number == 3) start = 1;
          if (cycle == 1 && bit_number == 3) start = 0;
          @(posedge clk);
          #2;
        end
      end
      check(done && !busy && tx, "done after complete stop bit");
      @(posedge clk);
      #2;
      check(!done, "done one cycle wide");
      cases = cases + 1;
    end
    check(receive_count == 256, "busy requests not queued");

    // Start・Data・Stop 도중 Reset은 완료 없이 Idle로 복귀한다.
    for (cycle = 0; cycle < 3; cycle = cycle + 1) begin
      bit_number = cycle == 0 ? 0 : cycle == 1 ? 4 : 9;
      @(negedge clk);
      data  = 8'h55;
      start = 1;
      @(negedge clk);
      start = 0;
      repeat (bit_number * BIT_CYCLES + 100) @(posedge clk);
      @(negedge clk);
      rst = 1;
      @(posedge clk);
      #2;
      check(tx && !busy && !done, "reset cancels partial UART byte");
      @(negedge clk);
      rst = 0;
      repeat (BIT_CYCLES) @(posedge clk);
      cases = cases + 1;
    end
    if (failures == 0) begin
      $display("UART_TX_TEST_PASS cases=%0d", cases);
    end else begin
      $display("UART_TX_TEST_FAIL failures=%0d", failures);
    end
    $finish;
  end

  initial begin
    #30000000;
    $display("UART_TX_TEST_FAIL global timeout");
    $finish;
  end
endmodule
