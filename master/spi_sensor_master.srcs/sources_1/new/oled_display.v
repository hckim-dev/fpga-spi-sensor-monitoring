`timescale 1ns / 1ps

module oled_display #(
    parameter integer POWERUP_CYCLES = 10000000,
    parameter integer RETRY_CYCLES = 50000000,
    parameter integer I2C_HALF_PERIOD_CYCLES = 500,
    parameter integer I2C_WATCHDOG_CYCLES = 2000000
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
    output reg oled_fault,
    output wire busy,
    inout wire scl,
    inout wire sda
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

  localparam integer TIMER_MAX = POWERUP_CYCLES > RETRY_CYCLES ? POWERUP_CYCLES : RETRY_CYCLES;
  localparam integer TIMER_WIDTH = count_width(TIMER_MAX - 1);
  localparam [TIMER_WIDTH-1:0] POWERUP_LAST = POWERUP_CYCLES - 1;
  localparam [TIMER_WIDTH-1:0] RETRY_LAST = RETRY_CYCLES - 1;
  localparam [3:0] POWER_WAIT = 4'd0;
  localparam [3:0] WAIT_RECORD = 4'd1;
  localparam [3:0] PREPARE_PACKET = 4'd2;
  localparam [3:0] START_PACKET = 4'd3;
  localparam [3:0] SEND_BYTES = 4'd4;
  localparam [3:0] WAIT_PACKET = 4'd5;
  localparam [3:0] RETRY_WAIT = 4'd6;
  localparam [1:0] INIT = 2'd0;
  localparam [1:0] PAGE_COMMAND = 2'd1;
  localparam [1:0] PAGE_DATA = 2'd2;
  localparam [1:0] DISPLAY_ON = 2'd3;

  localparam [3:0] LATCH_LINE = 4'd7;
  localparam [3:0] LOAD_CHARACTER = 4'd8;
  localparam [3:0] LOAD_PIXEL = 4'd9;

  reg [3:0] state;
  reg [1:0] packet_kind;
  reg [TIMER_WIDTH-1:0] wait_count;
  reg [54:0] active_record;
  reg [54:0] pending_record;
  reg pending_valid;
  reg refresh_due;
  reg need_init;
  reg address_locked;
  reg [6:0] selected_address;
  reg [2:0] page;
  reg [7:0] byte_index;
  reg [4:0] character_index;
  reg [2:0] glyph_column;
  reg [127:0] line_text;
  reg [4:0] line_length;
  reg [7:0] payload_data;
  reg payload_last;
  reg [127:0] saved_line;
  reg [4:0] saved_line_length;
  reg [7:0] character;
  reg [7:0] pixel_byte;
  wire [7:0] pixels;
  wire [54:0] incoming_record = {
    temperature, humidity, distance, sensor_valid, link_valid, link_stale, last_error
  };
  wire i2c_busy;
  wire i2c_done;
  wire i2c_error;
  wire tx_ready;
  wire i2c_start = !rst && state == START_PACKET && !i2c_busy;
  wire tx_valid = state == SEND_BYTES;
  wire signed [15:0] saved_temperature = active_record[54:39];
  wire [15:0] saved_humidity = active_record[38:23];
  wire [15:0] saved_distance = active_record[22:7];
  wire [1:0] saved_valid = active_record[6:5];
  wire saved_link_valid = active_record[4];
  wire [2:0] saved_error = active_record[2:0];
  reg [15:0] magnitude;
  reg negative;
  reg [43:0] temperature_text;
  reg [43:0] humidity_text;
  reg [43:0] distance_text;

  assign busy = state != WAIT_RECORD;

  oled_font u_oled_font (
      .character(character),
      .column(glyph_column),
      .pixels(pixels)
  );
  i2c_master #(
      .HALF_PERIOD_CYCLES(I2C_HALF_PERIOD_CYCLES),
      .WATCHDOG_CYCLES(I2C_WATCHDOG_CYCLES)
  ) u_i2c_master (
      .clk(clk),
      .rst(rst),
      .start(i2c_start),
      .address(selected_address),
      .tx_valid(tx_valid),
      .tx_ready(tx_ready),
      .tx_data(payload_data),
      .tx_last(payload_last),
      .busy(i2c_busy),
      .done(i2c_done),
      .error(i2c_error),
      .scl(scl),
      .sda(sda)
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

  function [43:0] format_value;
    input [15:0] value;
    input is_negative;
    input fractional;
    input valid;
    reg [15:0] digits;
    reg [39:0] text;
    reg [ 3:0] length;
    reg [ 3:0] hundreds;
    reg [ 3:0] tens;
    reg [ 3:0] ones;
    begin
      digits = decimal_digits(value[9:0]);
      hundreds = fractional ? digits[15:12] : digits[11:8];
      tens = fractional ? digits[11:8] : digits[7:4];
      ones = fractional ? digits[7:4] : digits[3:0];
      text = 40'b0;
      length = 0;
      if (!valid) begin
        text   = "--";
        length = 2;
      end else begin
        if (is_negative) begin
          text   = "-";
          length = 1;
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

  function [7:0] init_byte;
    input [7:0] index;
    begin
      case (index)
        0: init_byte = 8'h00;
        1: init_byte = 8'hAE;
        2: init_byte = 8'hD5;
        3: init_byte = 8'h80;
        4: init_byte = 8'hA8;
        5: init_byte = 8'h3F;
        6: init_byte = 8'hD3;
        7: init_byte = 8'h00;
        8: init_byte = 8'h40;
        9: init_byte = 8'h8D;
        10: init_byte = 8'h14;
        11: init_byte = 8'h20;
        12: init_byte = 8'h02;
        13: init_byte = 8'hA1;
        14: init_byte = 8'hC8;
        15: init_byte = 8'hDA;
        16: init_byte = 8'h12;
        17: init_byte = 8'h81;
        18: init_byte = 8'h7F;
        19: init_byte = 8'hD9;
        20: init_byte = 8'hF1;
        21: init_byte = 8'hDB;
        22: init_byte = 8'h20;
        23: init_byte = 8'hA4;
        24: init_byte = 8'hA6;
        default: init_byte = 8'h2E;
      endcase
    end
  endfunction

  always @* begin
    negative  = saved_temperature < 16'sd0;
    magnitude = negative ? -saved_temperature : saved_temperature;
  end

  // 수치 변환을 저장해 Glyph 생성 경로와 분리한다.
  always @(posedge clk) begin
    if (state == PREPARE_PACKET) begin
      temperature_text <= format_value(magnitude, negative, 1'b1, saved_valid[0]);
      humidity_text <= format_value(saved_humidity, 1'b0, 1'b1, saved_valid[0]);
      distance_text <= format_value(saved_distance, 1'b0, 1'b0, saved_valid[1]);
    end
  end

  always @* begin
    line_text   = 128'b0;
    line_length = 0;
    case (page)
      0: begin
        line_text   = "SENSOR MONITOR";
        line_length = 14;
      end
      1: begin
        line_text = (128'h543A20 << ((temperature_text[43:40]+1)*8)) |
            ({88'b0, temperature_text[39:0]} << 8) | 128'h43;
        line_length = {1'b0, temperature_text[43:40]} + 5'd4;
      end
      2: begin
        line_text = (128'h483A20 << ((humidity_text[43:40]+1)*8)) |
            ({88'b0, humidity_text[39:0]} << 8) | 128'h25;
        line_length = {1'b0, humidity_text[43:40]} + 5'd4;
      end
      3: begin
        line_text = (128'h443A20 << ((distance_text[43:40]+2)*8)) |
            ({88'b0, distance_text[39:0]} << 16) | 128'h434D;
        line_length = {1'b0, distance_text[43:40]} + 5'd5;
      end
      4: begin
        line_text   = saved_link_valid ? "LINK: OK" : "LINK: ERR";
        line_length = saved_link_valid ? 8 : 9;
      end
      5: begin
        case (saved_error)
          1: begin
            line_text   = "ERR: TIMEOUT";
            line_length = 12;
          end
          2: begin
            line_text   = "ERR: LENGTH";
            line_length = 11;
          end
          3: begin
            line_text   = "ERR: HEADER";
            line_length = 11;
          end
          4: begin
            line_text   = "ERR: XOR";
            line_length = 8;
          end
          5: begin
            line_text   = "ERR: RESERVED";
            line_length = 13;
          end
          6: begin
            line_text   = "ERR: RANGE";
            line_length = 10;
          end
          7: begin
            line_text   = "ERR: STALE";
            line_length = 10;
          end
          default: begin
            line_text   = "ERR: NONE";
            line_length = 9;
          end
        endcase
      end
      6: begin
        line_text   = "SPI MODE0";
        line_length = 9;
      end
      default: begin
        line_text   = "FPGA MASTER";
        line_length = 11;
      end
    endcase
  end

  always @* begin
    payload_data = 8'b0;
    payload_last = 1'b0;
    case (packet_kind)
      INIT: begin
        payload_data = init_byte(byte_index);
        payload_last = byte_index == 25;
      end
      PAGE_COMMAND: begin
        case (byte_index)
          0: payload_data = 8'h00;
          1: payload_data = 8'hB0 | {5'b0, page};
          2: payload_data = 8'h00;
          default: payload_data = 8'h10;
        endcase
        payload_last = byte_index == 3;
      end
      PAGE_DATA: begin
        payload_data = byte_index == 0 ? 8'h40 : pixel_byte;
        payload_last = byte_index == 128;
      end
      default: begin
        payload_data = byte_index == 0 ? 8'h00 : 8'hAF;
        payload_last = byte_index == 1;
      end
    endcase
  end

  // synthesis translate_off
  initial begin
    if (POWERUP_CYCLES < 1 || RETRY_CYCLES < 1) begin
      $display("ERROR: invalid OLED wait parameters");
      $finish;
    end
  end
  // synthesis translate_on

  always @(posedge clk) begin
    if (rst) begin
      state <= POWER_WAIT;
      wait_count <= {TIMER_WIDTH{1'b0}};
      pending_valid <= 1'b0;
      refresh_due <= 1'b1;
      need_init <= 1'b1;
      address_locked <= 1'b0;
      selected_address <= 7'h3C;
      page <= 0;
      byte_index <= 0;
      character_index <= 0;
      glyph_column <= 0;
      packet_kind <= INIT;
      oled_fault <= 1'b1;
    end else begin
      if (report_update) begin
        pending_record <= incoming_record;
        pending_valid  <= 1'b1;
      end
      if (i2c_done && i2c_error) begin
        // 실패한 Byte부터 이어 쓰지 않고 최신 Snapshot으로 전체를 재초기화한다.
        oled_fault <= 1'b1;
        need_init <= 1'b1;
        wait_count <= {TIMER_WIDTH{1'b0}};
        state <= RETRY_WAIT;
        if (!address_locked) begin
          selected_address <= selected_address == 7'h3C ? 7'h3D : 7'h3C;
        end
      end else begin
        case (state)
          POWER_WAIT, RETRY_WAIT: begin
            if ((state == POWER_WAIT && wait_count == POWERUP_LAST) ||
                (state == RETRY_WAIT && wait_count == RETRY_LAST)) begin
              wait_count <= {TIMER_WIDTH{1'b0}};
              refresh_due <= 1'b1;
              state <= WAIT_RECORD;
            end else begin
              wait_count <= wait_count + 1'b1;
            end
          end
          WAIT_RECORD: begin
            if (refresh_due || pending_valid || report_update) begin
              active_record <= report_update ? incoming_record : pending_valid ? pending_record : incoming_record;
              pending_valid <= 1'b0;
              refresh_due <= 1'b0;
              page <= 0;
              packet_kind <= need_init ? INIT : PAGE_COMMAND;
              state <= PREPARE_PACKET;
            end
          end
          PREPARE_PACKET: begin
            byte_index <= 0;
            character_index <= 0;
            glyph_column <= 0;
            state <= LATCH_LINE;
          end
          LATCH_LINE: begin
            saved_line <= line_text;
            saved_line_length <= line_length;
            state <= START_PACKET;
          end
          LOAD_CHARACTER: begin
            character <= character_index < saved_line_length ?
                saved_line[(saved_line_length-1-character_index)*8 +: 8] : 8'h20;
            state <= LOAD_PIXEL;
          end
          LOAD_PIXEL: begin
            pixel_byte <= pixels;
            state <= SEND_BYTES;
          end
          START_PACKET: begin
            if (i2c_start) begin
              state <= SEND_BYTES;
            end
          end
          SEND_BYTES: begin
            if (tx_ready) begin
              if (packet_kind == PAGE_DATA && byte_index != 0) begin
                if (glyph_column == 5) begin
                  glyph_column <= 0;
                  character_index <= character_index + 1'b1;
                end else begin
                  glyph_column <= glyph_column + 1'b1;
                end
              end
              if (payload_last) begin
                state <= WAIT_PACKET;
              end else begin
                byte_index <= byte_index + 1'b1;
                state <= LOAD_CHARACTER;
              end
            end
          end
          WAIT_PACKET: begin
            if (i2c_done) begin
              case (packet_kind)
                INIT: begin
                  address_locked <= 1'b1;
                  packet_kind <= PAGE_COMMAND;
                  state <= PREPARE_PACKET;
                end
                PAGE_COMMAND: begin
                  packet_kind <= PAGE_DATA;
                  state <= PREPARE_PACKET;
                end
                PAGE_DATA: begin
                  if (page == 7) begin
                    if (need_init) begin
                      packet_kind <= DISPLAY_ON;
                      state <= PREPARE_PACKET;
                    end else begin
                      oled_fault <= 1'b0;
                      state <= WAIT_RECORD;
                    end
                  end else begin
                    page <= page + 1'b1;
                    packet_kind <= PAGE_COMMAND;
                    state <= PREPARE_PACKET;
                  end
                end
                default: begin
                  need_init <= 1'b0;
                  oled_fault <= 1'b0;
                  state <= WAIT_RECORD;
                end
              endcase
            end
          end
          default: begin
            oled_fault <= 1'b1;
            need_init <= 1'b1;
            state <= RETRY_WAIT;
            wait_count <= {TIMER_WIDTH{1'b0}};
          end
        endcase
      end
    end
  end
endmodule
