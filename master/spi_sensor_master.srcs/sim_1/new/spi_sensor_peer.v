`timescale 1ns / 1ps

// Master 검증용 직렬 응답 모델이며 실제 센서 Driver는 포함하지 않는다.
module spi_sensor_peer (
  input wire spi_cs_n,
  input wire spi_sclk,
  input wire spi_mosi,
  output wire spi_miso,
  input wire [79:0] reply_frame,
  input wire peer_reset
);
  reg [7:0] command = 8'b0;
  reg [79:0] snapshot = 80'b0;
  reg miso_bit = 1'b0;
  integer rises = 0;

  assign spi_miso = spi_cs_n ? 1'bz : (peer_reset ? 1'b0 : miso_bit);

  always @(negedge spi_cs_n) begin
    command = 8'b0;
    snapshot = 80'b0;
    rises = 0;
    miso_bit <= 1'b0;
  end

  always @(posedge spi_sclk) begin
    if (!spi_cs_n) begin
      rises = rises + 1;
      if (rises <= 8) begin
        command = {command[6:0], spi_mosi};
      end
      if (rises == 8 && command == 8'h01 && !peer_reset) begin
        snapshot = reply_frame;
      end
    end
  end

  always @(negedge spi_sclk) begin
    if (!spi_cs_n) begin
      if (rises >= 8 && rises < 80) begin
        miso_bit <= #1000 snapshot[79-rises];
      end else begin
        miso_bit <= #1000 1'b0;
      end
    end
  end
endmodule
