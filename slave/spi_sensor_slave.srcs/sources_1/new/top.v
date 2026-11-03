module top(
    input clk, reset, echo, spi_cs_n, spi_sclk, spi_mosi,
    output trig, spi_miso
);
    reg [23:0] poll_count;
    reg [24:0] age;
    reg [8:0] stored_distance;
    reg stored_valid;
    wire done, valid;
    wire [8:0] distance;
    wire distance_valid = stored_valid && age < 25000000;
    wire [63:0] snapshot = {8'hA5, 6'b0, distance_valid, 1'b0,
                            32'b0, 7'b0, stored_distance};

    ultrasonic_sensor sensor (
        .clk(clk), .reset(reset), .echo(echo), .start_trig(poll_count == 0),
        .trig(trig), .distance(distance), .done(done), .valid(valid)
    );
    spi_slave link (
        .clk(clk), .reset(reset), .spi_cs_n(spi_cs_n), .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi), .snapshot(snapshot), .spi_miso(spi_miso)
    );

    always @(posedge clk) begin
        if (reset) begin
            poll_count <= 0;
            age <= 0;
            stored_distance <= 0;
            stored_valid <= 0;
        end else begin
            if (poll_count == 9999999) poll_count <= 0;
            else poll_count <= poll_count + 1'b1;

            if (age < 25000000) age <= age + 1'b1;
            if (done) begin
                stored_valid <= valid;
                if (valid) begin
                    stored_distance <= distance;
                    age <= 0;
                end
            end
        end
    end
endmodule
