module control_unit(
    input clk, reset, done, valid,
    input [8:0] distance,
    input dht_done, dht_valid,
    input [15:0] temperature, humidity,
    output start_trig,
    output [63:0] snapshot
);
    reg [23:0] poll_count;
    reg [24:0] age;
    reg [8:0] stored_distance;
    reg stored_valid;
    wire distance_valid = stored_valid && age < 25000000;
    reg [28:0] dht_age;
    reg dht_stored_valid;
    reg [15:0] stored_temperature, stored_humidity;
    wire temperature_valid = dht_stored_valid && dht_age < 300000000;

    always @(posedge clk) begin
        if (reset) begin
            dht_age <= 0;
            dht_stored_valid <= 0;
            stored_temperature <= 0;
            stored_humidity <= 0;
        end else begin
            if (dht_age < 300000000) dht_age <= dht_age + 1'b1;
            if (dht_done) begin
                dht_stored_valid <= dht_valid;
                if (dht_valid) begin
                    dht_age <= 0;
                    stored_temperature <= temperature;
                    stored_humidity <= humidity;
                end
            end
        end
    end

    assign snapshot = {8'hA5, 6'b0, distance_valid, temperature_valid,
                            stored_temperature, stored_humidity, 7'b0, stored_distance};


    localparam [23:0] POLL_LAST = 24'd9999999;
    assign start_trig = !reset && poll_count == POLL_LAST;

    always @(posedge clk) begin
        if (reset) begin
            poll_count <= 0;
            age <= 0;
            stored_distance <= 0;
            stored_valid <= 0;
        end else begin
            if (poll_count == POLL_LAST) poll_count <= 0;
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



