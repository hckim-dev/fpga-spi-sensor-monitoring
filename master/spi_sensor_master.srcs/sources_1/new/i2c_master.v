`timescale 1ns / 1ps

module i2c_master #(
    parameter integer HALF_PERIOD_CYCLES = 500,
    parameter integer WATCHDOG_CYCLES = 2000000,
    parameter integer MAX_TX_BYTES = 129
) (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [6:0] address,
    input wire tx_valid,
    output wire tx_ready,
    input wire [7:0] tx_data,
    input wire tx_last,
    output reg busy,
    output reg done,
    output reg error,
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

  localparam integer PHASE_WIDTH = count_width(HALF_PERIOD_CYCLES - 1);
  localparam integer WATCHDOG_WIDTH = count_width(WATCHDOG_CYCLES - 1);
  localparam integer BYTE_WIDTH = count_width(MAX_TX_BYTES);
  localparam [PHASE_WIDTH-1:0] HALF_LAST = HALF_PERIOD_CYCLES - 1;
  localparam [WATCHDOG_WIDTH-1:0] WATCHDOG_LAST = WATCHDOG_CYCLES - 1;
  localparam [BYTE_WIDTH-1:0] BYTE_LIMIT = MAX_TX_BYTES;
  localparam [3:0] IDLE = 4'd0;
  localparam [3:0] BUS_FREE = 4'd1;
  localparam [3:0] START_HOLD = 4'd2;
  localparam [3:0] BIT_LOW = 4'd3;
  localparam [3:0] BIT_HIGH_WAIT = 4'd4;
  localparam [3:0] BIT_HIGH = 4'd5;
  localparam [3:0] ACK_LOW = 4'd6;
  localparam [3:0] ACK_HIGH_WAIT = 4'd7;
  localparam [3:0] ACK_HIGH = 4'd8;
  localparam [3:0] WAIT_BYTE = 4'd9;
  localparam [3:0] STOP_LOW = 4'd10;
  localparam [3:0] STOP_HIGH_WAIT = 4'd11;
  localparam [3:0] STOP_HIGH = 4'd12;
  localparam [3:0] FINISH_GAP = 4'd13;

  reg [3:0] state;
  reg [PHASE_WIDTH-1:0] phase_count;
  reg [WATCHDOG_WIDTH-1:0] watchdog_count;
  reg [BYTE_WIDTH-1:0] byte_count;
  reg [7:0] shift;
  reg [2:0] bit_index;
  reg address_phase;
  reg last_byte;
  reg scl_low;
  reg sda_low;
  (* ASYNC_REG = "TRUE" *) reg scl_meta;
  (* ASYNC_REG = "TRUE" *) reg scl_synced;
  (* ASYNC_REG = "TRUE" *) reg sda_meta;
  (* ASYNC_REG = "TRUE" *) reg sda_synced;

  // High는 구동하지 않고 해제하며, 실제 Pin을 동기화해 읽는다.
  assign scl = scl_low ? 1'b0 : 1'bz;
  assign sda = sda_low ? 1'b0 : 1'bz;
  assign tx_ready = !rst && busy && state == WAIT_BYTE;

  // synthesis translate_off
  initial begin
    if (HALF_PERIOD_CYCLES < 4 || WATCHDOG_CYCLES < 1 || MAX_TX_BYTES < 1) begin
      $display("ERROR: invalid i2c_master cycle or packet parameters");
      $finish;
    end
  end
  // synthesis translate_on

  always @(posedge clk) begin
    if (rst) begin
      scl_meta   <= 1'b1;
      scl_synced <= 1'b1;
      sda_meta   <= 1'b1;
      sda_synced <= 1'b1;
    end else begin
      scl_meta   <= scl;
      scl_synced <= scl_meta;
      sda_meta   <= sda;
      sda_synced <= sda_meta;
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      phase_count <= {PHASE_WIDTH{1'b0}};
      watchdog_count <= {WATCHDOG_WIDTH{1'b0}};
      byte_count <= {BYTE_WIDTH{1'b0}};
      shift <= 8'b0;
      bit_index <= 3'd7;
      address_phase <= 1'b0;
      last_byte <= 1'b0;
      scl_low <= 1'b0;
      sda_low <= 1'b0;
      busy <= 1'b0;
      done <= 1'b0;
      error <= 1'b0;
    end else begin
      done <= 1'b0;
      if (busy) begin
        watchdog_count <= watchdog_count + 1'b1;
      end

      // Bus·Clock Stretch·Byte 공급 대기 모두 같은 Packet Watchdog에 포함한다.
      if (busy && watchdog_count == WATCHDOG_LAST) begin
        scl_low <= 1'b0;
        sda_low <= 1'b0;
        busy <= 1'b0;
        done <= 1'b1;
        error <= 1'b1;
        state <= IDLE;
      end else begin
        case (state)
          IDLE: begin
            if (start) begin
              shift <= {address, 1'b0};
              address_phase <= 1'b1;
              last_byte <= 1'b0;
              byte_count <= {BYTE_WIDTH{1'b0}};
              bit_index <= 3'd7;
              phase_count <= {PHASE_WIDTH{1'b0}};
              watchdog_count <= {WATCHDOG_WIDTH{1'b0}};
              busy <= 1'b1;
              error <= 1'b0;
              state <= BUS_FREE;
            end
          end
          BUS_FREE, FINISH_GAP: begin
            if (scl_synced && sda_synced) begin
              if (phase_count == HALF_LAST) begin
                phase_count <= {PHASE_WIDTH{1'b0}};
                if (state == BUS_FREE) begin
                  sda_low <= 1'b1;
                  state   <= START_HOLD;
                end else begin
                  busy  <= 1'b0;
                  done  <= 1'b1;
                  state <= IDLE;
                end
              end else begin
                phase_count <= phase_count + 1'b1;
              end
            end else begin
              phase_count <= {PHASE_WIDTH{1'b0}};
            end
          end
          START_HOLD: begin
            if (phase_count == HALF_LAST) begin
              scl_low <= 1'b1;
              phase_count <= {PHASE_WIDTH{1'b0}};
              state <= BIT_LOW;
            end else begin
              phase_count <= phase_count + 1'b1;
            end
          end
          BIT_LOW, ACK_LOW, STOP_LOW: begin
            if (state == BIT_LOW) begin
              sda_low <= !shift[7];
            end else begin
              sda_low <= state == STOP_LOW;
            end
            if (phase_count == HALF_LAST) begin
              scl_low <= 1'b0;
              phase_count <= {PHASE_WIDTH{1'b0}};
              case (state)
                BIT_LOW: state <= BIT_HIGH_WAIT;
                ACK_LOW: state <= ACK_HIGH_WAIT;
                default: state <= STOP_HIGH_WAIT;
              endcase
            end else begin
              phase_count <= phase_count + 1'b1;
            end
          end
          BIT_HIGH_WAIT, ACK_HIGH_WAIT, STOP_HIGH_WAIT: begin
            if (scl_synced) begin
              phase_count <= {PHASE_WIDTH{1'b0}};
              case (state)
                BIT_HIGH_WAIT: state <= BIT_HIGH;
                ACK_HIGH_WAIT: state <= ACK_HIGH;
                default: state <= STOP_HIGH;
              endcase
            end
          end
          BIT_HIGH, ACK_HIGH, STOP_HIGH: begin
            if (!scl_synced) begin
              phase_count <= {PHASE_WIDTH{1'b0}};
            end else if (phase_count == HALF_LAST) begin
              phase_count <= {PHASE_WIDTH{1'b0}};
              if (state == STOP_HIGH) begin
                sda_low <= 1'b0;
                state   <= FINISH_GAP;
              end else begin
                scl_low <= 1'b1;
                if (state == BIT_HIGH) begin
                  if (bit_index == 0) begin
                    state <= ACK_LOW;
                  end else begin
                    shift <= {shift[6:0], 1'b0};
                    bit_index <= bit_index - 1'b1;
                    state <= BIT_LOW;
                  end
                end else if (sda_synced) begin
                  error <= 1'b1;
                  state <= STOP_LOW;
                end else if (address_phase) begin
                  address_phase <= 1'b0;
                  state <= WAIT_BYTE;
                end else if (last_byte) begin
                  state <= STOP_LOW;
                end else if (byte_count == BYTE_LIMIT) begin
                  error <= 1'b1;
                  state <= STOP_LOW;
                end else begin
                  state <= WAIT_BYTE;
                end
              end
            end else begin
              phase_count <= phase_count + 1'b1;
            end
          end
          WAIT_BYTE: begin
            if (tx_valid) begin
              shift <= tx_data;
              last_byte <= tx_last;
              byte_count <= byte_count + 1'b1;
              bit_index <= 3'd7;
              phase_count <= {PHASE_WIDTH{1'b0}};
              state <= BIT_LOW;
            end
          end
          default: begin
            scl_low <= 1'b0;
            sda_low <= 1'b0;
            busy <= 1'b0;
            done <= 1'b1;
            error <= 1'b1;
            state <= IDLE;
          end
        endcase
      end
    end
  end
endmodule
