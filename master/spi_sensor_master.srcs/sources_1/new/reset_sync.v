`timescale 1ns / 1ps

module reset_sync (
  input wire clk,
  input wire arst,
  output wire rst
);
  (* ASYNC_REG = "TRUE" *) reg reset_meta = 1'b1;
  (* ASYNC_REG = "TRUE" *) reg reset_synced = 1'b1;

  // Power-on은 Reset으로 시작하고 해제만 두 Clock에 걸쳐 동기화한다.
  always @(posedge clk or posedge arst) begin
    if (arst) begin
      reset_meta <= 1'b1;
      reset_synced <= 1'b1;
    end else begin
      reset_meta <= 1'b0;
      reset_synced <= reset_meta;
    end
  end

  assign rst = reset_synced;
endmodule
