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

            // Drive request before the active clock edge.
            @(negedge clk);
            cpu_req_addr  = address;
            cpu_req_valid = 1'b1;

            // Wait until the cache accepts the request.
            do begin
                @(posedge clk);
            end while (!cpu_req_ready);

            @(negedge clk);
            cpu_req_valid = 1'b0;

            // The cache holds its response until cpu_rsp_ready is asserted.
            wait (cpu_rsp_valid === 1'b1);
            #1;

            if (cpu_rsp_rdata !== expected_data) begin
                $error("LOAD FAILED: addr=%08h expected=%08h actual=%08h",
                       address, expected_data, cpu_rsp_rdata);
                $fatal(1);
            end

            $display("PASS: load addr=%08h data=%08h",
                     address, cpu_rsp_rdata);

            // Allow the RESPONSE -> IDLE handshake to complete.
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

    // Count accepted lower-memory requests and check line alignment.
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

        // Test 1: first access to line 0x1000 must miss and refill.
        request_count_before = memory_request_count;
        load_and_check(32'h0000_1004);
        expect_memory_requests(request_count_before + 1,
                               "cold miss and refill");

        // Test 2: 0x100C is in the same 32-byte line, so it must hit.
        request_count_before = memory_request_count;
        load_and_check(32'h0000_100C);
        expect_memory_requests(request_count_before,
                               "same-line cache hit");

        // Test 3: adding 0x800 keeps the index but changes the tag.
        // A direct-mapped cache must replace the existing line.
        request_count_before = memory_request_count;
        load_and_check(32'h0000_1804);
        expect_memory_requests(request_count_before + 1,
                               "same-index conflict miss");

        // Test 4: the original 0x1000 line was evicted, so it misses again.
        request_count_before = memory_request_count;
        load_and_check(32'h0000_1004);
        expect_memory_requests(request_count_before + 1,
                               "access after conflict eviction");

        $display("--------------------------------------------------");
        $display("ALL PHASE 1 L1D CACHE TESTS PASSED");
        $display("--------------------------------------------------");

        #20;
        $finish;
    end

    initial begin
        // Prevent an accidental FSM or handshake deadlock from hanging sim.
        #5000;
        $fatal(1, "TESTBENCH TIMEOUT");
    end

endmodule
