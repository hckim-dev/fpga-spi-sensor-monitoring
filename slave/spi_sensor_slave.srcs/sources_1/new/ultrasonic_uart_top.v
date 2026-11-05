module ultrasonic_uart_top(
    input clk, reset, echo,
    output trig, RsTx
);
    wire start_trig, done, valid;
    wire [8:0] distance;
    wire [63:0] snapshot;
    wire tx_busy;
    reg tx_start;
    reg [7:0] tx_data;
    reg [63:0] message;
    reg [3:0] remaining;

    ultrasonic_sensor sensor (
        .clk(clk), .reset(reset), .echo(echo), .start_trig(start_trig),
        .trig(trig), .distance(distance), .done(done), .valid(valid)
    );
    control_unit control (
        .clk(clk), .reset(reset), .done(done), .valid(valid),
        .distance(distance), .start_trig(start_trig), .snapshot(snapshot),
        .spi_error(1'b0), .last_good(), .dht_done(1'b0), .dht_valid(1'b0), .temperature(16'b0), .humidity(16'b0)
    );
    uart_tx #(.BPS(9600)) transmitter (
        .clk(clk), .reset(reset), .tx_data(tx_data), .tx_start(tx_start),
        .tx(RsTx), .tx_busy(tx_busy)
    );

    wire [7:0] hundreds = 8'h30 + distance / 100;
    wire [7:0] tens = 8'h30 + (distance / 10) % 10;
    wire [7:0] ones = 8'h30 + distance % 10;

    always @(posedge clk) begin
        if (reset) begin
            tx_start <= 0;
            tx_data <= 0;
            message <= 0;
            remaining <= 0;
        end else begin
            tx_start <= 0;
            if (remaining == 0) begin
                if (done) begin
                    if (valid)
                        message <= {hundreds, tens, ones, " cm", 8'h0D, 8'h0A};
                    else
                        message <= {"NOECHO", 8'h0D, 8'h0A};
                    remaining <= 8;
                end
            end else if (!tx_busy && !tx_start) begin
                tx_start <= 1;
                tx_data <= message[63:56];
                message <= {message[55:0], 8'b0};
                remaining <= remaining - 1'b1;
            end
        end
    end
endmodule


