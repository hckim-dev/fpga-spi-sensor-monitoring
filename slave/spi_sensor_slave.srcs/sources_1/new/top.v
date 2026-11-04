module top(
    input clk, reset, echo, spi_cs_n, spi_sclk, spi_mosi,
    inout dht11_data,
    output trig, spi_miso,
    output [15:0] led
);
    wire start_trig, done, valid;
    wire [8:0] distance;
    wire [63:0] snapshot;
    wire dht_done, dht_valid;
    wire signed [15:0] temperature;
    wire [15:0] humidity;

    dht11_sensor dht (
        .clk(clk), .reset(reset), .dht11_data(dht11_data),
        .done(dht_done), .valid(dht_valid),
        .temperature(temperature), .humidity(humidity)
    );
    wire [7:0] received_byte;
    wire rx_toggle, tx_toggle;

    assign led = {!spi_cs_n, 5'b0, tx_toggle, rx_toggle, received_byte};

    ultrasonic_sensor sensor (
        .clk(clk), .reset(reset), .echo(echo), .start_trig(start_trig),
        .trig(trig), .distance(distance), .done(done), .valid(valid)
    );
    control_unit control (
        .clk(clk), .reset(reset), .done(done), .valid(valid),
        .distance(distance), .start_trig(start_trig), .snapshot(snapshot),
        .dht_done(dht_done), .dht_valid(dht_valid),
        .temperature(temperature), .humidity(humidity)
    );
    spi_slave link (
        .clk(clk), .reset(reset), .spi_cs_n(spi_cs_n), .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi), .snapshot(snapshot), .spi_miso(spi_miso),
        .received_byte(received_byte), .rx_toggle(rx_toggle), .tx_toggle(tx_toggle)
    );
endmodule

