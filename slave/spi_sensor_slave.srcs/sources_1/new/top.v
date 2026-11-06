module top(
    input clk, reset, echo, spi_cs_n, spi_sclk, spi_mosi,
    input [2:0] sw,
    inout dht11_data,
    output trig, spi_miso,
    output [15:0] led,
    output [6:0] seg,
    output [3:0] an,
    output dp, RsTx
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
    wire [1:0] last_good;
    wire spi_error;
    wire [63:0] display_snapshot = {snapshot[63:50], last_good, snapshot[47:0]};
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
        .spi_error(spi_error), .last_good(last_good),
        .dht_done(dht_done), .dht_valid(dht_valid),
        .temperature(temperature), .humidity(humidity)
    );
    spi_slave link (
        .clk(clk), .reset(system_reset), .spi_cs_n(spi_cs_n), .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi), .snapshot(snapshot), .spi_miso(spi_miso),
        .received_byte(received_byte), .rx_toggle(rx_toggle), .tx_toggle(tx_toggle), .spi_error(spi_error)
    );
    sensor_fnd display (
        .clk(clk), .reset(system_reset), .sw(sw), .snapshot(display_snapshot),
        .trigger_seen(trigger_seen), .echo_seen(echo_seen),
        .seg(seg), .an(an), .dp(dp)
    );
    sensor_error_uart error_uart (
        .clk(clk), .reset(system_reset), .snapshot(snapshot),
        .last_good(last_good), .dht_failed(dht_done && !dht_valid),
        .ultrasonic_failed(done && !valid), .tx(RsTx)
    );
endmodule

module sensor_error_uart(
    input clk, reset,
    input [63:0] snapshot,
    input [1:0] last_good,
    input dht_failed, ultrasonic_failed,
    output tx
);
    reg previous_spi_error;
    reg [2:0] pending, selected;
    reg [303:0] message;
    reg [5:0] remaining;
    reg tx_start;
    reg [7:0] tx_data;
    wire tx_busy;
    wire [2:0] events = {snapshot[52] && !previous_spi_error,
                         dht_failed, ultrasonic_failed};

    function [7:0] digit;
        input [15:0] value;
        begin
            digit = 8'h30 + value % 16'd10;
        end
    endfunction

    function [39:0] decimal_tenths;
        input [15:0] value;
        begin
            decimal_tenths = {digit(value / 16'd1000), digit(value / 16'd100),
                              digit(value / 16'd10), ".", digit(value)};
        end
    endfunction

    wire negative = snapshot[47];
    wire [15:0] temperature = negative ? -snapshot[47:32] : snapshot[47:32];
    wire [7:0] sign_char = negative ? "-" : "+";
    wire [47:0] temp_text = last_good[0] ? {sign_char, decimal_tenths(temperature)} : "   N/A";
    wire [39:0] humidity_text = last_good[0] ? decimal_tenths(snapshot[31:16]) : "  N/A";
    wire [15:0] distance = {7'b0, snapshot[8:0]};
    wire [23:0] distance_text = last_good[1]
        ? {digit(distance / 16'd100), digit(distance / 16'd10), digit(distance)}
        : "N/A";
    // Error reports show only fresh, valid readings from the other sensor.
    // last_good alone also includes retained readings after a sensor failure.
    wire [47:0] current_temp_text = snapshot[48] ? temp_text : "   N/A";
    wire [39:0] current_humidity_text = snapshot[48] ? humidity_text : "  N/A";
    wire [23:0] current_distance_text = snapshot[49] ? distance_text : "N/A";

    uart_tx #(.BPS(9600)) transmitter (
        .clk(clk), .reset(reset), .tx_data(tx_data), .tx_start(tx_start),
        .tx(tx), .tx_busy(tx_busy)
    );

    always @* begin
        selected = 0;
        if (remaining == 0) begin
            if (pending[2]) selected = 3'b100;
            else selected = {1'b0, pending[1:0]};
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            previous_spi_error <= 0;
            pending <= 0;
            message <= 0;
            remaining <= 0;
            tx_start <= 0;
            tx_data <= 0;
        end else begin
            previous_spi_error <= snapshot[52];
            pending <= (pending & ~selected) | events;
            tx_start <= 0;
            case (selected)
                3'b100: begin
                    message <= {"SPI error T=", temp_text, "C H=", humidity_text,
                                "% D=", distance_text, "cm", 8'h0D, 8'h0A};
                    remaining <= 38;
                end
                3'b010: begin
                    if (snapshot[50]) begin
                        message <= {"DHT11 ERROR | ULTRASONIC ERROR", 8'h0D, 8'h0A, 48'b0};
                        remaining <= 32;
                    end else begin
                        message <= {"DHT11 ERROR D=", current_distance_text,
                                    "cm", 8'h0D, 8'h0A, 136'b0};
                        remaining <= 21;
                    end
                end
                3'b001: begin
                    if (snapshot[51]) begin
                        message <= {"DHT11 ERROR | ULTRASONIC ERROR", 8'h0D, 8'h0A, 48'b0};
                        remaining <= 32;
                    end else begin
                        message <= {"ULTRASONIC ERROR T=", current_temp_text,
                                    "C H=", current_humidity_text, "%",
                                    8'h0D, 8'h0A, 8'b0};
                        remaining <= 37;
                    end
                end
                3'b011: begin
                    message <= {"DHT11 ERROR | ULTRASONIC ERROR", 8'h0D, 8'h0A, 48'b0};
                    remaining <= 32;
                end
                default: if (remaining != 0 && !tx_busy && !tx_start) begin
                    tx_start <= 1;
                    tx_data <= message[303:296];
                    message <= {message[295:0], 8'b0};
                    remaining <= remaining - 1'b1;
                end
            endcase
        end
    end
endmodule
