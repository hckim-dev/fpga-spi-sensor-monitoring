`timescale 1ns / 1ps

module tb_reset_sync;
  reg clk = 1'b0;
  reg clock_enable = 1'b1;
  reg arst = 1'b0;
  wire rst;
  integer failures = 0;
  integer cases = 0;
  integer offset;

  reset_sync u_reset_sync (
      .clk (clk),
      .arst(arst),
      .rst (rst)
  );
  always #5 begin
    if (clock_enable) clk = ~clk;
  end

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

  task release_check;
    begin
      @(posedge clk);
      #1;
      check(rst, "release remains reset after first edge");
      @(posedge clk);
      #1;
      check(!rst, "release completes after second edge");
      cases = cases + 1;
    end
  endtask

  initial begin
    #1;
    check(rst, "power-on reset asserted without button");
    release_check;
    for (offset = 1; offset < 5; offset = offset + 1) begin
      @(negedge clk);
      #(offset);
      arst = 1;
      #0.1;
      check(rst, "asynchronous assertion before clock edge");
      repeat (3) @(posedge clk);
      @(negedge clk);
      #(offset);
      arst = 0;
      release_check;
    end
    @(negedge clk);
    clock_enable = 0;
    #2;
    arst = 1;
    #1;
    check(rst, "asserts with stopped clock");
    arst = 0;
    #30;
    check(rst, "stopped clock prevents release");
    clock_enable = 1;
    release_check;
    if (failures == 0) begin
      $display("RESET_SYNC_TEST_PASS cases=%0d", cases);
    end else begin
      $display("RESET_SYNC_TEST_FAIL failures=%0d", failures);
    end
    $finish;
  end

  initial begin
    #10000;
    $display("RESET_SYNC_TEST_FAIL global timeout");
    $finish;
  end
endmodule
