module dht11_sensor(
    input clk, reset,
    inout dht11_data,
    output reg done, valid,
    output reg signed [15:0] temperature,
    output reg [15:0] humidity
);
    localparam WAIT=0, START=1, ACK_LOW=2, ACK_HIGH=3,
               ACK_END=4, BIT_RISE=5, BIT_FALL=6, CHECK=7;
    reg [2:0] state;
    reg [27:0] timer;
    reg [5:0] bit_index;
    reg [39:0] frame;
    (* ASYNC_REG="TRUE" *) reg data_meta, data_sync;
    wire [7:0] checksum = frame[39:32] + frame[31:24] +
                          frame[23:16] + frame[15:8];
    wire [15:0] hum = frame[39:32] * 16'd10 + frame[31:24];
    wire signed [15:0] magnitude = frame[23:16] * 16'd10 + frame[14:8];
    wire signed [15:0] temp = frame[15] ? -magnitude : magnitude;
    wire frame_valid = checksum == frame[7:0] && frame[31:24] <= 9 &&
                       frame[14:8] <= 9 && hum <= 1000 &&
                       temp >= -16'sd200 && temp <= 16'sd600;

    assign dht11_data = (!reset && state == START) ? 1'b0 : 1'bz;

    always @(posedge clk) begin
        data_meta <= dht11_data;
        data_sync <= data_meta;
        if (reset) begin
            state <= WAIT;
            timer <= 0;
            bit_index <= 0;
            frame <= 0;
            done <= 0;
            valid <= 0;
            temperature <= 0;
            humidity <= 0;
        end else begin
            done <= 0;
            timer <= timer + 1'b1;
            if (state >= ACK_LOW && state <= BIT_FALL && timer == 20000) begin
                state <= WAIT;
                timer <= 0;
                done <= 1;
                valid <= 0;
            end else case (state)
                WAIT: if (timer == 199999999) begin
                    state <= START;
                    timer <= 0;
                    bit_index <= 0;
                end
                START: if (timer == 1799999) begin
                    state <= ACK_LOW;
                    timer <= 0;
                end
                // Allow the released bus to rise before looking for ACK.
                ACK_LOW: if (timer >= 1000 && !data_sync) begin
                    state <= ACK_HIGH;
                    timer <= 0;
                end
                ACK_HIGH: if (data_sync) begin
                    state <= ACK_END;
                    timer <= 0;
                end
                ACK_END: if (!data_sync) begin
                    state <= BIT_RISE;
                    timer <= 0;
                end
                BIT_RISE: if (data_sync) begin
                    state <= BIT_FALL;
                    timer <= 0;
                end
                BIT_FALL: if (!data_sync) begin
                    frame <= {frame[38:0], timer >= 4999};
                    bit_index <= bit_index + 1'b1;
                    state <= bit_index == 39 ? CHECK : BIT_RISE;
                    timer <= 0;
                end
                CHECK: begin
                    valid <= frame_valid;
                    done <= 1;
                    if (frame_valid) begin
                        temperature <= temp;
                        humidity <= hum;
                    end
                    state <= WAIT;
                    timer <= 0;
                end
                default: begin
                    state <= WAIT;
                    timer <= 0;
                end
            endcase
        end
    end
endmodule
