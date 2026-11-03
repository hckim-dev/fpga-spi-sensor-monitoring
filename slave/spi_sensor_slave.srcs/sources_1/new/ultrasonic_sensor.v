module ultrasonic_sensor(
    input clk, reset, echo, start_trig,
    output reg trig,
    output reg [8:0] distance,
    output reg done, valid
);
    localparam IDLE=0, TRIGGER=1, WAIT_ECHO=2, MEASURE=3;
    reg [1:0] state;
    reg [21:0] count;
    (* ASYNC_REG="TRUE" *) reg echo_meta, echo_sync;
    wire [21:0] cm = count / 5800;

    always @(posedge clk) begin
        if (reset) begin
            echo_meta <= 0;
            echo_sync <= 0;
        end else begin
            echo_meta <= echo;
            echo_sync <= echo_meta;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            count <= 0;
            trig <= 0;
            distance <= 0;
            done <= 0;
            valid <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE: if (start_trig) begin
                    count <= 0;
                    trig <= 1;
                    state <= TRIGGER;
                end
                TRIGGER: if (count == 999) begin
                    trig <= 0;
                    count <= 0;
                    state <= WAIT_ECHO;
                end else count <= count + 1'b1;
                WAIT_ECHO: if (echo_sync) begin
                    count <= 1;
                    state <= MEASURE;
                end else if (count == 2999999) begin
                    done <= 1;
                    valid <= 0;
                    state <= IDLE;
                end else count <= count + 1'b1;
                MEASURE: if (!echo_sync || count == 3000000) begin
                    done <= 1;
                    valid <= !echo_sync && cm >= 2 && cm <= 400;
                    if (!echo_sync && cm >= 2 && cm <= 400)
                        distance <= cm[8:0];
                    state <= IDLE;
                end else count <= count + 1'b1;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
