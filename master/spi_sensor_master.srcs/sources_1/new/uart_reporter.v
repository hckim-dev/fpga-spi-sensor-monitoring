`timescale 1ns / 1ps

module uart_reporter #(
    parameter integer BIT_CYCLES = 868
) (
    input wire clk,
    input wire rst,
    input wire report_update,
    input wire signed [15:0] temperature,
    input wire [15:0] humidity,
    input wire [15:0] distance,
    input wire [1:0] sensor_valid,
    input wire link_valid,
    input wire link_stale,
    input wire [2:0] last_error,
    input wire oled_fault,
    output wire tx,
    output wire busy
);
  localparam [2:0] WAIT_RECORD = 3'd0;
  localparam [2:0] BUILD_LINE  = 3'd1;
  localparam [2:0] SEND_BYTE   = 3'd2;
  localparam [2:0] WAIT_BYTE   = 3'd3;

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

  localparam integer RECOVERY_CYCLES = BIT_CYCLES * 10;
  localparam integer RECOVERY_WIDTH = count_width(RECOVERY_CYCLES);
  localparam [RECOVERY_WIDTH-1:0] RECOVERY_LIMIT = RECOVERY_CYCLES;

  localparam [2:0] PREPARE_VALUE = 3'd4;
  localparam [2:0] BUILD_CHUNK = 3'd5;

  reg [2:0] state;
  reg previous_oled_fault;
  reg pending_valid;
  reg [55:0] pending_record;
  reg [55:0] active_record;
  reg need_resync;
  reg [511:0] message;
  reg [6:0] message_length;
  reg [6:0] bytes_left;
  reg [2:0] field_index;
  reg [RECOVERY_WIDTH-1:0] recovery_count;
  reg [127:0] chunk;
  reg [4:0] chunk_length;
  reg [127:0] saved_chunk;
  reg [4:0] saved_chunk_length;
  reg tx_start;
  reg [7:0] tx_data;
  wire tx_busy;
  wire tx_done;
  wire update_event = report_update || oled_fault != previous_oled_fault;
  wire [55:0] incoming_record = {
    temperature, humidity, distance, sensor_valid, link_valid, link_stale, last_error, oled_fault
  };
  wire signed [15:0] saved_temperature = active_record[55:40];
  wire [15:0] saved_humidity = active_record[39:24];
  wire [15:0] saved_distance = active_record[23:8];
  wire [1:0] saved_valid = active_record[7:6];
  wire saved_link_valid = active_record[5];
  wire [2:0] saved_error = active_record[3:1];
  wire saved_oled_fault = active_record[0];

  assign busy = state != WAIT_RECORD;

  uart_tx #(
      .BIT_CYCLES(BIT_CYCLES)
  ) u_uart_tx (
      .clk(clk),
      .rst(rst),
      .start(tx_start),
      .data(tx_data),
      .tx(tx),
      .busy(tx_busy),
      .done(tx_done)
  );

  function [15:0] decimal_digits;
    input [9:0] value;
    reg [15:0] digits;
    integer bit_index;
    integer place;
    begin
      digits = 16'b0;
      for (bit_index = 9; bit_index >= 0; bit_index = bit_index - 1) begin
        for (place = 0; place < 4; place = place + 1) begin
          if (digits[place*4+:4] >= 4'd5) begin
            digits[place*4+:4] = digits[place*4+:4] + 4'd3;
          end
        end
        digits = {digits[14:0], value[bit_index]};
      end
      decimal_digits = digits;
    end
  endfunction

  // 상위 4 Bit는 길이, 하위 40 Bit는 오른쪽 정렬한 수치 문자열이다.
  function [43:0] format_value;
    input [15:0] magnitude;
    input negative;
    input fractional;
    input valid;
    reg [39:0] text;
    reg [ 3:0] length;
    reg [15:0] digits;
    reg [ 3:0] hundreds;
    reg [ 3:0] tens;
    reg [ 3:0] ones;
    begin
      text = 40'b0;
      length = 4'd0;
      digits = decimal_digits(magnitude[9:0]);
      hundreds = fractional ? digits[15:12] : digits[11:8];
      tens = fractional ? digits[11:8] : digits[7:4];
      ones = fractional ? digits[7:4] : digits[3:0];
      if (!valid) begin
        text   = "--";
        length = 4'd2;
      end else begin
        if (negative) begin
          text   = "-";
          length = 4'd1;
        end
        if (hundreds != 0) begin
          text   = {text[31:0], 4'h3, hundreds};
          length = length + 1'b1;
        end
        if (hundreds != 0 || tens != 0) begin
          text   = {text[31:0], 4'h3, tens};
          length = length + 1'b1;
        end
        text   = {text[31:0], 4'h3, ones};
        length = length + 1'b1;
        if (fractional) begin
          text   = {text[23:0], 8'h2E, 4'h3, digits[3:0]};
          length = length + 2'd2;
        end
      end
      format_value = {length, text};
    end
  endfunction

  reg [43:0] formatted_value;
  reg [15:0] magnitude;
  reg negative;

  always @* begin
    chunk = 128'b0;
    chunk_length = 5'b0;
    negative = saved_temperature < 16'sd0;
    magnitude = negative ? -saved_temperature : saved_temperature;
    case (field_index)
      3'd0: begin
        chunk = (128'h543D << ((formatted_value[43:40] + 1) * 8)) |
            ({88'b0, formatted_value[39:0]} << 8) | 128'h43;
        chunk_length = {1'b0, formatted_value[43:40]} + 5'd3;
      end
      3'd1: begin
        chunk = (128'h20483D << ((formatted_value[43:40] + 1) * 8)) |
            ({88'b0, formatted_value[39:0]} << 8) | 128'h25;
        chunk_length = {1'b0, formatted_value[43:40]} + 5'd4;
      end
      3'd2: begin
        chunk = (128'h20443D << ((formatted_value[43:40] + 2) * 8)) |
            ({88'b0, formatted_value[39:0]} << 16) | 128'h636D;
        chunk_length = {1'b0, formatted_value[43:40]} + 5'd5;
      end
      3'd3: begin
        if (saved_link_valid) begin
          chunk = " L=OK";
          chunk_length = 5'd5;
        end else begin
          case (saved_error)
            3'd1: begin
              chunk = " L=ERR:TIMEOUT";
              chunk_length = 5'd14;
            end
            3'd2: begin
              chunk = " L=ERR:LENGTH";
              chunk_length = 5'd13;
            end
            3'd3: begin
              chunk = " L=ERR:HEADER";
              chunk_length = 5'd13;
            end
            3'd4: begin
              chunk = " L=ERR:XOR";
              chunk_length = 5'd10;
            end
            3'd5: begin
              chunk = " L=ERR:RESERVED";
              chunk_length = 5'd15;
            end
            3'd6: begin
              chunk = " L=ERR:RANGE";
              chunk_length = 5'd12;
            end
            3'd7: begin
              chunk = " L=ERR:STALE";
              chunk_length = 5'd12;
            end
            default: begin
              chunk = " L=ERR:NONE";
              chunk_length = 5'd11;
            end
          endcase
        end
      end
      default: begin
        if (saved_oled_fault) begin
          chunk = {" O=ERR", 8'h0D, 8'h0A};
          chunk_length = 5'd8;
        end else begin
          chunk = {" O=OK", 8'h0D, 8'h0A};
          chunk_length = 5'd7;
        end
      end
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      state <= WAIT_RECORD;
      previous_oled_fault <= 1'b0;
      pending_valid <= 1'b0;
      need_resync <= 1'b1;
      message_length <= 7'b0;
      bytes_left <= 7'b0;
      field_index <= 3'b0;
      tx_start <= 1'b0;
      tx_data <= 8'b0;
      recovery_count <= RECOVERY_LIMIT;
    end else begin
      tx_start <= 1'b0;
      previous_oled_fault <= oled_fault;
      // 상대 수신기의 진행 중 문자가 끝나도록 Reset 뒤 한 문자만큼 쉰다.
      if (recovery_count != 0) begin
        recovery_count <= recovery_count - 1'b1;
      end
      if (update_event) begin
        pending_record <= incoming_record;
        pending_valid  <= 1'b1;
      end
      case (state)
        WAIT_RECORD: begin
          if (update_event || pending_valid) begin
            // 동시 갱신은 이전 Pending보다 우선하고 전송용 Snapshot을 고정한다.
            active_record <= update_event ? incoming_record : pending_record;
            pending_valid <= 1'b0;
            message <= need_resync ? 512'h0D0A : 512'b0;
            message_length <= need_resync ? 7'd2 : 7'd0;
            need_resync <= 1'b0;
            field_index <= 3'd0;
            state <= PREPARE_VALUE;
          end
        end
        PREPARE_VALUE: begin
          case (field_index)
            3'd0: formatted_value <= format_value(magnitude, negative, 1'b1, saved_valid[0]);
            3'd1: formatted_value <= format_value(saved_humidity, 1'b0, 1'b1, saved_valid[0]);
            3'd2: formatted_value <= format_value(saved_distance, 1'b0, 1'b0, saved_valid[1]);
            default: formatted_value <= 44'b0;
          endcase
          state <= BUILD_CHUNK;
        end
        BUILD_CHUNK: begin
          saved_chunk <= chunk;
          saved_chunk_length <= chunk_length;
          state <= BUILD_LINE;
        end
        BUILD_LINE: begin
          message <= (message << (saved_chunk_length * 8)) | {384'b0, saved_chunk};
          message_length <= message_length + {2'b0, saved_chunk_length};
          if (field_index == 3'd4) begin
            bytes_left <= message_length + {2'b0, saved_chunk_length};
            state <= SEND_BYTE;
          end else begin
            field_index <= field_index + 1'b1;
            state <= PREPARE_VALUE;
          end
        end
        SEND_BYTE: begin
          if (!tx_busy && recovery_count == 0) begin
            tx_data <= message[(bytes_left-1)*8+:8];
            tx_start <= 1'b1;
            state <= WAIT_BYTE;
          end
        end
        WAIT_BYTE: begin
          if (tx_done) begin
            if (bytes_left == 7'd1) begin
              state <= WAIT_RECORD;
            end else begin
              bytes_left <= bytes_left - 1'b1;
              state <= SEND_BYTE;
            end
          end
        end
      endcase
    end
  end
endmodule
