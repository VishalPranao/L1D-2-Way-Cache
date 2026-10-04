`timescale 1ns/1ps

module tb_l1d_cache;
    import cache_pkg::*;

    localparam int ID_COUNT = 1 << REQ_ID_WIDTH;
    localparam int RESPONSE_LOG_DEPTH = 256;

    logic clk;
    logic reset_n;

    logic                      cpu_req_valid;
    logic                      cpu_req_ready;
    logic [REQ_ID_WIDTH-1:0]   cpu_req_id;
    logic [ADDR_WIDTH-1:0]     cpu_req_addr;
    logic                      cpu_req_write;
    logic [DATA_WIDTH-1:0]     cpu_req_wdata;
    logic [WORD_BYTES-1:0]     cpu_req_wstrb;

    logic                      cpu_rsp_valid;
    logic                      cpu_rsp_ready;
    logic [REQ_ID_WIDTH-1:0]   cpu_rsp_id;
    logic [DATA_WIDTH-1:0]     cpu_rsp_rdata;

    logic                      axi_awvalid;
    logic                      axi_awready;
    logic [AXI_ID_WIDTH-1:0]   axi_awid;
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
    logic [AXI_ID_WIDTH-1:0]   axi_bid;
    logic [1:0]                axi_bresp;

    logic                      axi_arvalid;
    logic                      axi_arready;
    logic [AXI_ID_WIDTH-1:0]   axi_arid;
    logic [ADDR_WIDTH-1:0]     axi_araddr;
    logic [7:0]                axi_arlen;
    logic [2:0]                axi_arsize;
    logic [1:0]                axi_arburst;

    logic                      axi_rvalid;
    logic                      axi_rready;
    logic [AXI_ID_WIDTH-1:0]   axi_rid;
    logic [AXI_DATA_WIDTH-1:0] axi_rdata;
    logic                      axi_rlast;
    logic [1:0]                axi_rresp;

    logic [DATA_WIDTH-1:0] expected_by_id [0:ID_COUNT-1];
    logic                  expected_valid_by_id [0:ID_COUNT-1];
    logic                  response_seen_by_id [0:ID_COUNT-1];
    logic [DATA_WIDTH-1:0] observed_by_id [0:ID_COUNT-1];

    logic [REQ_ID_WIDTH-1:0] response_order_log
        [0:RESPONSE_LOG_DEPTH-1];

    integer cpu_request_count;
    integer cpu_response_count;
    integer response_order_count;

    integer axi_read_burst_count;
    integer axi_read_beat_count;
    integer axi_write_burst_count;
    integer axi_write_beat_count;
    integer axi_write_response_count;
    integer outstanding_read_count;
    integer max_outstanding_read_count;
    integer read_beat_monitor [0:NUM_MSHRS-1];
    integer write_beat_monitor;

    integer current_mshr_count;
    integer max_mshr_occupancy;
    integer merge_event_count;
    integer full_mshr_stall_count;
    integer reservation_stall_count;

    integer reads_before;
    integer read_beats_before;
    integer writes_before;
    integer write_beats_before;
    integer write_responses_before;
    integer merge_events_before;
    integer full_stalls_before;
    integer reservation_stalls_before;
    integer response_order_before;

    logic [ADDR_WIDTH-1:0] last_writeback_addr;
    logic [REQ_ID_WIDTH-1:0] stalled_response_id;
    logic [DATA_WIDTH-1:0] stalled_response_data;

    logic [DATA_WIDTH-1:0] merged_store_expected;

    integer monitor_id_number;
    integer occupancy_number;
    integer initialize_id_number;

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
        .m_axi_awid    (axi_awid),
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
        .m_axi_bid     (axi_bid),
        .m_axi_bresp   (axi_bresp),

        .m_axi_arvalid (axi_arvalid),
        .m_axi_arready (axi_arready),
        .m_axi_arid    (axi_arid),
        .m_axi_araddr  (axi_araddr),
        .m_axi_arlen   (axi_arlen),
        .m_axi_arsize  (axi_arsize),
        .m_axi_arburst (axi_arburst),

        .m_axi_rvalid  (axi_rvalid),
        .m_axi_rready  (axi_rready),
        .m_axi_rid     (axi_rid),
        .m_axi_rdata   (axi_rdata),
        .m_axi_rlast   (axi_rlast),
        .m_axi_rresp   (axi_rresp)
    );

    axi_memory_model #(
        .MEM_BYTES         (64 * 1024),
        .BASE_READ_LATENCY (12)
    ) memory_model (
        .clk           (clk),
        .reset_n       (reset_n),

        .s_axi_awvalid (axi_awvalid),
        .s_axi_awready (axi_awready),
        .s_axi_awid    (axi_awid),
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
        .s_axi_bid     (axi_bid),
        .s_axi_bresp   (axi_bresp),

        .s_axi_arvalid (axi_arvalid),
        .s_axi_arready (axi_arready),
        .s_axi_arid    (axi_arid),
        .s_axi_araddr  (axi_araddr),
        .s_axi_arlen   (axi_arlen),
        .s_axi_arsize  (axi_arsize),
        .s_axi_arburst (axi_arburst),

        .s_axi_rvalid  (axi_rvalid),
        .s_axi_rready  (axi_rready),
        .s_axi_rid     (axi_rid),
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
        input logic [WORD_BYTES-1:0] write_strobe,
        input logic [DATA_WIDTH-1:0] expected_response
    );
        begin
            @(negedge clk);

            if (expected_valid_by_id[request_id])
                $fatal(1, "Request ID %0d is already outstanding", request_id);

            expected_by_id[request_id]       = expected_response;
            expected_valid_by_id[request_id] = 1'b1;
            response_seen_by_id[request_id]  = 1'b0;

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
        input logic [ADDR_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] expected_response
    );
        begin
            issue_request(request_id, address, 1'b0, '0, '0,
                          expected_response);
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
                          write_data, write_strobe, '0);
        end
    endtask

    task automatic wait_for_response(
        input logic [REQ_ID_WIDTH-1:0] request_id,
        input string test_name
    );
        begin
            while (response_seen_by_id[request_id] !== 1'b1)
                @(negedge clk);

            $display("PASS RSP  : %-44s id=%0d data=%08h",
                     test_name, request_id, observed_by_id[request_id]);
            response_seen_by_id[request_id] = 1'b0;
        end
    endtask

    task automatic wait_cache_quiet;
        begin
            while (current_mshr_count != 0
                   || dut.lookup_state_q != LOOKUP_IDLE
                   || dut.response_queue.count_q != 0)
                @(negedge clk);

            @(negedge clk);
        end
    endtask

    task automatic load_and_wait(
        input logic [REQ_ID_WIDTH-1:0] request_id,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] expected_response,
        input string test_name
    );
        begin
            issue_load(request_id, address, expected_response);
            wait_for_response(request_id, test_name);
            wait_cache_quiet();
        end
    endtask

    task automatic store_and_wait(
        input logic [REQ_ID_WIDTH-1:0] request_id,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] write_data,
        input logic [WORD_BYTES-1:0] write_strobe,
        input string test_name
    );
        begin
            issue_store(request_id, address, write_data, write_strobe);
            wait_for_response(request_id, test_name);
            wait_cache_quiet();
        end
    endtask

    task automatic save_counts;
        begin
            reads_before              = axi_read_burst_count;
            read_beats_before         = axi_read_beat_count;
            writes_before             = axi_write_burst_count;
            write_beats_before        = axi_write_beat_count;
            write_responses_before    = axi_write_response_count;
            merge_events_before       = merge_event_count;
            full_stalls_before        = full_mshr_stall_count;
            reservation_stalls_before = reservation_stall_count;
            response_order_before     = response_order_count;
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

    always_comb begin
        current_mshr_count = 0;

        for (occupancy_number = 0;
             occupancy_number < NUM_MSHRS;
             occupancy_number = occupancy_number + 1) begin
            if (dut.mshr_valid_q[occupancy_number])
                current_mshr_count = current_mshr_count + 1;
        end
    end

    // Scoreboard and protocol monitor.
    always @(posedge clk) begin
        if (!reset_n) begin
            cpu_request_count          = 0;
            cpu_response_count         = 0;
            response_order_count       = 0;
            axi_read_burst_count       = 0;
            axi_read_beat_count        = 0;
            axi_write_burst_count      = 0;
            axi_write_beat_count       = 0;
            axi_write_response_count   = 0;
            outstanding_read_count     = 0;
            max_outstanding_read_count = 0;
            max_mshr_occupancy         = 0;
            merge_event_count          = 0;
            full_mshr_stall_count      = 0;
            reservation_stall_count    = 0;
            write_beat_monitor         = 0;
            last_writeback_addr        = '0;

            for (monitor_id_number = 0;
                 monitor_id_number < NUM_MSHRS;
                 monitor_id_number = monitor_id_number + 1) begin
                read_beat_monitor[monitor_id_number] = 0;
            end
        end
        else begin
            if (current_mshr_count > max_mshr_occupancy)
                max_mshr_occupancy = current_mshr_count;

            if (dut.merge_fire)
                merge_event_count = merge_event_count + 1;

            if (dut.lookup_state_q == LOOKUP_COMPARE
                && !dut.lookup_hit
                && !dut.mshr_match_valid
                && !dut.free_mshr_valid) begin
                full_mshr_stall_count = full_mshr_stall_count + 1;
            end

            if (dut.lookup_state_q == LOOKUP_COMPARE
                && !dut.lookup_hit
                && !dut.mshr_match_valid
                && dut.free_mshr_valid
                && !dut.lookup_victim_available) begin
                reservation_stall_count = reservation_stall_count + 1;
            end

            if (cpu_req_valid && cpu_req_ready)
                cpu_request_count = cpu_request_count + 1;

            if (cpu_rsp_valid && cpu_rsp_ready) begin
                cpu_response_count = cpu_response_count + 1;

                if (response_order_count >= RESPONSE_LOG_DEPTH)
                    $fatal(1, "Response-order log overflow");

                if (!expected_valid_by_id[cpu_rsp_id])
                    $fatal(1, "Unexpected response ID %0d", cpu_rsp_id);

                if (cpu_rsp_rdata !== expected_by_id[cpu_rsp_id]) begin
                    $fatal(1,
                        "Response mismatch: id=%0d expected=%08h actual=%08h",
                        cpu_rsp_id,
                        expected_by_id[cpu_rsp_id],
                        cpu_rsp_rdata);
                end

                observed_by_id[cpu_rsp_id]       = cpu_rsp_rdata;
                response_seen_by_id[cpu_rsp_id]  = 1'b1;
                expected_valid_by_id[cpu_rsp_id] = 1'b0;
                response_order_log[response_order_count] = cpu_rsp_id;
                response_order_count = response_order_count + 1;
            end

            case ({axi_arvalid && axi_arready,
                   axi_rvalid && axi_rready && axi_rlast})
                2'b10: begin
                    outstanding_read_count = outstanding_read_count + 1;
                    if (outstanding_read_count
                        > max_outstanding_read_count) begin
                        max_outstanding_read_count = outstanding_read_count;
                    end
                end
                2'b01: outstanding_read_count = outstanding_read_count - 1;
                default: outstanding_read_count = outstanding_read_count;
            endcase

            if (axi_arvalid && axi_arready) begin
                axi_read_burst_count = axi_read_burst_count + 1;
                read_beat_monitor[axi_arid] = 0;

                if (axi_araddr[OFFSET_BITS-1:0] != '0
                    || axi_arlen != AXI_LINE_LEN
                    || axi_arsize != AXI_WORD_SIZE
                    || axi_arburst != AXI_BURST_INCR) begin
                    $fatal(1, "Invalid AXI refill request");
                end
            end

            if (axi_rvalid && axi_rready) begin
                axi_read_beat_count = axi_read_beat_count + 1;

                if (axi_rlast
                    != (read_beat_monitor[axi_rid]
                        == AXI_BEATS_PER_LINE - 1)) begin
                    $fatal(1,
                        "Incorrect RLAST for RID %0d on beat %0d",
                        axi_rid, read_beat_monitor[axi_rid]);
                end

                if (axi_rlast)
                    read_beat_monitor[axi_rid] = 0;
                else
                    read_beat_monitor[axi_rid]
                        = read_beat_monitor[axi_rid] + 1;
            end

            if (axi_awvalid && axi_awready) begin
                axi_write_burst_count = axi_write_burst_count + 1;
                write_beat_monitor    = 0;
                last_writeback_addr   = axi_awaddr;

                if (axi_awaddr[OFFSET_BITS-1:0] != '0
                    || axi_awlen != AXI_LINE_LEN
                    || axi_awsize != AXI_WORD_SIZE
                    || axi_awburst != AXI_BURST_INCR) begin
                    $fatal(1, "Invalid AXI writeback request");
                end
            end

            if (axi_wvalid && axi_wready) begin
                axi_write_beat_count = axi_write_beat_count + 1;

                if (axi_wstrb != {AXI_BYTES{1'b1}})
                    $fatal(1, "Writeback beat did not enable every byte");

                if (axi_wlast
                    != (write_beat_monitor == AXI_BEATS_PER_LINE - 1)) begin
                    $fatal(1, "Incorrect WLAST on beat %0d",
                           write_beat_monitor);
                end

                if (axi_wlast)
                    write_beat_monitor = 0;
                else
                    write_beat_monitor = write_beat_monitor + 1;
            end

            if (axi_bvalid && axi_bready)
                axi_write_response_count = axi_write_response_count + 1;
        end
    end

    initial begin
        reset_n       = 1'b0;
        cpu_req_valid = 1'b0;
        cpu_req_id    = '0;
        cpu_req_addr  = '0;
        cpu_req_write = 1'b0;
        cpu_req_wdata = '0;
        cpu_req_wstrb = '0;
        cpu_rsp_ready = 1'b1;

        for (initialize_id_number = 0;
             initialize_id_number < ID_COUNT;
             initialize_id_number = initialize_id_number + 1) begin
            expected_by_id[initialize_id_number]       = '0;
            expected_valid_by_id[initialize_id_number] = 1'b0;
            response_seen_by_id[initialize_id_number]  = 1'b0;
            observed_by_id[initialize_id_number]       = '0;
        end

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;

        // Prime H for a later hit-under-multiple-misses request.
        load_and_wait(4'd0, 32'h0000_0104,
                      expected_word(32'h0000_0104),
                      "prime cached line H");

        // Two independent misses occupy two MSHRs. The memory model returns
        // MSHR 1 before MSHR 0, while a younger cached hit responds first.
        save_counts();
        issue_load(4'd1, 32'h0000_0404,
                   expected_word(32'h0000_0404));
        issue_load(4'd2, 32'h0000_0444,
                   expected_word(32'h0000_0444));
        issue_load(4'd3, 32'h0000_0104,
                   expected_word(32'h0000_0104));

        wait_for_response(4'd1, "first independent miss A");
        wait_for_response(4'd2, "second independent miss B");
        wait_for_response(4'd3, "hit under two active misses");
        wait_cache_quiet();

        if (response_order_log[response_order_before] !== 4'd3
            || response_order_log[response_order_before + 1] !== 4'd2
            || response_order_log[response_order_before + 2] !== 4'd1) begin
            $fatal(1,
                "Expected response order H,B,A; got IDs %0d,%0d,%0d",
                response_order_log[response_order_before],
                response_order_log[response_order_before + 1],
                response_order_log[response_order_before + 2]);
        end

        expect_axi_delta(2, 16, 0, 0, 0,
                         "two concurrent clean misses use two AXI IDs");

        // Three CPU misses to one line merge into one MSHR and one AXI burst.
        save_counts();
        issue_load(4'd4, 32'h0000_0800,
                   expected_word(32'h0000_0800));
        issue_load(4'd5, 32'h0000_0804,
                   expected_word(32'h0000_0804));
        issue_load(4'd6, 32'h0000_0808,
                   expected_word(32'h0000_0808));

        wait_for_response(4'd4, "primary same-line miss");
        wait_for_response(4'd5, "first merged same-line load");
        wait_for_response(4'd6, "second merged same-line load");
        wait_cache_quiet();

        if ((merge_event_count - merge_events_before) != 2)
            $fatal(1, "Expected exactly two same-line merge events");

        expect_axi_delta(1, 8, 0, 0, 0,
                         "three same-line loads share one refill");

        // A store miss followed by a same-line load is processed in arrival
        // order. The load must observe the store-modified MSHR work line.
        merged_store_expected = merge_word(
            expected_word(32'h0000_0C24),
            32'hDEAD_BEEF,
            4'b1111
        );

        save_counts();
        issue_store(4'd7, 32'h0000_0C24,
                    32'hDEAD_BEEF, 4'b1111);
        issue_load(4'd8, 32'h0000_0C24,
                   merged_store_expected);
        wait_for_response(4'd7, "merged store-miss response");
        wait_for_response(4'd8, "merged load observes older store");
        wait_cache_quiet();
        expect_axi_delta(1, 8, 0, 0, 0,
                         "store and load merge into one refill");

        load_and_wait(4'd9, 32'h0000_0C24,
                      merged_store_expected,
                      "installed merged-store line remains a hit");

        // Fill all four MSHRs, then accept a fifth miss into the lookup slot.
        // The fifth request retries until one MSHR becomes free.
        save_counts();
        issue_load(4'd10, 32'h0000_3004,
                   expected_word(32'h0000_3004));
        issue_load(4'd11, 32'h0000_3044,
                   expected_word(32'h0000_3044));
        issue_load(4'd12, 32'h0000_3084,
                   expected_word(32'h0000_3084));
        issue_load(4'd13, 32'h0000_30C4,
                   expected_word(32'h0000_30C4));
        issue_load(4'd14, 32'h0000_3104,
                   expected_word(32'h0000_3104));

        wait_for_response(4'd10, "MSHR-full request 0");
        wait_for_response(4'd11, "MSHR-full request 1");
        wait_for_response(4'd12, "MSHR-full request 2");
        wait_for_response(4'd13, "MSHR-full request 3");
        wait_for_response(4'd14, "fifth miss retries after MSHR frees");
        wait_cache_quiet();

        if (max_mshr_occupancy != NUM_MSHRS)
            $fatal(1, "Expected all %0d MSHRs to become occupied",
                   NUM_MSHRS);

        if ((full_mshr_stall_count - full_stalls_before) == 0)
            $fatal(1, "Fifth miss never stalled for a free MSHR");

        expect_axi_delta(5, 40, 0, 0, 0,
                         "four MSHRs plus retried fifth miss");

        // Three different lines map to one two-way set. The first two reserve
        // both ways; the third waits until an installation releases one way.
        save_counts();
        issue_load(4'd0, 32'h0000_4144,
                   expected_word(32'h0000_4144));
        issue_load(4'd1, 32'h0000_4944,
                   expected_word(32'h0000_4944));
        issue_load(4'd2, 32'h0000_5144,
                   expected_word(32'h0000_5144));

        wait_for_response(4'd0, "same-set miss E");
        wait_for_response(4'd1, "same-set miss F");
        wait_for_response(4'd2, "same-set miss G waits for victim way");
        wait_cache_quiet();

        if ((reservation_stall_count - reservation_stalls_before) == 0)
            $fatal(1, "Third same-set miss never saw both ways reserved");

        expect_axi_delta(3, 24, 0, 0, 0,
                         "same-set reservations prevent victim collision");

        // Build dirty A and clean B in one set. Miss C writes back A while an
        // unrelated clean miss U uses another MSHR and AXI read transaction.
        load_and_wait(4'd3, 32'h0000_4184,
                      expected_word(32'h0000_4184),
                      "fill dirty-conflict line A");
        store_and_wait(4'd4, 32'h0000_4184,
                       32'hCAFE_BABE, 4'b1111,
                       "make line A dirty");
        load_and_wait(4'd5, 32'h0000_4984,
                      expected_word(32'h0000_4984),
                      "fill clean conflict line B");

        save_counts();
        issue_load(4'd6, 32'h0000_5184,
                   expected_word(32'h0000_5184));
        issue_load(4'd7, 32'h0000_6044,
                   expected_word(32'h0000_6044));
        wait_for_response(4'd6, "dirty-victim miss C");
        wait_for_response(4'd7, "clean miss concurrent with writeback");
        wait_cache_quiet();

        if (last_writeback_addr !== 32'h0000_4180) begin
            $fatal(1, "Expected dirty writeback at 0x4180; got %08h",
                   last_writeback_addr);
        end

        expect_axi_delta(2, 16, 1, 8, 1,
                         "dirty writeback overlaps independent refill");

        load_and_wait(4'd8, 32'h0000_4184, 32'hCAFE_BABE,
                      "dirty victim data reaches lower memory");

        // Response FIFO test: let several misses finish while the CPU refuses
        // responses, verify the head payload is stable, then drain the FIFO.
        save_counts();
        @(negedge clk);
        cpu_rsp_ready = 1'b0;

        issue_load(4'd9, 32'h0000_7004,
                   expected_word(32'h0000_7004));
        issue_load(4'd10, 32'h0000_7044,
                   expected_word(32'h0000_7044));
        issue_load(4'd11, 32'h0000_7084,
                   expected_word(32'h0000_7084));
        issue_load(4'd12, 32'h0000_70C4,
                   expected_word(32'h0000_70C4));

        while (cpu_rsp_valid !== 1'b1)
            @(negedge clk);

        stalled_response_id   = cpu_rsp_id;
        stalled_response_data = cpu_rsp_rdata;

        repeat (4) begin
            @(negedge clk);
            if (cpu_rsp_valid !== 1'b1
                || cpu_rsp_id !== stalled_response_id
                || cpu_rsp_rdata !== stalled_response_data) begin
                $fatal(1, "Response FIFO head changed under backpressure");
            end
        end

        cpu_rsp_ready = 1'b1;
        wait_for_response(4'd9, "backpressured response 0");
        wait_for_response(4'd10, "backpressured response 1");
        wait_for_response(4'd11, "backpressured response 2");
        wait_for_response(4'd12, "backpressured response 3");
        wait_cache_quiet();
        expect_axi_delta(4, 32, 0, 0, 0,
                         "response FIFO buffers multiple miss completions");

        if (max_outstanding_read_count < 2)
            $fatal(1, "AXI model never observed multiple outstanding reads");

        if (cpu_request_count != cpu_response_count) begin
            $fatal(1,
                "CPU request/response mismatch: requests=%0d responses=%0d",
                cpu_request_count, cpu_response_count);
        end

        if (outstanding_read_count != 0)
            $fatal(1, "Outstanding AXI reads remain at end of simulation");

        $display("--------------------------------------------------");
        $display("ALL PHASE 6 MULTI-MSHR AND MISS-UNDER-MISS TESTS PASSED");
        $display("--------------------------------------------------");

        #20;
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "TESTBENCH TIMEOUT");
    end

endmodule
