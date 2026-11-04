module top(
    input clk, reset, echo, spi_cs_n, spi_sclk, spi_mosi,
    input [2:0] sw,
    inout dht11_data,
    output trig, spi_miso,
    output [15:0] led,
    output [6:0] seg,
    output [3:0] an,
    output dp
);
    // Hold the design in reset at configuration and release on clk.
    (* ASYNC_REG="TRUE" *) reg [1:0] reset_sync = 2'b11;
    always @(posedge clk or posedge reset) begin
        if (reset) reset_sync <= 2'b11;
        else reset_sync <= {reset_sync[0], 1'b0};
    end
    wire system_reset = reset_sync[1];

    wire start_trig, done, valid;
    wire [8:0] distance;
    wire [63:0] snapshot;
    wire dht_done, dht_valid;
    wire signed [15:0] temperature;
    wire [15:0] humidity;

    dht11_sensor dht (
        .clk(clk), .reset(system_reset), .dht11_data(dht11_data),
        .done(dht_done), .valid(dht_valid),
        .temperature(temperature), .humidity(humidity)
    );
    wire [7:0] received_byte;
    wire rx_toggle, tx_toggle;

    (* ASYNC_REG="TRUE" *) reg echo_debug_meta, echo_debug_sync;
    reg trigger_toggle, trigger_seen, echo_seen;

    always @(posedge clk) begin
        if (system_reset) begin
            echo_debug_meta <= 0;
            echo_debug_sync <= 0;
            trigger_toggle <= 0;
            trigger_seen <= 0;
            echo_seen <= 0;
        end else begin
            echo_debug_meta <= echo;
            echo_debug_sync <= echo_debug_meta;
            if (trig) trigger_seen <= 1;
            if (start_trig) trigger_toggle <= ~trigger_toggle;
            if (echo_debug_sync) echo_seen <= 1;
        end
    end

    assign led = {!spi_cs_n, 2'b0, snapshot[49], echo_seen, trigger_toggle,
                  tx_toggle, rx_toggle, received_byte};

    ultrasonic_sensor sensor (
        .clk(clk), .reset(system_reset), .echo(echo), .start_trig(start_trig),
        .trig(trig), .distance(distance), .done(done), .valid(valid)
    );
    control_unit control (
        .clk(clk), .reset(system_reset), .done(done), .valid(valid),
        .distance(distance), .start_trig(start_trig), .snapshot(snapshot),
        .dht_done(dht_done), .dht_valid(dht_valid),
        .temperature(temperature), .humidity(humidity)
    );
    spi_slave link (
        .clk(clk), .reset(system_reset), .spi_cs_n(spi_cs_n), .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi), .snapshot(snapshot), .spi_miso(spi_miso),
        .received_byte(received_byte), .rx_toggle(rx_toggle), .tx_toggle(tx_toggle)
    );
    sensor_fnd display (
        .clk(clk), .reset(system_reset), .sw(sw), .snapshot(snapshot),
        .trigger_seen(trigger_seen), .echo_seen(echo_seen),
        .seg(seg), .an(an), .dp(dp)
    );
endmodule





