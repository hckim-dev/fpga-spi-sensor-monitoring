`timescale 1ns / 1ps

module sensor_reader #(
  parameter integer POLL_CYCLES = 10000000,
  parameter integer STALE_CYCLES = 50000000
) (
  input wire clk,
  input wire rst,
  output wire spi_start,
  output wire [79:0] spi_tx_frame,
  input wire spi_busy,
  input wire spi_done,
  input wire spi_error,
  input wire [79:0] spi_rx_frame,
  input wire [6:0] spi_rx_bits,
  output reg signed [15:0] temperature,
  output reg [15:0] humidity,
  output reg [15:0] distance,
  output reg [1:0] sensor_valid,
  output reg link_valid,
  output reg link_stale,
  output reg [2:0] last_error,
  output reg [7:0] debug_rx_byte,
  output reg report_update,
  output reg sample_toggle
);
  function integer count_width;
    input integer maximum;
    integer value;
    begin
      value = maximum;
      count_width = 0;
      while (value > 0) begin
        count_width = count_width + 1;
        value = value >> 1;
      end
      if (count_width == 0) begin
        count_width = 1;
      end
    end
  endfunction

  localparam integer POLL_WIDTH = count_width(POLL_CYCLES - 1);
  localparam integer AGE_WIDTH = count_width(STALE_CYCLES);
  localparam [POLL_WIDTH-1:0] POLL_LAST = POLL_CYCLES - 1;
  localparam [AGE_WIDTH-1:0] STALE_LAST = STALE_CYCLES - 1;
  localparam [AGE_WIDTH-1:0] STALE_LIMIT = STALE_CYCLES;
  localparam [1:0] WAIT_POLL = 2'd0;
  localparam [1:0] WAIT_TRANSFER = 2'd1;
  localparam [1:0] CHECK_FRAME = 2'd2;
  localparam [2:0] NONE = 3'd0;
  localparam [2:0] TIMEOUT = 3'd1;
  localparam [2:0] LENGTH = 3'd2;
  localparam [2:0] HEADER = 3'd3;
  localparam [2:0] CHECKSUM = 3'd4;
  localparam [2:0] RESERVED = 3'd5;
  localparam [2:0] RANGE = 3'd6;
  localparam [2:0] STALE = 3'd7;

  reg [1:0] state;
  reg [POLL_WIDTH-1:0] poll_count;
  reg [AGE_WIDTH-1:0] receive_age;
  reg [79:0] received_frame;
  reg [6:0] received_bits;
  reg received_error;
  reg [2:0] frame_error;

  wire signed [15:0] frame_temperature = received_frame[55:40];
  wire [15:0] frame_humidity = received_frame[39:24];
  wire [15:0] frame_distance = received_frame[23:8];
  wire [7:0] frame_status = received_frame[63:56];
  wire [7:0] frame_xor = received_frame[71:64] ^ received_frame[63:56] ^
      received_frame[55:48] ^ received_frame[47:40] ^ received_frame[39:32] ^
      received_frame[31:24] ^ received_frame[23:16] ^ received_frame[15:8] ^
      received_frame[7:0];

  // 대기 Counter를 포화시켜 지연된 Poll을 한 개만 보류한다.
  assign spi_start = !rst && state == WAIT_POLL && poll_count == POLL_LAST && !spi_busy;
  assign spi_tx_frame = 80'h01000000000000000000;

  // synthesis translate_off
  initial begin
    if (POLL_CYCLES < 1 || STALE_CYCLES < 1) begin
      $display("ERROR: sensor_reader cycle parameters must be positive");
      $finish;
    end
  end
  // synthesis translate_on

  always @* begin
    frame_error = NONE;
    if (received_error) begin
      frame_error = TIMEOUT;
    end else if (received_bits != 7'd80) begin
      frame_error = LENGTH;
    end else if (received_frame[71:64] != 8'hA5) begin
      frame_error = HEADER;
    end else if (frame_xor != 8'h00) begin
      frame_error = CHECKSUM;
    end else if (frame_status[7:2] != 6'b0) begin
      frame_error = RESERVED;
    end else if ((frame_status[0] &&
        (frame_temperature < -16'sd200 || frame_temperature > 16'sd600 ||
          frame_humidity > 16'd1000)) ||
        (frame_status[1] && (frame_distance < 16'd2 || frame_distance > 16'd400))) begin
      frame_error = RANGE;
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      state <= WAIT_POLL;
      poll_count <= POLL_LAST;
      receive_age <= {AGE_WIDTH{1'b0}};
      received_frame <= 80'b0;
      received_bits <= 7'd0;
      received_error <= 1'b0;
      temperature <= 16'sd0;
      humidity <= 16'd0;
      distance <= 16'd0;
      sensor_valid <= 2'b0;
      link_valid <= 1'b0;
      link_stale <= 1'b0;
      last_error <= NONE;
      debug_rx_byte <= 8'b0;
      report_update <= 1'b0;
      sample_toggle <= 1'b0;
    end else begin
      report_update <= 1'b0;
      if (spi_start) begin
        poll_count <= {POLL_WIDTH{1'b0}};
      end else if (poll_count < POLL_LAST) begin
        poll_count <= poll_count + 1'b1;
      end

      // 오류 응답도 Age를 멈추지 않는다. 성공 반영만 아래에서 우선한다.
      if (receive_age < STALE_LIMIT) begin
        receive_age <= receive_age + 1'b1;
      end
      if (!link_stale && receive_age == STALE_LAST) begin
        sensor_valid <= 2'b0;
        link_valid <= 1'b0;
        link_stale <= 1'b1;
        last_error <= STALE;
        report_update <= 1'b1;
      end

      case (state)
        WAIT_POLL: begin
          if (spi_start) begin
            state <= WAIT_TRANSFER;
          end
        end
        WAIT_TRANSFER: begin
          if (spi_done) begin
            received_frame <= spi_rx_frame;
            received_bits <= spi_rx_bits;
            received_error <= spi_error;
            state <= CHECK_FRAME;
          end
        end
        CHECK_FRAME: begin
          state <= WAIT_POLL;
          report_update <= 1'b1;
          last_error <= frame_error;
          if (received_bits == 7'd80) begin
            debug_rx_byte <= received_frame[15:8];
          end
          if (frame_error == NONE) begin
            temperature <= frame_temperature;
            humidity <= frame_humidity;
            distance <= frame_distance;
            sensor_valid <= frame_status[1:0];
            link_valid <= 1'b1;
            link_stale <= 1'b0;
            receive_age <= {AGE_WIDTH{1'b0}};
            sample_toggle <= !sample_toggle;
          end else begin
            sensor_valid <= 2'b0;
            link_valid <= 1'b0;
          end
        end
        default: begin
          state <= WAIT_POLL;
        end
      endcase
    end
  end
endmodule
