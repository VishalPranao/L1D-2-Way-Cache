`timescale 1ns/1ps

module tb_l1d_cache;
    import cache_pkg::*;

    logic clk;
    logic reset_n;

    logic                  cpu_req_valid;
    logic                  cpu_req_ready;
    logic [ADDR_WIDTH-1:0] cpu_req_addr;

    logic                  cpu_rsp_valid;
    logic                  cpu_rsp_ready;
    logic [DATA_WIDTH-1:0] cpu_rsp_rdata;

    logic                  mem_req_valid;
    logic                  mem_req_ready;
    logic [ADDR_WIDTH-1:0] mem_req_addr;

    logic                  mem_rsp_valid;
    logic                  mem_rsp_ready;
    line_t                 mem_rsp_data;

    integer memory_request_count;
    integer request_count_before;

    l1d_cache dut (
        .clk           (clk),
        .reset_n       (reset_n),
        .cpu_req_valid (cpu_req_valid),
        .cpu_req_ready (cpu_req_ready),
        .cpu_req_addr  (cpu_req_addr),
        .cpu_rsp_valid (cpu_rsp_valid),
        .cpu_rsp_ready (cpu_rsp_ready),
        .cpu_rsp_rdata (cpu_rsp_rdata),
        .mem_req_valid (mem_req_valid),
        .mem_req_ready (mem_req_ready),
        .mem_req_addr  (mem_req_addr),
        .mem_rsp_valid (mem_rsp_valid),
        .mem_rsp_ready (mem_rsp_ready),
        .mem_rsp_data  (mem_rsp_data)
    );

    simple_memory #(
        .MEM_BYTES (64 * 1024),
        .LATENCY   (3)
    ) memory_model (
        .clk           (clk),
        .reset_n       (reset_n),
        .mem_req_valid (mem_req_valid),
        .mem_req_ready (mem_req_ready),
        .mem_req_addr  (mem_req_addr),
        .mem_rsp_valid (mem_rsp_valid),
        .mem_rsp_ready (mem_rsp_ready),
        .mem_rsp_data  (mem_rsp_data)
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

    task automatic load_and_check(
        input logic [ADDR_WIDTH-1:0] address
    );
        logic [DATA_WIDTH-1:0] expected_data;
        begin
            expected_data = expected_word(address);

            @(negedge clk);
            cpu_req_addr  = address;
            cpu_req_valid = 1'b1;

            do begin
                @(posedge clk);
            end while (!cpu_req_ready);

            @(negedge clk);
            cpu_req_valid = 1'b0;

            wait (cpu_rsp_valid === 1'b1);
            #1;

            if (cpu_rsp_rdata !== expected_data) begin
                $error("LOAD FAILED: addr=%08h expected=%08h actual=%08h",
                       address, expected_data, cpu_rsp_rdata);
                $fatal(1);
            end

            $display("PASS: load addr=%08h data=%08h",
                     address, cpu_rsp_rdata);

            @(posedge clk);
            wait (cpu_req_ready === 1'b1);
        end
    endtask

    task automatic expect_memory_requests(
        input integer expected_count,
        input string  test_name
    );
        begin
            if (memory_request_count != expected_count) begin
                $error("%s: expected memory-request count %0d, got %0d",
                       test_name, expected_count, memory_request_count);
                $fatal(1);
            end

            $display("PASS: %s, memory requests=%0d",
                     test_name, memory_request_count);
        end
    endtask

    always @(posedge clk) begin
        if (!reset_n) begin
            memory_request_count <= 0;
        end
        else if (mem_req_valid && mem_req_ready) begin
            memory_request_count <= memory_request_count + 1;

            if (mem_req_addr[OFFSET_BITS-1:0] != '0) begin
                $error("Memory request was not line aligned: %08h",
                       mem_req_addr);
                $fatal(1);
            end
        end
    end

    initial begin
        reset_n       = 1'b0;
        cpu_req_valid = 1'b0;
        cpu_req_addr  = '0;
        cpu_rsp_ready = 1'b1;

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;

        // A: Both ways are invalid, so the first line fills Way 0.
        request_count_before = memory_request_count;
        load_and_check(32'h0000_1004);
        expect_memory_requests(request_count_before + 1,
                               "A cold miss fills Way 0");

        // B: Same set, different tag. Way 1 is invalid, so B must use it
        // instead of replacing A.
        request_count_before = memory_request_count;
        load_and_check(32'h0000_1804);
        expect_memory_requests(request_count_before + 1,
                               "B uses invalid Way 1");

        // Prove B is present and can hit from Way 1.
        request_count_before = memory_request_count;
        load_and_check(32'h0000_180C);
        expect_memory_requests(request_count_before,
                               "B hits in Way 1");

        // Prove A was not evicted when B filled the second way. This access
        // also makes A most recently used, so B becomes the next LRU victim.
        request_count_before = memory_request_count;
        load_and_check(32'h0000_100C);
        expect_memory_requests(request_count_before,
                               "A still hits in Way 0");

        // C: A third line mapping to Set 0 arrives. Both ways are valid, so
        // LRU must evict B, which is currently in Way 1.
        request_count_before = memory_request_count;
        load_and_check(32'h0000_2004);
        expect_memory_requests(request_count_before + 1,
                               "C causes LRU replacement");

        // A was most recently used before C arrived, so it must remain.
        request_count_before = memory_request_count;
        load_and_check(32'h0000_1004);
        expect_memory_requests(request_count_before,
                               "A survived LRU replacement");

        // B should have been the victim, so accessing it must miss now.
        request_count_before = memory_request_count;
        load_and_check(32'h0000_1804);
        expect_memory_requests(request_count_before + 1,
                               "B misses after LRU eviction");

        // Access another set and then prove Set 0 was not disturbed.
        request_count_before = memory_request_count;
        load_and_check(32'h0000_1024);
        expect_memory_requests(request_count_before + 1,
                               "different-set cold miss");

        request_count_before = memory_request_count;
        load_and_check(32'h0000_1004);
        expect_memory_requests(request_count_before,
                               "different set does not disturb Set 0");

        $display("--------------------------------------------------");
        $display("ALL PHASE 2 TWO-WAY L1D CACHE TESTS PASSED");
        $display("--------------------------------------------------");

        #20;
        $finish;
    end

    initial begin
        #8000;
        $fatal(1, "TESTBENCH TIMEOUT");
    end

endmodule
