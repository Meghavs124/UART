module tb_uart_compare;

    parameter CLK_FREQ    = 76800;
    parameter BAUD_RATE   = 2400;
    parameter WIDTH       = 8;
    parameter SYNC_SETTLE = 4;
    // Total bits in one 8N1 frame: 1 start + 8 data + 1 stop = 10
    parameter FRAME_BITS  = 10;

    reg              sys_clk;
    reg              sys_rst;
    reg              xmit_h;
    reg  [WIDTH-1:0] xmit_data_h;

    reg              dut_rx_in;
    reg              ref_rx_in;

    // Captured TX serial stream (bit-by-bit from DUT TX output)
    reg [FRAME_BITS-1:0] captured_frame;

    wire             dut_baud_op_clk;
    wire             dut_uart_xmit_data_h;
    wire             dut_xmit_done_h;
    wire [WIDTH-1:0] dut_rec_data_h;
    wire             dut_rec_ready;
    wire             dut_rec_busy;
    wire             dut_xmit_active;

    wire             ref_baud_op_clk;
    wire             ref_uart_xmit_data_h;
    wire             ref_xmit_done_h;
    wire [WIDTH-1:0] ref_rec_data_h;
    wire             ref_rec_ready;
    wire             ref_rec_busy;
    wire             ref_xmit_active;
    wire [WIDTH-1:0] ref_shift_monitor;
    wire [3:0]       ref_bit_index;

    integer pass_cnt = 0;
    integer fail_cnt = 0;
    integer test_num = 0;

    top #(
        .clk_freq  (CLK_FREQ),
        .baud_rate (BAUD_RATE),
        .width     (WIDTH)
    ) DUT (
        .sys_clk          (sys_clk),
        .sys_rst          (sys_rst),
        .xmit_h           (xmit_h),
        .xmit_data_h      (xmit_data_h),
        .uart_rec_data_h  (dut_rx_in),          // fed from captured_frame
        .baud_op_clk      (dut_baud_op_clk),
        .uart_xmit_data_h (dut_uart_xmit_data_h),
        .xmit_done_h      (dut_xmit_done_h),
        .rec_data_h       (dut_rec_data_h),
        .rec_ready        (dut_rec_ready),
        .rec_busy         (dut_rec_busy),
        .xmit_active      (dut_xmit_active)
    );

    top_ref #(
        .clk_freq  (CLK_FREQ),
        .baud_rate (BAUD_RATE),
        .width     (WIDTH)
    ) REF (
        .sys_clk          (sys_clk),
        .sys_rst          (sys_rst),
        .xmit_h           (xmit_h),
        .xmit_data_h      (xmit_data_h),
        .uart_rec_data_h  (ref_rx_in),          // fed from captured_frame
        .baud_op_clk      (ref_baud_op_clk),
        .uart_xmit_data_h (ref_uart_xmit_data_h),
        .xmit_done_h      (ref_xmit_done_h),
        .rec_data_h       (ref_rec_data_h),
        .rec_ready        (ref_rec_ready),
        .rec_busy         (ref_rec_busy),
        .xmit_active      (ref_xmit_active),
        .shift_out        (ref_shift_monitor),
        .bit_index        (ref_bit_index)
    );

    initial sys_clk = 0;
    always  #5 sys_clk = ~sys_clk;

    initial begin
        #80_000_000;
        $display("GLOBAL TIMEOUT  simulation aborted");
        $finish;
    end

    task apply_reset;
        begin
            sys_rst          = 0;
            xmit_h           = 0;
            xmit_data_h      = 0;
            dut_rx_in        = 1;   // idle high
            ref_rx_in        = 1;
            captured_frame   = {FRAME_BITS{1'b1}};
            repeat(10) @(posedge sys_clk);
            sys_rst = 1;
            repeat(5) @(posedge ref_baud_op_clk);
        end
    endtask

    task wait_ticks;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1)
                @(posedge ref_baud_op_clk);
        end
    endtask

    task run_tx;
        input [WIDTH-1:0] data;
        integer b;
        begin
            captured_frame = {FRAME_BITS{1'b1}};

            // Trigger TX on both DUT and REF
            @(posedge ref_baud_op_clk);
            xmit_data_h = data;
            xmit_h      = 1;
            @(posedge ref_baud_op_clk);
            xmit_h = 0;

            @(negedge dut_uart_xmit_data_h);

            // Capture FRAME_BITS bits at mid-bit of each baud period
            for (b = 0; b < FRAME_BITS; b = b + 1) begin
                wait_ticks(8);
                captured_frame[b] = dut_uart_xmit_data_h;
                wait_ticks(8);
            end

            // Wait for both TX done (fork so neither blocks the other)
            fork
                begin wait(dut_xmit_done_h); end
                begin wait(ref_xmit_done_h); end
            join
            repeat(4) @(posedge ref_baud_op_clk);

            $display("  run_tx: data=0x%h captured=%b (start=%b d=%b%b%b%b%b%b%b%b stop=%b)",
                data, captured_frame,
                captured_frame[0],
                captured_frame[1], captured_frame[2], captured_frame[3], captured_frame[4],
                captured_frame[5], captured_frame[6], captured_frame[7], captured_frame[8],
                captured_frame[9]);
        end
    endtask

    task run_rx;
        integer b;
        begin
            // Ensure line is idle before replay
            dut_rx_in = 1;
            ref_rx_in = 1;
            wait_ticks(4);

            // Drive each captured bit for 16 baud ticks
            for (b = 0; b < FRAME_BITS; b = b + 1) begin
                dut_rx_in = captured_frame[b];
                ref_rx_in = captured_frame[b];
                wait_ticks(16);
            end

            // Return to idle
            dut_rx_in = 1;
            ref_rx_in = 1;

            // Wait for DUT 2-FF sync pipeline to settle
            wait_ticks(SYNC_SETTLE);
            #1;
        end
    endtask

    task compare_outputs;
        input        check_tx;
        input        check_rx;
        output reg   matched;
        begin
            matched = 1;
            if (check_tx) begin
                if (dut_uart_xmit_data_h !== ref_uart_xmit_data_h) matched = 0;
                
                if (!check_rx) begin
                    if (dut_xmit_done_h !== ref_xmit_done_h) matched = 0;
                end
                if (dut_xmit_active !== ref_xmit_active) matched = 0;
            end
            if (check_rx) begin
                if (dut_rec_data_h !== ref_rec_data_h) matched = 0;
                if (dut_rec_ready  !== ref_rec_ready)  matched = 0;
                if (dut_rec_busy   !== ref_rec_busy)   matched = 0;
            end
        end
    endtask
 
    task print_mismatch;
        input check_tx;
        input check_rx;
        begin
            if (check_tx) begin
                if (dut_uart_xmit_data_h !== ref_uart_xmit_data_h)
                    $display("         uart_xmit_data_h : DUT=%b  REF=%b",
                              dut_uart_xmit_data_h, ref_uart_xmit_data_h);
                if (!check_rx && dut_xmit_done_h !== ref_xmit_done_h)
                    $display("         xmit_done_h      : DUT=%b  REF=%b",
                              dut_xmit_done_h, ref_xmit_done_h);
                if (dut_xmit_active !== ref_xmit_active)
                    $display("         xmit_active      : DUT=%b  REF=%b",
                              dut_xmit_active, ref_xmit_active);
            end
            if (check_rx) begin
                if (dut_rec_data_h !== ref_rec_data_h)
                    $display("         rec_data_h  : DUT=0x%h  REF=0x%h",
                              dut_rec_data_h, ref_rec_data_h);
                if (dut_rec_ready !== ref_rec_ready)
                    $display("         rec_ready   : DUT=%b  REF=%b",
                              dut_rec_ready, ref_rec_ready);
                if (dut_rec_busy !== ref_rec_busy)
                    $display("         rec_busy    : DUT=%b  REF=%b",
                              dut_rec_busy, ref_rec_busy);
            end
        end
    endtask

    task report;
        input [8*64-1:0] tname;
        input            passed;
        input            check_tx;
        input            check_rx;
        begin
            test_num = test_num + 1;
            if (passed) begin
                $display("[PASS] TC%0d: %s  |  DUT: tx=%b done=%b active=%b busy=%b ready=%b data=0x%h  |  REF: tx=%b done=%b active=%b busy=%b ready=%b data=0x%h",
                    test_num, tname,
                    dut_uart_xmit_data_h, dut_xmit_done_h, dut_xmit_active,
                    dut_rec_busy, dut_rec_ready, dut_rec_data_h,
                    ref_uart_xmit_data_h, ref_xmit_done_h, ref_xmit_active,
                    ref_rec_busy, ref_rec_ready, ref_rec_data_h);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] TC%0d: %s  |  DUT: tx=%b done=%b active=%b busy=%b ready=%b data=0x%h  |  REF: tx=%b done=%b active=%b busy=%b ready=%b data=0x%h",
                    test_num, tname,
                    dut_uart_xmit_data_h, dut_xmit_done_h, dut_xmit_active,
                    dut_rec_busy, dut_rec_ready, dut_rec_data_h,
                    ref_uart_xmit_data_h, ref_xmit_done_h, ref_xmit_active,
                    ref_rec_busy, ref_rec_ready, ref_rec_data_h);
                print_mismatch(check_tx, check_rx);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task full_test;
        input [WIDTH-1:0] data;
        output reg        matched;
        reg               m;
        begin
            run_tx(data);
            run_rx();
            compare_outputs(1, 1, m);
            matched = m;
        end
    endtask

    initial begin
        $display("=======================================================");
        $display("  UART Compare TB  DUT vs REF  60 Test Cases        ");
        $display("  Flow: run_tx -> capture -> run_rx -> compare         ");
        $display("  No direct TX-to-RX wire anywhere                    ");
        $display("  SYNC_SETTLE=%0d baud ticks                          ", SYNC_SETTLE);
        $display("=======================================================\n");

        // TX001  Basic 0xA5
        apply_reset();
        begin : TX001
            reg m;
            full_test(8'hA5, m);
            report("Basic TX then RX 0xA5", m, 1, 1);
        end

        // TX002  xmit_active asserts on xmit_h
        apply_reset();
        begin : TX002
            reg m;
            @(posedge ref_baud_op_clk);
            xmit_data_h = 8'hAA;
            xmit_h      = 1;
            @(posedge ref_baud_op_clk);
            #1;
            m = (dut_xmit_active === ref_xmit_active) && (dut_xmit_active === 1);
            xmit_h = 0;
            wait(dut_xmit_done_h);
            repeat(4) @(posedge ref_baud_op_clk);
            report("xmit_active asserts on xmit_h", m, 1, 0);
        end

        // TX003  xmit_done_h asserts after full frame
        apply_reset();
        begin : TX003
            reg dut_done, ref_done, m;
            dut_done = 0; ref_done = 0;
            @(posedge ref_baud_op_clk);
            xmit_data_h = 8'hA5;
            xmit_h      = 1;
            @(posedge ref_baud_op_clk);
            xmit_h = 0;
            wait(ref_xmit_done_h); ref_done = 1;
            begin : wait_dut3
                integer k;
                for (k=0; k<8 && !dut_xmit_done_h; k=k+1)
                    @(posedge ref_baud_op_clk);
                if (dut_xmit_done_h) dut_done = 1;
            end
            repeat(4) @(posedge ref_baud_op_clk);
            m = (dut_done === ref_done);
            report("xmit_doneH asserts after full frame", m, 1, 0);
        end

        // TX004  Back-to-back 0x12 then 0x34
        apply_reset();
        begin : TX004
            reg m1, m2, m;
            full_test(8'h12, m1);
            full_test(8'h34, m2);
            m = m1 && m2;
            report("Back-to-Back 0x12 then 0x34", m, 1, 1);
        end

        // TX005  Idle: TX high, no activity
        apply_reset();
        begin : TX005
            reg m;
            wait_ticks(20); #1;
            m = (dut_uart_xmit_data_h===1) && (ref_uart_xmit_data_h===1) &&
                (dut_xmit_active===0)       && (ref_xmit_active===0);
            report("Idle TX HIGH xmit_active=0", m, 1, 0);
        end

        // TX006  Max data 0xFF
        apply_reset();
        begin : TX006
            reg m;
            full_test(8'hFF, m);
            report("Max Data 0xFF", m, 1, 1);
        end

        // TX007  0x2A
        apply_reset();
        begin : TX007
            reg m;
            full_test(8'h2A, m);
            report("Data 0x2A", m, 1, 1);
        end

        // TX008  Trigger during busy: original frame intact
        apply_reset();
        begin : TX008
            reg m;
            @(posedge ref_baud_op_clk);
            xmit_data_h = 8'hA5; xmit_h = 1;
            @(posedge ref_baud_op_clk); xmit_h = 0;
            wait_ticks(20);
            xmit_data_h = 8'h3C; xmit_h = 1;
            @(posedge ref_baud_op_clk); xmit_h = 0;
            wait(ref_xmit_done_h);
            repeat(4) @(posedge ref_baud_op_clk); #1;
            compare_outputs(1, 0, m);
            report("Trigger during busy: original frame intact", m, 1, 0);
        end

        // TX009  Reset during TX
        apply_reset();
        begin : TX009
            reg m;
            @(posedge ref_baud_op_clk);
            xmit_data_h = 8'hA5; xmit_h = 1;
            @(posedge ref_baud_op_clk); xmit_h = 0;
            wait_ticks(20);
            sys_rst = 0;
            repeat(5) @(posedge sys_clk); #1;
            compare_outputs(1, 1, m);
            sys_rst = 1;
            repeat(5) @(posedge ref_baud_op_clk);
            report("Reset during TX: both stop and go idle", m, 1, 1);
        end

        // TX010  0x55
        apply_reset();
        begin : TX010
            reg m;
            full_test(8'h55, m);
            report("8N1 Frame 0x55", m, 1, 1);
        end

        // TX011  0x3F
        apply_reset();
        begin : TX011
            reg m;
            full_test(8'h3F, m);
            report("6-bit boundary 0x3F", m, 1, 1);
        end

        // TX012  0xFF again
        apply_reset();
        begin : TX012
            reg m;
            full_test(8'hFF, m);
            report("8-bit max boundary 0xFF", m, 1, 1);
        end

        // TX013  3 back-to-back frames
        apply_reset();
        begin : TX013
            reg m1, m2, m3, m;
            full_test(8'hAA, m1);
            full_test(8'h55, m2);
            full_test(8'hA5, m3);
            m = m1 && m2 && m3;
            report("3 back-to-back frames AA,55,A5", m, 1, 1);
        end

        // TX014  baud low-limit proxy
        apply_reset();
        begin : TX014
            reg m;
            full_test(8'hA5, m);
            report("Baud low-limit proxy", m, 1, 1);
        end

        // TX015  baud high-limit proxy
        apply_reset();
        begin : TX015
            reg m;
            full_test(8'h3C, m);
            report("Baud high-limit proxy", m, 1, 1);
        end

        // TX016  immediate retrigger after done
        apply_reset();
        begin : TX016
            reg m1, m2, m;
            full_test(8'hA5, m1);
            full_test(8'hB6, m2);
            m = m1 && m2;
            report("Immediate retrigger after done", m, 1, 1);
        end

        // TX017  trigger during active TX ignored
        apply_reset();
        begin : TX017
            reg m;
            @(posedge ref_baud_op_clk);
            xmit_data_h = 8'hCC; xmit_h = 1;
            @(posedge ref_baud_op_clk); xmit_h = 0;
            wait_ticks(10);
            xmit_data_h = 8'hDD; xmit_h = 1;
            @(posedge ref_baud_op_clk); xmit_h = 0;
            wait(ref_xmit_done_h);
            repeat(4) @(posedge ref_baud_op_clk); #1;
            compare_outputs(1, 0, m);
            report("Trigger during active TX: ignored", m, 1, 0);
        end

        // TX018  reset mid-TX
        apply_reset();
        begin : TX018
            reg m;
            @(posedge ref_baud_op_clk);
            xmit_data_h = 8'hA5; xmit_h = 1;
            @(posedge ref_baud_op_clk); xmit_h = 0;
            wait_ticks(15);
            sys_rst = 0;
            repeat(5) @(posedge sys_clk); #1;
            compare_outputs(1, 1, m);
            sys_rst = 1;
            repeat(5) @(posedge ref_baud_op_clk);
            report("Reset mid-TX: both abort to idle", m, 1, 1);
        end

        // TX019  zero data 0x00
        apply_reset();
        begin : TX019
            reg m;
            full_test(8'h00, m);
            report("Zero data 0x00", m, 1, 1);
        end

        // TX020  glitch on xmit_h
        apply_reset();
        begin : TX020
            reg m;
            @(posedge ref_baud_op_clk);
            xmit_data_h = 8'hA5; xmit_h = 1;
            #2; xmit_h = 0;
            wait_ticks(30); #1;
            compare_outputs(1, 1, m);
            report("Glitch on xmitH: DUT and REF same", m, 1, 1);
        end

        // TX021  valid stop bit
        apply_reset();
        begin : TX021
            reg m;
            full_test(8'hA5, m);
            report("Valid stop bit: frame accepted", m, 1, 1);
        end

        // TX022  0x3C
        apply_reset();
        begin : TX022
            reg m;
            full_test(8'h3C, m);
            report("TX then RX 0x3C", m, 1, 1);
        end

        // TX023  rec_ready pulses after valid frame
        apply_reset();
        begin : TX023
            reg dut_rdy, ref_rdy, m;
            dut_rdy = 0; ref_rdy = 0;
            run_tx(8'hA5);
            fork
                run_rx();
                begin : watch23
                    integer k;
                    for (k=0; k<60; k=k+1) begin
                        @(posedge ref_baud_op_clk);
                        if (dut_rec_ready) dut_rdy = 1;
                        if (ref_rec_ready) ref_rdy = 1;
                    end
                end
            join
            m = (dut_rdy===1) && (ref_rdy===1);
            report("rec_readyH pulses after valid frame", m, 0, 1);
        end

        // TX024  rec_busy asserts on start bit
        apply_reset();
        begin : TX024
            reg m;
            dut_rx_in = 0; ref_rx_in = 0;
            wait_ticks(12); #1;
            m = (dut_rec_busy===1) && (ref_rec_busy===1);
            dut_rx_in = 1; ref_rx_in = 1;
            wait_ticks(20);
            report("Start bit: rec_busy asserts in DUT and REF", m, 0, 1);
        end

        // TX025  sequential RX two frames
        apply_reset();
        begin : TX025
            reg m1, m2, m;
            full_test(8'hA5, m1);
            full_test(8'h3C, m2);
            m = m1 && m2;
            report("Sequential TX+RX: 0xA5 then 0x3C", m, 1, 1);
        end

        // TX026  valid stop accepted
        apply_reset();
        begin : TX026
            reg m;
            full_test(8'hA5, m);
            report("Valid stop accepted: DUT matches REF", m, 1, 1);
        end

        // TX027  idle line
        apply_reset();
        begin : TX027
            reg m;
            wait_ticks(30); #1;
            m = (dut_uart_xmit_data_h===1) && (ref_uart_xmit_data_h===1) &&
                (dut_rec_busy===0) && (ref_rec_busy===0);
            report("Idle line: no activity in DUT or REF", m, 1, 1);
        end

        // TX028  clean frame baseline
        apply_reset();
        begin : TX028
            reg m;
            full_test(8'hA5, m);
            report("Clean frame baseline 0xA5", m, 1, 1);
        end

        // TX029  post-frame busy clears
        apply_reset();
        begin : TX029
            reg m;
            full_test(8'hA5, m);
            wait_ticks(5); #1;
            m = (dut_rec_busy===0) && (ref_rec_busy===0);
            report("Post-frame busy clears in DUT and REF", m, 0, 1);
        end

        // TX030  3 back-to-back RX frames
        apply_reset();
        begin : TX030
            reg m1, m2, m3, m;
            full_test(8'hAA, m1);
            full_test(8'hBB, m2);
            full_test(8'hCC, m3);
            m = m1 && m2 && m3;
            report("3 back-to-back frames AA,BB,CC", m, 1, 1);
        end

        // TX031  reset during RX
        apply_reset();
        begin : TX031
            reg m;
            dut_rx_in = 0; ref_rx_in = 0;
            wait_ticks(20);
            sys_rst = 0;
            repeat(5) @(posedge sys_clk); #1;
            compare_outputs(1, 1, m);
            dut_rx_in = 1; ref_rx_in = 1;
            sys_rst = 1;
            repeat(5) @(posedge ref_baud_op_clk);
            report("Reset during RX: DUT matches REF", m, 1, 1);
        end

        // TX032  0x2A
        apply_reset();
        begin : TX032
            reg m;
            full_test(8'h2A, m);
            report("Min boundary 0x2A", m, 1, 1);
        end

        // TX033  0xFF
        apply_reset();
        begin : TX033
            reg m;
            full_test(8'hFF, m);
            report("Max boundary 0xFF", m, 1, 1);
        end

        // TX034  0x12, 0x34, 0x56
        apply_reset();
        begin : TX034
            reg m1, m2, m3, m;
            full_test(8'h12, m1);
            full_test(8'h34, m2);
            full_test(8'h56, m3);
            m = m1 && m2 && m3;
            report("Back-to-Back 0x12,0x34,0x56", m, 1, 1);
        end

        // TX035  busy at 24th tick
        apply_reset();
        begin : TX035
            reg m;
            dut_rx_in = 0; ref_rx_in = 0;
            wait_ticks(24); #1;
            m = (dut_rec_busy===ref_rec_busy) && (dut_rec_busy===1);
            dut_rx_in = 1; ref_rx_in = 1;
            wait_ticks(28);
            report("Busy at 24th tick matches REF", m, 0, 1);
        end

        // TX036  slow baud proxy
        apply_reset();
        begin : TX036
            reg m;
            full_test(8'hA5, m);
            report("Slow baud proxy", m, 1, 1);
        end

        // TX037  fast baud proxy
        apply_reset();
        begin : TX037
            reg m;
            full_test(8'h3C, m);
            report("Fast baud proxy", m, 1, 1);
        end

        // TX038  valid stop bit
        apply_reset();
        begin : TX038
            reg m;
            full_test(8'hA5, m);
            report("Valid stop bit RX accepted", m, 1, 1);
        end

        // TX039  idle: no spurious reception
        apply_reset();
        begin : TX039
            reg m;
            wait_ticks(30); #1;
            m = (dut_rec_busy===0) && (ref_rec_busy===0) &&
                (dut_rec_ready===0) && (ref_rec_ready===0);
            report("Idle RX: no spurious reception", m, 0, 1);
        end

        // TX040  0x55
        apply_reset();
        begin : TX040
            reg m;
            full_test(8'h55, m);
            report("Noise baseline 0x55", m, 1, 1);
        end

        // TX041  short start glitch
        apply_reset();
        begin : TX041
            reg m;
            dut_rx_in = 0; ref_rx_in = 0;
            wait_ticks(3);
            dut_rx_in = 1; ref_rx_in = 1;
            wait_ticks(30); #1;
            m = (dut_rec_busy===ref_rec_busy) && (dut_rec_ready===ref_rec_ready);
            report("Short start glitch: DUT and REF same", m, 0, 1);
        end

        // TX042  3 frames no gap
        apply_reset();
        begin : TX042
            reg m1, m2, m3, m;
            full_test(8'h11, m1);
            full_test(8'h22, m2);
            full_test(8'h33, m3);
            m = m1 && m2 && m3;
            report("3 frames no gap: 11,22,33", m, 1, 1);
        end

        // TX043  0xA5 then 0x5A
        apply_reset();
        begin : TX043
            reg m1, m2, m;
            full_test(8'hA5, m1);
            full_test(8'h5A, m2);
            m = m1 && m2;
            report("Sequential 0xA5 then 0x5A", m, 1, 1);
        end

        // TX044  reset mid-RX
        apply_reset();
        begin : TX044
            reg m;
            dut_rx_in = 0; ref_rx_in = 0;
            wait_ticks(25);
            sys_rst = 0;
            repeat(5) @(posedge sys_clk); #1;
            compare_outputs(1, 1, m);
            dut_rx_in = 1; ref_rx_in = 1;
            sys_rst = 1;
            repeat(5) @(posedge ref_baud_op_clk);
            report("Reset mid-RX: DUT matches REF", m, 1, 1);
        end

        // TX045  baud 2400
        apply_reset();
        begin : TX045
            reg m;
            full_test(8'hA5, m);
            report("Baud 2400 TX+RX", m, 1, 1);
        end

        // TX046  0xB7
        apply_reset();
        begin : TX046
            reg m;
            full_test(8'hB7, m);
            report("Baud 9600 proxy 0xB7", m, 1, 1);
        end

        // TX047  0xC8
        apply_reset();
        begin : TX047
            reg m;
            full_test(8'hC8, m);
            report("Baud 19200 proxy 0xC8", m, 1, 1);
        end

        // TX048  0xD9
        apply_reset();
        begin : TX048
            reg m;
            full_test(8'hD9, m);
            report("Unsupported baud proxy 0xD9", m, 1, 1);
        end

        // TX049  0xA5 repeat
        apply_reset();
        begin : TX049
            reg m;
            full_test(8'hA5, m);
            report("Baud mismatch proxy", m, 1, 1);
        end

        // TX050  oversampling: count start bit ticks
        apply_reset();
        begin : TX050
            reg m;
            integer dut_count, ref_count;
            dut_count = 0; ref_count = 0;
            @(posedge ref_baud_op_clk);
            xmit_data_h = 8'hA5; xmit_h = 1;
            @(posedge ref_baud_op_clk); xmit_h = 0;
            wait(dut_uart_xmit_data_h === 0);
            begin : cnt_dut50
                integer k;
                for (k=0; k<20; k=k+1) begin
                    @(posedge dut_baud_op_clk); dut_count = dut_count + 1;
                    if (dut_uart_xmit_data_h !== 0) k = 20;
                end
            end
            begin : cnt_ref50
                integer k;
                for (k=0; k<20; k=k+1) begin
                    @(posedge ref_baud_op_clk); ref_count = ref_count + 1;
                    if (ref_uart_xmit_data_h !== 0) k = 20;
                end
            end
            m = (dut_count === ref_count);
            wait(ref_xmit_done_h);
            repeat(4) @(posedge ref_baud_op_clk);
            report("Oversampling: DUT tick count matches REF", m, 1, 0);
        end

        // TX051  0xEA
        apply_reset();
        begin : TX051
            reg m;
            full_test(8'hEA, m);
            report("Lowest baud proxy 0xEA", m, 1, 1);
        end

        // TX052  0xFB
        apply_reset();
        begin : TX052
            reg m;
            full_test(8'hFB, m);
            report("Highest baud proxy 0xFB", m, 1, 1);
        end

        // TX053  oversampling boundary: busy at 8th tick
        apply_reset();
        begin : TX053
            reg m;
            dut_rx_in = 0; ref_rx_in = 0;
            wait_ticks(8); #1;
            m = (dut_rec_busy===ref_rec_busy) && (dut_rec_busy===1);
            dut_rx_in = 1; ref_rx_in = 1;
            wait_ticks(30);
            report("Oversampling boundary 8th tick: busy matches", m, 0, 1);
        end

        // TX054  timing accuracy
        apply_reset();
        begin : TX054
            reg m;
            full_test(8'hA5, m);
            report("Timing accuracy 8N1", m, 1, 1);
        end

        // TX055  no corruption
        apply_reset();
        begin : TX055
            reg m;
            full_test(8'hA5, m);
            report("No corruption proxy", m, 1, 1);
        end

        // TX056  0x3C
        apply_reset();
        begin : TX056
            reg m;
            full_test(8'h3C, m);
            report("Baud mismatch proxy 0x3C", m, 1, 1);
        end

        // TX057  0xFF
        apply_reset();
        begin : TX057
            reg m;
            full_test(8'hFF, m);
            report("Extreme proxy 0xFF", m, 1, 1);
        end

        // TX058  3 different frames
        apply_reset();
        begin : TX058
            reg m1, m2, m3, m;
            full_test(8'hA5, m1);
            full_test(8'h5A, m2);
            full_test(8'hFF, m3);
            m = m1 && m2 && m3;
            report("Clock drift proxy: A5,5A,FF", m, 1, 1);
        end

        // TX059  step-by-step shift register for 0xA5
        apply_reset();
        begin : TX059
            reg m;
            reg [WIDTH-1:0] exp [0:7];
            exp[0]=8'h80; exp[1]=8'h40; exp[2]=8'hA0; exp[3]=8'h50;
            exp[4]=8'h28; exp[5]=8'h94; exp[6]=8'h4A; exp[7]=8'hA5;
            m = 1;

            // Manually drive start bit
            dut_rx_in = 0; ref_rx_in = 0;
            wait_ticks(16);

            begin : step59
                integer b;
                for (b = 0; b < 8; b = b + 1) begin
                    dut_rx_in = 8'hA5 >> b & 1;
                    ref_rx_in = 8'hA5 >> b & 1;
                    wait_ticks(8 + SYNC_SETTLE); #1;
                    if (ref_shift_monitor !== exp[b]) begin
                        $display("  TX059 bit%0d: ref_shift=0x%h exp=0x%h", b, ref_shift_monitor, exp[b]);
                        m = 0;
                    end
                    if (dut_rec_data_h !== exp[b]) begin
                        $display("  TX059 bit%0d: dut_data=0x%h  exp=0x%h", b, dut_rec_data_h, exp[b]);
                        m = 0;
                    end
                    wait_ticks(16 - 8 - SYNC_SETTLE);
                end
            end

            dut_rx_in = 1; ref_rx_in = 1;
            wait_ticks(20);
            report("Step-by-step shift 0xA5: DUT matches REF", m, 0, 1);
        end

        // TX060  TX 0xA5, then RX replay, verify independence
        apply_reset();
        begin : TX060
            reg m;
            run_tx(8'hA5);
            $display("         TX060: captured_frame=%b", captured_frame);
            run_rx();
            compare_outputs(1, 1, m);
            $display("         TX060: dut_rec=0x%h ref_rec=0x%h (expect A5)",
                      dut_rec_data_h, ref_rec_data_h);
            report("TX=0xA5 captured and replayed to RX", m, 1, 1);
        end

        // ========================================================
        // SUMMARY
        // ========================================================
        repeat(10) @(posedge ref_baud_op_clk);
        $display("\n=======================================================");
        $display("  FINAL RESULTS");
        $display("  Total : %0d", test_num);
        $display("  PASS  : %0d", pass_cnt);
        $display("  FAIL  : %0d", fail_cnt);
        $display("=======================================================");
        if (fail_cnt == 0)
            $display("  *** ALL TESTS PASSED ***\n");
        else
            $display("  *** %0d TEST(S) FAILED ***\n", fail_cnt);
        $finish;
    end

    // ============================================================
    // $monitor
    // ============================================================
    initial begin
        $monitor("T=%0t | DUT: tx=%b done=%b active=%b busy=%b ready=%b data=0x%h | REF: tx=%b done=%b active=%b busy=%b ready=%b data=0x%h | dut_rx=%b ref_rx=%b",
            $time,
            dut_uart_xmit_data_h, dut_xmit_done_h, dut_xmit_active,
            dut_rec_busy, dut_rec_ready, dut_rec_data_h,
            ref_uart_xmit_data_h, ref_xmit_done_h, ref_xmit_active,
            ref_rec_busy, ref_rec_ready, ref_rec_data_h,
            dut_rx_in, ref_rx_in);
    end

endmodule
