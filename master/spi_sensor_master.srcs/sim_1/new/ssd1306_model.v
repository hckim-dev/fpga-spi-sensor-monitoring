`timescale 1ns / 1ps

// ACK와 Page RAM만 모델링하며 실제 발광·전원 동작을 대신하지 않는다.
module ssd1306_model (
  input wire scl,
  inout wire sda,
  input wire present,
  input wire [6:0] address,
  input wire nack_data,
  input wire [2:0] nack_page
);
  reg sda_low = 1'b0;
  reg active = 1'b0;
  reg packet_ok = 1'b0;
  reg packet_for_us = 1'b0;
  reg [7:0] shift = 8'b0;
  reg [7:0] received [0:130];
  reg [7:0] ram [0:1023];
  integer bit_count = 0;
  integer byte_count = 0;
  integer packets = 0;
  integer init_count = 0;
  integer frames = 0;
  integer on_count = 0;
  integer addresses_3c = 0;
  integer addresses_3d = 0;
  integer failures = 0;
  integer page = 0;
  integer column = 0;
  reg [7:0] completed_pages = 8'b0;
  integer i;
  reg reject_byte;

  assign sda = sda_low ? 1'b0 : 1'bz;
  initial begin
    for (i = 0; i < 1024; i = i + 1) ram[i] = 8'hFF;
  end

  always @(negedge sda) begin
    if (scl) begin
      active = 1;
      bit_count = 0;
      byte_count = 0;
      shift = 0;
      packet_for_us = 0;
      packet_ok = 1;
    end
  end

  always @(posedge scl) begin
    if (active) begin
      bit_count = bit_count + 1;
      if (bit_count <= 8) begin
        shift = {shift[6:0], sda};
        if (bit_count == 8) begin
          if (byte_count < 131) received[byte_count] = shift;
          if (byte_count == 0) begin
            packet_for_us = shift === {address, 1'b0} && present;
            if (shift == 8'h78) addresses_3c = addresses_3c + 1;
            if (shift == 8'h7A) addresses_3d = addresses_3d + 1;
          end
          byte_count = byte_count + 1;
        end
      end
    end
  end

  always @(negedge scl) begin
    if (active) begin
      if (bit_count == 8) begin
        reject_byte = !packet_for_us || !present ||
            (nack_data && received[1] == 8'h40 && page == nack_page && byte_count == 12);
        sda_low = !reject_byte;
        if (reject_byte) packet_ok = 0;
        if (packet_ok && byte_count > 2 && received[1] == 8'h40) begin
          if (column < 128) ram[page*128+column] = received[byte_count-1];
          column = column + 1;
        end
      end else if (bit_count == 9) begin
        sda_low = 0;
        bit_count = 0;
      end
    end
  end

  always @(posedge sda) begin
    if (scl && active) begin
      active = 0;
      if (packet_for_us && packet_ok) begin
        packets = packets + 1;
        if (byte_count == 27 && received[1] == 0 && received[2] == 8'hAE) begin
          init_count = init_count + 1;
          completed_pages = 0;
          if (received[5] != 8'hA8 || received[6] != 8'h3F ||
              received[10] != 8'h8D || received[11] != 8'h14 ||
              received[12] != 8'h20 || received[13] != 8'h02 || received[23] != 8'h20 ||
              received[25] != 8'hA6 || received[26] != 8'h2E) begin
            failures = failures + 1;
            $display("FAIL: SSD1306 init bytes");
          end
        end else if (byte_count == 5 && received[1] == 0 && received[2][7:3] == 5'b10110) begin
          page = received[2][2:0];
          column = 0;
          if (page == 0) completed_pages = 0;
          if (received[3] != 0 || received[4] != 8'h10) begin
            failures = failures + 1;
            $display("FAIL: SSD1306 column reset");
          end
        end else if (received[1] == 8'h40) begin
          if (byte_count > 130 || column > 128) begin
            failures = failures + 1;
            $display("FAIL: SSD1306 page length");
          end
          completed_pages[page] = byte_count == 130 && column == 128;
          if (page == 7 && completed_pages == 8'hFF) frames = frames + 1;
        end else if (byte_count == 3 && received[1] == 0 && received[2] == 8'hAF) begin
          on_count = on_count + 1;
        end else begin
          failures = failures + 1;
          $display("FAIL: unexpected OLED packet length=%0d", byte_count);
        end
      end
    end
  end
endmodule
