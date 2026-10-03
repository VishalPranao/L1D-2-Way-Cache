`timescale 1ns/1ps

module tb_l1d_cache;
    import cache_pkg::*;

    localparam int RESPONSE_LOG_DEPTH = 128;

    logic clk;
    logic reset_n;

    logic                        cpu_req_valid;
    logic                        cpu_req_ready;
    logic [REQ_ID_WIDTH-1:0]     cpu_req_id;
    logic [ADDR_WIDTH-1:0]       cpu_req_addr;
    logic                        cpu_req_write;
    logic [DATA_WIDTH-1:0]       cpu_req_wdata;
    logic [WORD_BYTES-1:0]       cpu_req_wstrb;

    logic                        cpu_rsp_valid;
    logic                        cpu_rsp_ready;
    logic [REQ_ID_WIDTH-1:0]     cpu_rsp_id;
    logic [DATA_WIDTH-1:0]       cpu_rsp_rdata;

    logic                        axi_awvalid;
    logic                        axi_awready;
    logic [ADDR_WIDTH-1:0]       axi_awaddr;
    logic [7:0]                  axi_awlen;
    logic [2:0]                  axi_awsize;
    logic [1:0]                  axi_awburst;

    logic                        axi_wvalid;
    logic                        axi_wready;
    logic [AXI_DATA_WIDTH-1:0]   axi_wdata;
    logic [AXI_BYTES-1:0]        axi_wstrb;
    logic                        axi_wlast;

    logic                        axi_bvalid;
    logic                        axi_bready;
    logic [1:0]                  axi_bresp;

    logic                        axi_arvalid;
    logic                        axi_arready;
    logic [ADDR_WIDTH-1:0]       axi_araddr;
    logic [7:0]                  axi_arlen;
    logic [2:0]                  axi_arsize;
    logic [1:0]                  axi_arburst;

    logic                        axi_rvalid;
    logic                        axi_rready;
    logic [AXI_DATA_WIDTH-1:0]   axi_rdata;
    logic                        axi_rlast;
    logic [1:0]                  axi_rresp;

    integer axi_read_burst_count;
    integer axi_read_beat_count;
    integer axi_write_burst_count;
    integer axi_write_beat_count;
    integer axi_write_response_count;
    integer read_beat_monitor;
    integer write_beat_monitor;
    integer cpu_request_count;
    integer cpu_response_count;
    integer hit_under_miss_count;
    integer second_miss_wait_count;

    logic [ADDR_WIDTH-1:0] last_refill_addr;
    logic [ADDR_WIDTH-1:0] last_writeback_addr;

    integer reads_before;
    integer read_beats_before;
    integer writes_before;
    integer write_beats_before;
    integer write_responses_before;

    logic [REQ_ID_WIDTH-1:0] response_id_log
        [0:RESPONSE_LOG_DEPTH-1];
    logic [DATA_WIDTH-1:0] response_data_log
        [0:RESPONSE_LOG_DEPTH-1];
    integer response_log_count;
    integer next_response_to_check;

    logic [DATA_WIDTH-1:0] expected_store_miss_word;
    logic [REQ_ID_WIDTH-1:0] stalled_response_id;
    logic [DATA_WIDTH-1:0] stalled_response_data;

    l1d_cache dut (
        .clk           (clk),
        .reset_n       (reset_n),

        .cpu_req_valid (cpu_req_valid),
        .cpu_req_ready (cpu_req_ready),
        .cpu_req_id    (cpu_req_id),
        .cpu_req_addr  (cpu_req_addr),
        .cpu_req_write (cpu_req_write),
        .cpu_req_wdata (cpu_req_wdata),
        .cpu_req_wstrb (cpu_req_wstrb),

        .cpu_rsp_valid (cpu_rsp_valid),
        .cpu_rsp_ready (cpu_rsp_ready),
        .cpu_rsp_id    (cpu_rsp_id),
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
        .READ_LATENCY (5)
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

    task automatic issue_request(
        input logic [REQ_ID_WIDTH-1:0] request_id,
        input logic [ADDR_WIDTH-1:0] address,
        input logic write_request,
        input logic [DATA_WIDTH-1:0] write_data,
        input logic [WORD_BYTES-1:0] write_strobe
    );
        begin
            @(negedge clk);
            cpu_req_id    = request_id;
            cpu_req_addr  = address;
            cpu_req_write = write_request;
            cpu_req_wdata = write_data;
            cpu_req_wstrb = write_strobe;
            cpu_req_valid = 1'b1;
            #1;

            while (cpu_req_ready !== 1'b1)
                @(negedge clk);

            @(posedge clk);
            @(negedge clk);
            cpu_req_valid = 1'b0;
        end
    endtask

    task automatic issue_load(
        input logic [REQ_ID_WIDTH-1:0] request_id,
        input logic [ADDR_WIDTH-1:0] address
    );
        begin
            issue_request(request_id, address, 1'b0, '0, '0);
        end
    endtask

    task automatic issue_store(
        input logic [REQ_ID_WIDTH-1:0] request_id,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] write_data,
        input logic [WORD_BYTES-1:0] write_strobe
    );
        begin
            issue_request(request_id, address, 1'b1,
                          write_data, write_strobe);
        end
    endtask

    task automatic expect_response(
        input logic [REQ_ID_WIDTH-1:0] expected_id,
        input logic [DATA_WIDTH-1:0] expected_data,
        input string test_name
    );
        begin
            while (response_log_count <= next_response_to_check)
                @(negedge clk);

            if (response_id_log[next_response_to_check] !== expected_id
                || response_data_log[next_response_to_check]
                   !== expected_data) begin
                $error("%s: response mismatch", test_name);
                $display("  expected id=%0d data=%08h",
                         expected_id, expected_data);
                $display("  actual   id=%0d data=%08h",
                         response_id_log[next_response_to_check],
                         response_data_log[next_response_to_check]);
                $fatal(1);
            end

            $display("PASS RSP  : %-42s id=%0d data=%08h",
                     test_name, expected_id, expected_data);
            next_response_to_check = next_response_to_check + 1;
        end
    endtask

    task automatic load_and_check(
        input logic [REQ_ID_WIDTH-1:0] request_id,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] expected_data,
        input string test_name
    );
        begin
            issue_load(request_id, address);
            expect_response(request_id, expected_data, test_name);
        end
    endtask

    task automatic store_and_check(
        input logic [REQ_ID_WIDTH-1:0] request_id,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] write_data,
        input logic [WORD_BYTES-1:0] write_strobe,
        input string test_name
    );
        begin
            issue_store(request_id, address, write_data, write_strobe);
            expect_response(request_id, '0, test_name);
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
        input string test_name
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

    // AXI and CPU protocol monitor plus a response log used to check explicit
    // out-of-order completion by request ID.
    always @(posedge clk) begin
        if (!reset_n) begin
            axi_read_burst_count     <= 0;
            axi_read_beat_count      <= 0;
            axi_write_burst_count    <= 0;
            axi_write_beat_count     <= 0;
            axi_write_response_count <= 0;
            read_beat_monitor         <= 0;
            write_beat_monitor        <= 0;
            cpu_request_count         <= 0;
            cpu_response_count        <= 0;
            hit_under_miss_count      <= 0;
            second_miss_wait_count    <= 0;
            response_log_count        <= 0;
            last_refill_addr          <= '0;
            last_writeback_addr       <= '0;
        end
        else begin
            if (cpu_req_valid && cpu_req_ready)
                cpu_request_count <= cpu_request_count + 1;

            if (cpu_rsp_valid && cpu_rsp_ready) begin
                cpu_response_count <= cpu_response_count + 1;

                if (response_log_count >= RESPONSE_LOG_DEPTH)
                    $fatal(1, "Response log overflow");

                response_id_log[response_log_count] <= cpu_rsp_id;
                response_data_log[response_log_count] <= cpu_rsp_rdata;
                response_log_count <= response_log_count + 1;

                if (dut.mshr_valid_q)
                    hit_under_miss_count <= hit_under_miss_count + 1;
            end

            if (dut.lookup_state_q == LOOKUP_WAIT_MSHR)
                second_miss_wait_count <= second_miss_wait_count + 1;

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
                last_writeback_addr   <= axi_awaddr;

                if (axi_awaddr[OFFSET_BITS-1:0] != '0
                    || axi_awlen != AXI_LINE_LEN
                    || axi_awsize != AXI_WORD_SIZE
                    || axi_awburst != AXI_BURST_INCR) begin
                    $fatal(1, "Invalid AXI writeback request");
                end
            end

            if (axi_wvalid && axi_wready) begin
                axi_write_beat_count <= axi_write_beat_count + 1;

                if (axi_wstrb != {AXI_BYTES{1'b1}})
                    $fatal(1, "Writeback beat did not enable all bytes");

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
        reset_n               = 1'b0;
        cpu_req_valid         = 1'b0;
        cpu_req_id            = '0;
        cpu_req_addr          = '0;
        cpu_req_write         = 1'b0;
        cpu_req_wdata         = '0;
        cpu_req_wstrb         = '0;
        cpu_rsp_ready         = 1'b1;
        next_response_to_check = 0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;

        // Prime a line that later requests can hit while unrelated misses are
        // active in the MSHR.
        load_and_check(4'd0, 32'h0000_0104,
                       expected_word(32'h0000_0104),
                       "prime hit-under-miss line H");

        // A younger load hit completes before the older clean miss. The IDs
        // prove that the response order is intentional and unambiguous.
        save_axi_counts();
        issue_load(4'd1, 32'h0000_0404);
        issue_load(4'd2, 32'h0000_0104);
        expect_response(4'd2, expected_word(32'h0000_0104),
                        "younger load hit bypasses older miss");
        expect_response(4'd1, expected_word(32'h0000_0404),
                        "older clean miss completes after hit");
        expect_axi_delta(1, 8, 0, 0, 0,
                         "load hit-under-miss uses one refill");

        // Store hits are also allowed under a miss and still mark their line
        // dirty. A following hit observes the stored value.
        save_axi_counts();
        issue_load(4'd3, 32'h0000_0444);
        issue_store(4'd4, 32'h0000_0104, 32'hDEAD_BEEF, 4'b1111);
        expect_response(4'd4, '0,
                        "store hit completes under clean miss");
        expect_response(4'd3, expected_word(32'h0000_0444),
                        "clean miss completes after store hit");
        expect_axi_delta(1, 8, 0, 0, 0,
                         "store hit-under-miss adds no AXI transfer");
        load_and_check(4'd5, 32'h0000_0104, 32'hDEAD_BEEF,
                       "read-after-write of under-miss store");

        // A request to the line currently being refilled cannot hit stale
        // data. It waits, refreshes its array snapshot, then hits the install.
        save_axi_counts();
        issue_load(4'd6, 32'h0000_0800);
        issue_load(4'd7, 32'h0000_0804);
        expect_response(4'd6, expected_word(32'h0000_0800),
                        "original same-line miss response");
        expect_response(4'd7, expected_word(32'h0000_0804),
                        "same-line request retries after install");
        expect_axi_delta(1, 8, 0, 0, 0,
                         "same-line waiter does not launch second refill");

        // A true second miss is accepted into the lookup slot but waits for
        // the one MSHR. The two refills occur serially, not concurrently.
        save_axi_counts();
        issue_load(4'd8, 32'h0000_0844);
        issue_load(4'd9, 32'h0000_0884);
        expect_response(4'd8, expected_word(32'h0000_0844),
                        "first of two serialized misses");
        expect_response(4'd9, expected_word(32'h0000_0884),
                        "second miss starts after MSHR frees");
        expect_axi_delta(2, 16, 0, 0, 0,
                         "single MSHR serializes two misses");

        // Build a dirty LRU victim: A and B map to the same set, then C is a
        // third line in that set. H can still hit during A's writeback/refill.
        load_and_check(4'd10, 32'h0000_1144,
                       expected_word(32'h0000_1144),
                       "fill conflict line A");
        store_and_check(4'd11, 32'h0000_1144,
                        32'hCAFE_BABE, 4'b1111,
                        "make conflict line A dirty");
        load_and_check(4'd12, 32'h0000_1944,
                       expected_word(32'h0000_1944),
                       "fill conflict line B");

        save_axi_counts();
        issue_load(4'd13, 32'h0000_2144);
        issue_load(4'd14, 32'h0000_0104);
        expect_response(4'd14, 32'hDEAD_BEEF,
                        "hit proceeds during dirty writeback miss");
        expect_response(4'd13, expected_word(32'h0000_2144),
                        "dirty miss completes after writeback/refill");
        expect_axi_delta(1, 8, 1, 8, 1,
                         "dirty miss uses writeback then refill");

        if (last_writeback_addr !== 32'h0000_1140
            || last_refill_addr !== 32'h0000_2140) begin
            $fatal(1,
                "Wrong dirty-miss addresses: writeback=%08h refill=%08h",
                last_writeback_addr, last_refill_addr);
        end

        load_and_check(4'd15, 32'h0000_1144, 32'hCAFE_BABE,
                       "reload observes dirty victim writeback");

        // A store miss is merged into the MSHR refill before installation. It
        // needs one read burst and no replay through the lookup controller.
        expected_store_miss_word = merge_word(
            expected_word(32'h0000_0C20),
            32'h1234_0000,
            4'b1100
        );
        save_axi_counts();
        store_and_check(4'd1, 32'h0000_0C22,
                        32'h1234_0000, 4'b1100,
                        "store miss merges into refill line");
        load_and_check(4'd2, 32'h0000_0C20,
                       expected_store_miss_word,
                       "load observes merged store-miss bytes");
        expect_axi_delta(1, 8, 0, 0, 0,
                         "store miss performs one refill only");

        // Hold response READY low and verify the registered response payload
        // remains unchanged until it is accepted.
        save_axi_counts();
        @(negedge clk);
        cpu_rsp_ready = 1'b0;
        issue_load(4'd3, 32'h0000_0C64);

        while (cpu_rsp_valid !== 1'b1)
            @(negedge clk);

        stalled_response_id   = cpu_rsp_id;
        stalled_response_data = cpu_rsp_rdata;

        repeat (4) begin
            @(negedge clk);
            if (cpu_rsp_valid !== 1'b1
                || cpu_rsp_id !== stalled_response_id
                || cpu_rsp_rdata !== stalled_response_data) begin
                $fatal(1, "CPU response changed while READY was low");
            end
        end

        cpu_rsp_ready = 1'b1;
        expect_response(4'd3, expected_word(32'h0000_0C64),
                        "response remains stable under backpressure");
        expect_axi_delta(1, 8, 0, 0, 0,
                         "backpressured miss still uses one refill");

        if (hit_under_miss_count < 3) begin
            $fatal(1,
                "Expected at least three responses while MSHR was active; got %0d",
                hit_under_miss_count);
        end

        if (second_miss_wait_count == 0)
            $fatal(1, "LOOKUP_WAIT_MSHR was never exercised");

        @(negedge clk);
        if (cpu_request_count != cpu_response_count) begin
            $fatal(1,
                "CPU request/response mismatch: requests=%0d responses=%0d",
                cpu_request_count, cpu_response_count);
        end

        if (dut.mshr_valid_q !== 1'b0)
            $fatal(1, "MSHR should be free at end of test");

        $display("--------------------------------------------------");
        $display("ALL PHASE 5 ONE-MSHR AND HIT-UNDER-MISS TESTS PASSED");
        $display("--------------------------------------------------");

        #20;
        $finish;
    end

    initial begin
        #50000;
        $fatal(1, "TESTBENCH TIMEOUT");
    end

endmodule
