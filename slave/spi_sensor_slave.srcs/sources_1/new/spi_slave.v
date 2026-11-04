module spi_slave(
    input clk, reset, spi_cs_n, spi_sclk, spi_mosi,
    input [63:0] snapshot,
    output spi_miso,
    output reg [7:0] received_byte,
    output reg rx_toggle, tx_toggle
);
    (* ASYNC_REG="TRUE" *) reg cs_meta, cs_sync, sclk_meta, sclk_sync, mosi_meta, mosi_sync;
    reg sclk_prev;
    reg armed;
    reg [17:0] elapsed;
    reg [6:0] bits;
    reg [7:0] command;
    reg [71:0] response;
    reg miso;
    wire [7:0] checksum = snapshot[63:56] ^ snapshot[55:48] ^
        snapshot[47:40] ^ snapshot[39:32] ^ snapshot[31:24] ^
        snapshot[23:16] ^ snapshot[15:8] ^ snapshot[7:0];

    // Report the command and one completed response, excluding dummy bytes.
    always @(posedge clk) begin
        if (reset) begin
            received_byte <= 0;
            rx_toggle <= 0;
            tx_toggle <= 0;
        end else if (!cs_sync && armed && elapsed < 200000 &&
                     sclk_sync && !sclk_prev) begin
            if (bits == 7) begin
                received_byte <= {command[6:0], mosi_sync};
                rx_toggle <= ~rx_toggle;
            end
            if (bits == 79 && command == 8'h01)
                tx_toggle <= ~tx_toggle;
        end
    end

    assign spi_miso = spi_cs_n ? 1'bz : (reset ? 1'b0 : miso);

    always @(posedge clk) begin
        cs_meta <= spi_cs_n;
        cs_sync <= cs_meta;
        sclk_meta <= spi_sclk;
        sclk_sync <= sclk_meta;
        sclk_prev <= sclk_sync;
        mosi_meta <= spi_mosi;
        mosi_sync <= mosi_meta;
    end

    always @(posedge clk) begin
        if (reset || cs_sync) begin
            armed <= !reset;
            elapsed <= 0;
            bits <= 0;
            command <= 0;
            response <= 0;
            miso <= 0;
        end else if (armed) begin
            if (elapsed == 200000) begin
                armed <= 0;
                miso <= 0;
            end else begin
                elapsed <= elapsed + 1'b1;
                if (sclk_sync && !sclk_prev && bits < 80) begin
                    bits <= bits + 1'b1;
                    if (bits < 8)
                        command <= {command[6:0], mosi_sync};
                    if (bits == 7 && {command[6:0], mosi_sync} == 8'h01)
                        response <= {snapshot, checksum};
                end
                if (!sclk_sync && sclk_prev && bits >= 8) begin
                    miso <= response[71];
                    response <= {response[70:0], 1'b0};
                end
            end
        end
    end
endmodule

