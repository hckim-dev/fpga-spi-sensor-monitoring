`timescale 1ns / 1ps

module tb_oled_display;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg report_update = 1'b0;
  reg signed [15:0] temperature = 235;
  reg [15:0] humidity = 600;
  reg [15:0] distance = 291;
  reg [1:0] sensor_valid = 3;
  reg link_valid = 1;
  reg link_stale = 0;
  reg [2:0] last_error = 0;
  wire oled_fault;
  wire busy;
  tri1 scl;
  tri1 sda;
  reg present = 1;
  reg [6:0] address = 7'h3C;
  reg nack_data = 0;
  reg [2:0] nack_page = 2;
  integer failures = 0;
  integer cases = 0;
  integer before_frames;
  integer i;
  time failed_at;

  oled_display #(
      .POWERUP_CYCLES(20),
      .RETRY_CYCLES(1000),
      .I2C_HALF_PERIOD_CYCLES(10),
      .I2C_WATCHDOG_CYCLES(100000)
  ) u_oled_display (
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
      .busy(busy),
      .scl(scl),
      .sda(sda)
  );
  ssd1306_model u_ssd1306_model (
      .scl(scl),
      .sda(sda),
      .present(present),
      .address(address),
      .nack_data(nack_data),
      .nack_page(nack_page)
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

  task update;
    begin
      @(negedge clk);
      report_update = 1;
      @(negedge clk);
      report_update = 0;
    end
  endtask

  task expect_glyph;
    input integer row;
    input integer character_position;
    input [39:0] expected;
    integer col;
    begin
      for (col = 0; col < 5; col = col + 1) begin
        check(u_ssd1306_model.ram[row*128+character_position*6+col] === expected[(4-col)*8+:8],
              "independent expected glyph in decoded OLED RAM");
      end
      check(u_ssd1306_model.ram[row*128+character_position*6+5] == 0, "glyph spacing cleared");
    end
  endtask

  task wait_frame;
    input integer target;
    integer limit;
    begin
      limit = 0;
      while (u_ssd1306_model.frames < target && limit < 2000000) begin
        @(posedge clk);
        limit = limit + 1;
      end
      #2;
      check(u_ssd1306_model.frames >= target, "bounded complete OLED frame");
      cases = cases + 1;
    end
  endtask

  initial begin
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 0;
    wait (u_ssd1306_model.page == 1 && u_ssd1306_model.byte_count == 12);
    temperature = -55;
    humidity = 452;
    distance = 123;
    update;
    temperature = -200;
    humidity = 1000;
    distance = 400;
    update;
    wait_frame(1);
    expect_glyph(0, 0, 40'h4649494931);
    expect_glyph(1, 0, 40'h01017F0101);
    expect_glyph(1, 3, 40'h4261514946);
    expect_glyph(1, 4, 40'h2141454B31);
    expect_glyph(1, 5, 40'h0060600000);
    expect_glyph(1, 6, 40'h2745454539);
    for (i = 84; i < 128; i = i + 1) check(u_ssd1306_model.ram[i] == 0, "full page tail cleared");
    check(oled_fault, "initial fault remains until display ON packet");
    wait (!oled_fault);
    check(u_ssd1306_model.on_count == 1, "display enabled after all eight pages");
    wait_frame(2);
    expect_glyph(1, 3, 40'h0808080808);
    expect_glyph(1, 4, 40'h4261514946);
    expect_glyph(1, 5, 40'h3E5149453E);
    expect_glyph(1, 6, 40'h0060600000);
    expect_glyph(2, 3, 40'h00427F4000);
    wait (!busy);
    check(u_ssd1306_model.init_count == 1, "normal refresh does not reinitialize");

    nack_data   = 1;
    temperature = 600;
    update;
    wait (oled_fault);
    failed_at = $time;
    check(u_ssd1306_model.frames == 2, "partial page failure not a complete frame");
    nack_data = 0;
    temperature = 0;
    humidity = 0;
    distance = 2;
    sensor_valid = 0;
    link_valid = 0;
    link_stale = 1;
    last_error = 7;
    update;
    wait (u_ssd1306_model.init_count == 2);
    check($time - failed_at >= 10000, "retry wait before reinitialization");
    wait_frame(3);
    expect_glyph(1, 3, 40'h0808080808);
    expect_glyph(1, 4, 40'h0808080808);
    expect_glyph(2, 3, 40'h0808080808);
    expect_glyph(3, 3, 40'h0808080808);
    expect_glyph(4, 6, 40'h7F49494941);
    wait (!oled_fault);
    check(u_ssd1306_model.on_count == 2, "recovery restores full screen before clearing fault");

    wait (!busy);
    before_frames = u_ssd1306_model.frames;
    sensor_valid = 3;
    link_valid = 1;
    link_stale = 0;
    last_error = 0;
    temperature = 235;
    update;
    wait (u_ssd1306_model.page == 1 && u_ssd1306_model.byte_count == 12);
    temperature = 600;
    update;
    @(negedge clk);
    rst = 1;
    temperature = -55;
    humidity = 452;
    distance = 123;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 0;
    wait_frame(before_frames + 1);
    expect_glyph(1, 3, 40'h0808080808);
    expect_glyph(1, 4, 40'h2745454539);
    expect_glyph(1, 5, 40'h0060600000);
    wait (!oled_fault);

    // FPGA Reset은 모듈 RAM을 지우지 않아도 전체 재초기화로 복구해야 한다.
    wait (!busy);
    before_frames = u_ssd1306_model.frames;
    @(negedge clk);
    rst = 1;
    address = 7'h3D;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 0;
    wait_frame(before_frames + 1);
    wait (!oled_fault);
    check(u_ssd1306_model.addresses_3c > 0 && u_ssd1306_model.addresses_3d > 0,
          "address NACK falls back to 0x3D");

    present = 0;
    temperature = 235;
    update;
    wait (oled_fault);
    repeat (3000) @(posedge clk);
    check(oled_fault, "absent device retains fault");
    present = 1;
    wait_frame(before_frames + 2);
    wait (!oled_fault);
    check(u_ssd1306_model.failures == 0, "all decoded OLED packets satisfy model checks");
    if (failures == 0) begin
      $display("OLED_DISPLAY_TEST_PASS cases=%0d frames=%0d", cases, u_ssd1306_model.frames);
    end else begin
      $display("OLED_DISPLAY_TEST_FAIL failures=%0d", failures);
    end
    $finish;
  end

  initial begin
    #40000000;
    $display("OLED_DISPLAY_TEST_FAIL global timeout");
    $finish;
  end
endmodule
