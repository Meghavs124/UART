module uart_tx_ref #(parameter width = 8)(
    input                  baud_op_clk,
    input                  sys_rst,
    input                  xmit_h,
    input  [width-1:0]     xmit_data_h,
    output reg             xmit_done_h,
    output reg             xmit_active,
    output reg             uart_xmit_data_h
);
    integer i;
    reg [width-1:0] latched_data;
    reg             busy;

    initial begin
        uart_xmit_data_h = 1;
        xmit_done_h      = 1;   // idle: done=1, active=0 (complements)
        xmit_active      = 0;
        busy             = 0;
        latched_data     = 0;
    end

    // Block 1: latch data and set busy when xmit_h seen and not busy
    always @(posedge baud_op_clk or negedge sys_rst) begin
        if (!sys_rst) begin
            latched_data <= 0;
            busy         <= 0;
            xmit_done_h  <= 1;   // reset: idle => done=1, active=0
            xmit_active  <= 0;
        end
        else if (xmit_h && !busy) begin
            latched_data <= xmit_data_h;
            busy         <= 1;
            xmit_done_h  <= 0;   // transmission starting: done=0, active=1
            xmit_active  <= 1;
        end
    end

    // Block 2: drive serial line when busy goes high
    always @(posedge busy or negedge sys_rst) begin : tx_send
        if (!sys_rst) begin
            uart_xmit_data_h <= 1;
            xmit_done_h      <= 1;   // reset: done=1, active=0
            xmit_active      <= 0;
            busy             <= 0;
        end
        else begin
            // active=1, done=0 throughout transmission
            xmit_active      <= 1;
            xmit_done_h      <= 0;

            // START bit
            @(posedge baud_op_clk);
            uart_xmit_data_h <= 0;
            repeat(15) @(posedge baud_op_clk);

            // DATA bits LSB first
            for (i = 0; i < width; i = i + 1) begin
                @(posedge baud_op_clk);
                uart_xmit_data_h <= latched_data[i];
                repeat(15) @(posedge baud_op_clk);
            end

            // STOP bit
            @(posedge baud_op_clk);
            uart_xmit_data_h <= 1;
            repeat(15) @(posedge baud_op_clk);

            // Frame done: active=0, done=1 (complements)
            // Stays this way until next xmit_h clears done in Block 1
            @(posedge baud_op_clk);
            xmit_active <= 0;
            xmit_done_h <= 1;
            busy        <= 0;
        end
    end
endmodule
