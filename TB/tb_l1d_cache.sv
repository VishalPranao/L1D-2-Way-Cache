`timescale 1ns/1ps

module tb_l1d_cache;
    import cache_pkg::*;

    logic clk;
    logic reset_n;

    logic                  cpu_req_valid;
    logic                  cpu_req_ready;
    logic [ADDR_WIDTH-1:0] cpu_req_addr;
    logic                  cpu_req_write;
    logic [DATA_WIDTH-1:0] cpu_req_wdata;
    logic [WORD_BYTES-1:0] cpu_req_wstrb;

    logic                  cpu_rsp_valid;
    logic                  cpu_rsp_ready;
    logic [DATA_WIDTH-1:0] cpu_rsp_rdata;

    logic                      axi_awvalid;
    logic                      axi_awready;
    logic [ADDR_WIDTH-1:0]     axi_awaddr;
    logic [7:0]                axi_awlen;
    logic [2:0]                axi_awsize;
    logic [1:0]                axi_awburst;

    logic                      axi_wvalid;
    logic                      axi_wready;
    logic [AXI_DATA_WIDTH-1:0] axi_wdata;
    logic [AXI_BYTES-1:0]      axi_wstrb;
    logic                      axi_wlast;

    logic                      axi_bvalid;
    logic                      axi_bready;
    logic [1:0]                axi_bresp;

    logic                      axi_arvalid;
    logic                      axi_arready;
    logic [ADDR_WIDTH-1:0]     axi_araddr;
    logic [7:0]                axi_arlen;
    logic [2:0]                axi_arsize;
    logic [1:0]                axi_arburst;

    logic                      axi_rvalid;
    logic                      axi_rready;
    logic [AXI_DATA_WIDTH-1:0] axi_rdata;
    logic                      axi_rlast;
    logic [1:0]                axi_rresp;

    integer axi_read_burst_count;
    integer axi_read_beat_count;
    integer axi_write_burst_count;
    integer axi_write_beat_count;
    integer axi_write_response_count;
    integer read_beat_monitor;
    integer write_beat_monitor;
    integer cpu_request_count;
    integer cpu_response_count;

    logic [ADDR_WIDTH-1:0] last_refill_addr;
    logic [ADDR_WIDTH-1:0] last_writeback_addr;

    integer reads_before;
    integer read_beats_before;
    integer writes_before;
    integer write_beats_before;
    integer write_responses_before;

    logic [DATA_WIDTH-1:0] d_expected_word;

    l1d_cache dut (
        .clk           (clk),
        .reset_n       (reset_n),

        .cpu_req_valid (cpu_req_valid),
        .cpu_req_ready (cpu_req_ready),
        .cpu_req_addr  (cpu_req_addr),
        .cpu_req_write (cpu_req_write),
        .cpu_req_wdata (cpu_req_wdata),
        .cpu_req_wstrb (cpu_req_wstrb),

        .cpu_rsp_valid (cpu_rsp_valid),
        .cpu_rsp_ready (cpu_rsp_ready),
        .cpu_rsp_rdata (cpu_rsp_rdata),

        .m_axi_awvalid (axi_awvalid),
        .m_axi_awready (axi_awready),
        .m_axi_awaddr  (axi_awaddr),
        .m_axi_awlen   (axi_awlen),
        .m_axi_awsize  (axi_awsize),
        .m_axi_awburst (axi_awburst),

        .m_axi_wvalid  (axi_wvalid),
        .m_axi_wready  (axi_wready),
        .m_axi_wdata   (axi_wdata),
        .m_axi_wstrb   (axi_wstrb),
        .m_axi_wlast   (axi_wlast),

        .m_axi_bvalid  (axi_bvalid),
        .m_axi_bready  (axi_bready),
        .m_axi_bresp   (axi_bresp),

        .m_axi_arvalid (axi_arvalid),
        .m_axi_arready (axi_arready),
        .m_axi_araddr  (axi_araddr),
        .m_axi_arlen   (axi_arlen),
        .m_axi_arsize  (axi_arsize),
        .m_axi_arburst (axi_arburst),

        .m_axi_rvalid  (axi_rvalid),
        .m_axi_rready  (axi_rready),
        .m_axi_rdata   (axi_rdata),
        .m_axi_rlast   (axi_rlast),
        .m_axi_rresp   (axi_rresp)
    );

    axi_memory_model #(
        .MEM_BYTES    (64 * 1024),
        .READ_LATENCY (3)
    ) memory_model (
        .clk           (clk),
        .reset_n       (reset_n),

        .s_axi_awvalid (axi_awvalid),
        .s_axi_awready (axi_awready),
        .s_axi_awaddr  (axi_awaddr),
        .s_axi_awlen   (axi_awlen),
        .s_axi_awsize  (axi_awsize),
        .s_axi_awburst (axi_awburst),

        .s_axi_wvalid  (axi_wvalid),
        .s_axi_wready  (axi_wready),
        .s_axi_wdata   (axi_wdata),
        .s_axi_wstrb   (axi_wstrb),
        .s_axi_wlast   (axi_wlast),

        .s_axi_bvalid  (axi_bvalid),
        .s_axi_bready  (axi_bready),
        .s_axi_bresp   (axi_bresp),

        .s_axi_arvalid (axi_arvalid),
        .s_axi_arready (axi_arready),
        .s_axi_araddr  (axi_araddr),
        .s_axi_arlen   (axi_arlen),
        .s_axi_arsize  (axi_arsize),
        .s_axi_arburst (axi_arburst),

        .s_axi_rvalid  (axi_rvalid),
        .s_axi_rready  (axi_rready),
        .s_axi_rdata   (axi_rdata),
        .s_axi_rlast   (axi_rlast),
        .s_axi_rresp   (axi_rresp)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function automatic logic [7:0] expected_byte(
        input logic [ADDR_WIDTH-1:0] address
    );
        expected_byte = (address ^ (address >> 8)) & 8'hFF;
    endfunction

    function automatic logic [DATA_WIDTH-1:0] expected_word(
        input logic [ADDR_WIDTH-1:0] address
    );
        expected_word = {
            expected_byte(address + 3),
            expected_byte(address + 2),
            expected_byte(address + 1),
            expected_byte(address)
        };
    endfunction

    function automatic logic [DATA_WIDTH-1:0] merge_word(
        input logic [DATA_WIDTH-1:0] old_word,
        input logic [DATA_WIDTH-1:0] new_word,
        input logic [WORD_BYTES-1:0] write_strobe
    );
        integer byte_number;
        begin
            merge_word = old_word;

            for (byte_number = 0;
                 byte_number < WORD_BYTES;
                 byte_number = byte_number + 1) begin
                if (write_strobe[byte_number]) begin
                    merge_word[(byte_number * 8) +: 8]
                        = new_word[(byte_number * 8) +: 8];
                end
            end
        end
    endfunction

    task automatic load_and_check(
        input logic [ADDR_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] expected_data
    );
        begin
            @(negedge clk);
            while (cpu_req_ready !== 1'b1)
                @(negedge clk);

            cpu_req_addr  = address;
            cpu_req_write = 1'b0;
            cpu_req_wdata = '0;
            cpu_req_wstrb = '0;
            cpu_req_valid = 1'b1;

            @(posedge clk);
            @(negedge clk);
            cpu_req_valid = 1'b0;

            wait (cpu_rsp_valid === 1'b1);
            #1;

            if (cpu_rsp_rdata !== expected_data) begin
                $error("LOAD FAILED: addr=%08h expected=%08h actual=%08h",
                       address, expected_data, cpu_rsp_rdata);
                $fatal(1);
            end

            $display("PASS LOAD : addr=%08h data=%08h",
                     address, cpu_rsp_rdata);

            @(posedge clk);
            @(negedge clk);
        end
    endtask

    task automatic store_and_check(
        input logic [ADDR_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] write_data,
        input logic [WORD_BYTES-1:0] write_strobe
    );
        begin
            @(negedge clk);
            while (cpu_req_ready !== 1'b1)
                @(negedge clk);

            cpu_req_addr  = address;
            cpu_req_write = 1'b1;
            cpu_req_wdata = write_data;
            cpu_req_wstrb = write_strobe;
            cpu_req_valid = 1'b1;

            @(posedge clk);
            @(negedge clk);
            cpu_req_valid = 1'b0;

            wait (cpu_rsp_valid === 1'b1);
            #1;

            if (cpu_rsp_rdata !== '0) begin
                $error("STORE RESPONSE FAILED: addr=%08h response=%08h",
                       address, cpu_rsp_rdata);
                $fatal(1);
            end

            $display("PASS STORE: addr=%08h data=%08h strobe=%04b",
                     address, write_data, write_strobe);

            @(posedge clk);
            @(negedge clk);
        end
    endtask

    task automatic save_axi_counts;
        begin
            reads_before           = axi_read_burst_count;
            read_beats_before      = axi_read_beat_count;
            writes_before          = axi_write_burst_count;
            write_beats_before     = axi_write_beat_count;
            write_responses_before = axi_write_response_count;
        end
    endtask

    task automatic expect_axi_delta(
        input integer expected_reads,
        input integer expected_read_beats,
        input integer expected_writes,
        input integer expected_write_beats,
        input integer expected_write_responses,
        input string  test_name
    );
        begin
            if ((axi_read_burst_count - reads_before) != expected_reads
                || (axi_read_beat_count - read_beats_before)
                   != expected_read_beats
                || (axi_write_burst_count - writes_before) != expected_writes
                || (axi_write_beat_count - write_beats_before)
                   != expected_write_beats
                || (axi_write_response_count - write_responses_before)
                   != expected_write_responses) begin
                $error("%s: AXI count mismatch", test_name);
                $display("  reads expected=%0d actual=%0d",
                         expected_reads,
                         axi_read_burst_count - reads_before);
                $display("  read beats expected=%0d actual=%0d",
                         expected_read_beats,
                         axi_read_beat_count - read_beats_before);
                $display("  writes expected=%0d actual=%0d",
                         expected_writes,
                         axi_write_burst_count - writes_before);
                $display("  write beats expected=%0d actual=%0d",
                         expected_write_beats,
                         axi_write_beat_count - write_beats_before);
                $display("  B responses expected=%0d actual=%0d",
                         expected_write_responses,
                         axi_write_response_count - write_responses_before);
                $fatal(1);
            end

            $display("PASS AXI  : %s", test_name);
        end
    endtask

    // AXI and CPU protocol monitor.
    always @(posedge clk) begin
        if (!reset_n) begin
            axi_read_burst_count      <= 0;
            axi_read_beat_count       <= 0;
            axi_write_burst_count     <= 0;
            axi_write_beat_count      <= 0;
            axi_write_response_count  <= 0;
            read_beat_monitor          <= 0;
            write_beat_monitor         <= 0;
            cpu_request_count          <= 0;
            cpu_response_count         <= 0;
            last_refill_addr            <= '0;
            last_writeback_addr         <= '0;
        end
        else begin
            if (cpu_req_valid && cpu_req_ready)
                cpu_request_count <= cpu_request_count + 1;

            if (cpu_rsp_valid && cpu_rsp_ready)
                cpu_response_count <= cpu_response_count + 1;

            if (axi_arvalid && axi_arready) begin
                axi_read_burst_count <= axi_read_burst_count + 1;
                read_beat_monitor    <= 0;
                last_refill_addr     <= axi_araddr;

                if (axi_araddr[OFFSET_BITS-1:0] != '0
                    || axi_arlen != AXI_LINE_LEN
                    || axi_arsize != AXI_WORD_SIZE
                    || axi_arburst != AXI_BURST_INCR) begin
                    $fatal(1, "Invalid AXI refill request");
                end
            end

            if (axi_rvalid && axi_rready) begin
                axi_read_beat_count <= axi_read_beat_count + 1;

                if (axi_rlast
                    != (read_beat_monitor == AXI_BEATS_PER_LINE - 1)) begin
                    $fatal(1, "Incorrect RLAST on beat %0d",
                           read_beat_monitor);
                end

                if (axi_rlast)
                    read_beat_monitor <= 0;
                else
                    read_beat_monitor <= read_beat_monitor + 1;
            end

            if (axi_awvalid && axi_awready) begin
                axi_write_burst_count <= axi_write_burst_count + 1;
                write_beat_monitor    <= 0;
                last_writeback_addr  <= axi_awaddr;

                if (axi_awaddr[OFFSET_BITS-1:0] != '0
                    || axi_awlen != AXI_LINE_LEN
                    || axi_awsize != AXI_WORD_SIZE
                    || axi_awburst != AXI_BURST_INCR) begin
                    $fatal(1, "Invalid AXI writeback request");
                end
            end

            if (axi_wvalid && axi_wready) begin
                axi_write_beat_count <= axi_write_beat_count + 1;

                if (axi_wstrb != {AXI_BYTES{1'b1}}) begin
                    $fatal(1, "Writeback beat did not enable all bytes");
                end

                if (axi_wlast
                    != (write_beat_monitor == AXI_BEATS_PER_LINE - 1)) begin
                    $fatal(1, "Incorrect WLAST on beat %0d",
                           write_beat_monitor);
                end

                if (axi_wlast)
                    write_beat_monitor <= 0;
                else
                    write_beat_monitor <= write_beat_monitor + 1;
            end

            if (axi_bvalid && axi_bready)
                axi_write_response_count
                    <= axi_write_response_count + 1;
        end
    end

    initial begin
        reset_n       = 1'b0;
        cpu_req_valid = 1'b0;
        cpu_req_addr  = '0;
        cpu_req_write = 1'b0;
        cpu_req_wdata = '0;
        cpu_req_wstrb = '0;
        cpu_rsp_ready = 1'b1;

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;

        // A: cold miss into Set 0, Way 0. One eight-beat AXI read burst.
        save_axi_counts();
        load_and_check(32'h0000_1004, expected_word(32'h0000_1004));
        expect_axi_delta(1, 8, 0, 0, 0,
                         "cold load A uses one AXI refill burst");

        // Make A dirty. Store and following load must remain cache hits.
        save_axi_counts();
        store_and_check(32'h0000_1004, 32'hDEAD_BEEF, 4'b1111);
        load_and_check(32'h0000_1004, 32'hDEAD_BEEF);
        expect_axi_delta(0, 0, 0, 0, 0,
                         "store hit and read-after-write stay in cache");

        if (dut.dirty_array[0][0] !== 1'b1)
            $fatal(1, "A should be dirty in Set 0 Way 0");

        // B maps to Set 0 and fills the still-invalid Way 1.
        save_axi_counts();
        load_and_check(32'h0000_1804, expected_word(32'h0000_1804));
        expect_axi_delta(1, 8, 0, 0, 0,
                         "B fills invalid Way 1 without writeback");

        // C is a third Set-0 line. A is the LRU victim and is dirty, so C
        // forces an eight-beat writeback followed by an eight-beat refill.
        save_axi_counts();
        load_and_check(32'h0000_2004, expected_word(32'h0000_2004));
        expect_axi_delta(1, 8, 1, 8, 1,
                         "dirty A writeback occurs before C refill");

        if (last_writeback_addr !== 32'h0000_1000
            || last_refill_addr !== 32'h0000_2000) begin
            $fatal(1,
                "Wrong dirty-miss addresses: writeback=%08h refill=%08h",
                last_writeback_addr, last_refill_addr);
        end

        // Reloading A misses, but lower memory must now contain DEADBEEF from
        // the preceding writeback. B is clean, so no second writeback occurs.
        save_axi_counts();
        load_and_check(32'h0000_1004, 32'hDEAD_BEEF);
        expect_axi_delta(1, 8, 0, 0, 0,
                         "A refill observes data written back to memory");

        // Regression of Phase-3 byte masking on the refilled A line.
        save_axi_counts();
        store_and_check(32'h0000_1005, 32'h0000_AA00, 4'b0010);
        load_and_check(32'h0000_1004, 32'hDEAD_AAEF);
        expect_axi_delta(0, 0, 0, 0, 0,
                         "byte store hit updates only selected lane");

        // C remains in the other way after A is reloaded.
        save_axi_counts();
        load_and_check(32'h0000_2004, expected_word(32'h0000_2004));
        expect_axi_delta(0, 0, 0, 0, 0,
                         "C remains present in the other way");

        // Store miss in Set 1: AXI refill, replay masked store, mark dirty.
        d_expected_word = merge_word(
            expected_word(32'h0000_1024),
            32'h1234_0000,
            4'b1100
        );

        save_axi_counts();
        store_and_check(32'h0000_1026, 32'h1234_0000, 4'b1100);
        load_and_check(32'h0000_1024, d_expected_word);
        expect_axi_delta(1, 8, 0, 0, 0,
                         "store miss uses AXI write allocation and replay");

        if (dut.dirty_array[1][0] !== 1'b1)
            $fatal(1, "Store-miss line in Set 1 should be dirty");

        if (cpu_request_count != cpu_response_count) begin
            $fatal(1,
                "CPU request/response mismatch: requests=%0d responses=%0d",
                cpu_request_count, cpu_response_count);
        end

        $display("--------------------------------------------------");
        $display("ALL PHASE 4 PIPELINE, WRITEBACK AND AXI TESTS PASSED");
        $display("--------------------------------------------------");

        #20;
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "TESTBENCH TIMEOUT");
    end

endmodule
