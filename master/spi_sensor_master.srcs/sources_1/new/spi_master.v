`timescale 1ns / 1ps

module spi_master #(
    parameter integer HALF_PERIOD_CYCLES = 500,
    parameter integer CS_SETUP_CYCLES = 500,
    parameter integer CS_HOLD_CYCLES = 500,
    parameter integer CS_GAP_CYCLES = 1000,
    parameter integer WATCHDOG_CYCLES = 200000
) (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [79:0] tx_frame,
    output reg busy,
    output reg done,
    output reg error,
    output reg [79:0] rx_frame,
    output reg [6:0] rx_bits,
    output reg spi_cs_n,
    output reg spi_sclk,
    output reg spi_mosi,
    input wire spi_miso
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
      if (count_width == 0) count_width = 1;
    end
  endfunction

  function integer maximum;
    input integer a;
    input integer b;
    begin
      maximum = (a > b) ? a : b;
    end
  endfunction

  localparam integer PHASE_MAX = maximum(
      maximum(HALF_PERIOD_CYCLES, CS_SETUP_CYCLES), maximum(CS_HOLD_CYCLES, CS_GAP_CYCLES)
  );
  localparam integer PHASE_WIDTH = count_width(PHASE_MAX - 1);
  localparam integer WATCHDOG_WIDTH = count_width(WATCHDOG_CYCLES);
  localparam [PHASE_WIDTH-1:0] HALF_LAST = HALF_PERIOD_CYCLES - 1;
  localparam [PHASE_WIDTH-1:0] SETUP_LAST = CS_SETUP_CYCLES - 1;
  localparam [PHASE_WIDTH-1:0] HOLD_LAST = CS_HOLD_CYCLES - 1;
  localparam [PHASE_WIDTH-1:0] GAP_LAST = CS_GAP_CYCLES - 1;
  localparam [WATCHDOG_WIDTH-1:0] WATCHDOG_LIMIT = WATCHDOG_CYCLES;
  localparam [2:0] IDLE = 3'd0, CS_SETUP = 3'd1, TRANSFER = 3'd2, CS_HOLD = 3'd3, CS_GAP = 3'd4;

  reg [2:0] state;
  reg [PHASE_WIDTH-1:0] phase_count;
  reg [WATCHDOG_WIDTH-1:0] watchdog_count;
  reg [79:0] tx_shift;
  reg [79:0] rx_shift;
  reg completion_pending;
  (* ASYNC_REG = "TRUE" *) reg miso_meta;
  (* ASYNC_REG = "TRUE" *) reg miso_sync;

  // synthesis translate_off
  initial begin
    if (HALF_PERIOD_CYCLES < 1 || CS_SETUP_CYCLES < 1 ||
            CS_HOLD_CYCLES < 1 || CS_GAP_CYCLES < 1 || WATCHDOG_CYCLES < 1) begin
      $display("ERROR: spi_master cycle parameters must be positive");
      $finish;
    end
  end
  // synthesis translate_on

  always @(posedge clk) begin
    if (rst) begin
      miso_meta <= 1'b0;
      miso_sync <= 1'b0;
    end else begin
      miso_meta <= spi_miso;
      miso_sync <= miso_meta;
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      state <= CS_GAP;
      phase_count <= {PHASE_WIDTH{1'b0}};
      watchdog_count <= {WATCHDOG_WIDTH{1'b0}};
      tx_shift <= 80'b0;
      rx_shift <= 80'b0;
      completion_pending <= 1'b0;
      busy <= 1'b1;
      done <= 1'b0;
      error <= 1'b0;
      rx_frame <= 80'b0;
      rx_bits <= 7'd0;
      spi_cs_n <= 1'b1;
      spi_sclk <= 1'b0;
      spi_mosi <= 1'b0;
    end else begin
      done <= 1'b0;
      if (spi_cs_n) watchdog_count <= {WATCHDOG_WIDTH{1'b0}};
      else watchdog_count <= watchdog_count + 1'b1;

      // This timer runs on clk, even when SPI phase progression stalls.
      // Starting at zero on CS assertion makes expiry strictly > 2ms.
      if (!spi_cs_n && watchdog_count == WATCHDOG_LIMIT) begin
        spi_cs_n <= 1'b1;
        spi_sclk <= 1'b0;
        spi_mosi <= 1'b0;
        rx_frame <= rx_shift;
        error <= 1'b1;
        state <= CS_GAP;
        phase_count <= {PHASE_WIDTH{1'b0}};
        watchdog_count <= {WATCHDOG_WIDTH{1'b0}};
      end else begin
        case (state)
          IDLE: begin
            if (start) begin
              tx_shift <= tx_frame;
              rx_shift <= 80'b0;
              rx_frame <= 80'b0;
              rx_bits <= 7'd0;
              error <= 1'b0;
              busy <= 1'b1;
              completion_pending <= 1'b1;
              spi_cs_n <= 1'b0;
              spi_mosi <= tx_frame[79];
              phase_count <= {PHASE_WIDTH{1'b0}};
              state <= CS_SETUP;
            end
          end
          CS_SETUP: begin
            if (phase_count == SETUP_LAST) begin
              spi_sclk <= 1'b1;
              rx_shift <= {rx_shift[78:0], miso_sync};
              rx_bits <= 7'd1;
              phase_count <= {PHASE_WIDTH{1'b0}};
              state <= TRANSFER;
            end else phase_count <= phase_count + 1'b1;
          end
          TRANSFER: begin
            if (phase_count == HALF_LAST) begin
              phase_count <= {PHASE_WIDTH{1'b0}};
              if (spi_sclk) begin
                spi_sclk <= 1'b0;
                if (rx_bits == 7'd80) begin
                  spi_mosi <= 1'b0;
                  rx_frame <= rx_shift;
                  state <= CS_HOLD;
                end else begin
                  tx_shift <= {tx_shift[78:0], 1'b0};
                  spi_mosi <= tx_shift[78];
                end
              end else begin
                spi_sclk <= 1'b1;
                rx_shift <= {rx_shift[78:0], miso_sync};
                rx_bits  <= rx_bits + 1'b1;
              end
            end else phase_count <= phase_count + 1'b1;
          end
          CS_HOLD: begin
            if (phase_count == HOLD_LAST) begin
              spi_cs_n <= 1'b1;
              phase_count <= {PHASE_WIDTH{1'b0}};
              state <= CS_GAP;
            end else phase_count <= phase_count + 1'b1;
          end
          CS_GAP: begin
            if (phase_count == GAP_LAST) begin
              phase_count <= {PHASE_WIDTH{1'b0}};
              state <= IDLE;
              busy <= 1'b0;
              done <= completion_pending;
              completion_pending <= 1'b0;
            end else phase_count <= phase_count + 1'b1;
          end
          default: begin
            spi_cs_n <= 1'b1;
            spi_sclk <= 1'b0;
            spi_mosi <= 1'b0;
            busy <= 1'b1;
            error <= 1'b1;
            rx_frame <= rx_shift;
            state <= CS_GAP;
            phase_count <= {PHASE_WIDTH{1'b0}};
          end
        endcase
      end
    end
  end
endmodule
