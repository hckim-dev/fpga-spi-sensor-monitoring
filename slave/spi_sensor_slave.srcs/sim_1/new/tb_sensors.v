`timescale 1ns/1ps
module tb_sensors;
    reg clk = 0;
    reg reset = 1;
    always #5 clk = ~clk;

    reg dht_drive_low = 0;
    tri1 dht_data;
    assign dht_data = dht_drive_low ? 1'b0 : 1'bz;
    wire dht_done, dht_valid;
    wire signed [15:0] temperature;
    wire [15:0] humidity;

    reg echo = 0;
    reg start_trig = 0;
    wire trig, ultrasonic_done, ultrasonic_valid;
    wire [8:0] distance;
    reg dht_passed = 0;
    reg ultrasonic_passed = 0;
    reg [39:0] raw_frame = 40'h0C001B032A;
    integer bit_number;

    dht11_sensor dht (
        .clk(clk), .reset(reset), .dht11_data(dht_data),
        .done(dht_done), .valid(dht_valid),
        .temperature(temperature), .humidity(humidity)
    );
    ultrasonic_sensor ultrasonic (
        .clk(clk), .reset(reset), .echo(echo), .start_trig(start_trig),
        .trig(trig), .distance(distance),
        .done(ultrasonic_done), .valid(ultrasonic_valid)
    );

    initial begin
        #100;
        @(negedge clk); reset = 0;
    end

    // Skip only the initial 2-second idle interval.
    // START, ACK and all 40 data-bit pulse widths use actual timing.
    initial begin
        wait(!reset);
        @(negedge clk); dht.timer = 28'd199999999;
        wait(dht_data === 1'b0);
        wait(dht_data === 1'b1);
        #30000 dht_drive_low = 1;
        #80000 dht_drive_low = 0;
        #80000 dht_drive_low = 1;
        for (bit_number = 39; bit_number >= 0; bit_number = bit_number - 1) begin
            #50000 dht_drive_low = 0;
            if (raw_frame[bit_number]) #70000;
            else #27000;
            dht_drive_low = 1;
        end
        wait(dht_done); #1;
        if (!dht_valid || temperature !== 16'sd273 || humidity !== 16'd120)
            $fatal(1, "DHT11 FAIL T=%d H=%d valid=%b", temperature, humidity, dht_valid);
        $display("DHT11 PASS: temperature=27.3 C humidity=12.0 percent");
        dht_passed = 1;
        #50000 dht_drive_low = 0;
    end

    initial begin
        wait(!reset);
        @(negedge clk); start_trig = 1;
        @(negedge clk); start_trig = 0;
        wait(trig);
        wait(!trig);
        #100000 echo = 1;
        #1624000 echo = 0; // 28 cm * 58 us/cm
        wait(ultrasonic_done); #1;
        if (!ultrasonic_valid || distance !== 9'd28)
            $fatal(1, "Ultrasonic FAIL distance=%d valid=%b", distance, ultrasonic_valid);
        $display("ULTRASONIC PASS: distance=28 cm");
        ultrasonic_passed = 1;
    end

    initial begin
        wait(dht_passed && ultrasonic_passed);
        #100;
        $display("PASS: both sensor measurements completed");
        $finish;
    end
    initial #30000000 $fatal(1, "Measurement timeout");
endmodule
