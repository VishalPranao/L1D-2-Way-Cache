`timescale 1ns/1ps

module tb_l1d_cache;
    import cache_pkg::*;

    localparam int ID_COUNT = 1 << REQ_ID_WIDTH;

    logic clk;
    logic reset_n;

    logic                    cpu_req_valid;
    logic                    cpu_req_ready;
    logic [REQ_ID_WIDTH-1:0] cpu_req_id;
    logic [ADDR_WIDTH-1:0]   cpu_req_addr;
    logic                    cpu_req_write;
    logic [DATA_WIDTH-1:0]   cpu_req_wdata;
    logic [WORD_BYTES-1:0]   cpu_req_wstrb;

    logic                    cpu_rsp_valid;
    logic                    cpu_rsp_ready;
    logic [REQ_ID_WIDTH-1:0] cpu_rsp_id;
    logic [DATA_WIDTH-1:0]   cpu_rsp_rdata;
    logic                    cpu_rsp_error;

    logic flush_valid;
    logic flush_ready;
    logic flush_done;
    logic flush_error;

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

    logic force_read_error;
    logic force_write_error;

    logic response_seen [0:ID_COUNT-1];
    logic [DATA_WIDTH-1:0] response_data [0:ID_COUNT-1];
    logic response_error [0:ID_COUNT-1];

    integer read_burst_count;
    integer write_burst_count;
    integer response_id_number;
    integer reads_before;

    l1d_cache dut (
        .clk             (clk),
        .reset_n         (reset_n),
        .cpu_req_valid   (cpu_req_valid),
        .cpu_req_ready   (cpu_req_ready),
        .cpu_req_id      (cpu_req_id),
        .cpu_req_addr    (cpu_req_addr),
        .cpu_req_write   (cpu_req_write),
        .cpu_req_wdata   (cpu_req_wdata),
        .cpu_req_wstrb   (cpu_req_wstrb),
        .cpu_rsp_valid   (cpu_rsp_valid),
        .cpu_rsp_ready   (cpu_rsp_ready),
        .cpu_rsp_id      (cpu_rsp_id),
        .cpu_rsp_rdata   (cpu_rsp_rdata),
        .cpu_rsp_error   (cpu_rsp_error),
        .flush_valid     (flush_valid),
        .flush_ready     (flush_ready),
        .flush_done      (flush_done),
        .flush_error     (flush_error),
        .m_axi_awvalid   (axi_awvalid),
        .m_axi_awready   (axi_awready),
        .m_axi_awid      (axi_awid),
        .m_axi_awaddr    (axi_awaddr),
        .m_axi_awlen     (axi_awlen),
        .m_axi_awsize    (axi_awsize),
        .m_axi_awburst   (axi_awburst),
        .m_axi_wvalid    (axi_wvalid),
        .m_axi_wready    (axi_wready),
        .m_axi_wdata     (axi_wdata),
        .m_axi_wstrb     (axi_wstrb),
        .m_axi_wlast     (axi_wlast),
        .m_axi_bvalid    (axi_bvalid),
        .m_axi_bready    (axi_bready),
        .m_axi_bid       (axi_bid),
        .m_axi_bresp     (axi_bresp),
        .m_axi_arvalid   (axi_arvalid),
        .m_axi_arready   (axi_arready),
        .m_axi_arid      (axi_arid),
        .m_axi_araddr    (axi_araddr),
        .m_axi_arlen     (axi_arlen),
        .m_axi_arsize    (axi_arsize),
        .m_axi_arburst   (axi_arburst),
        .m_axi_rvalid    (axi_rvalid),
        .m_axi_rready    (axi_rready),
        .m_axi_rid       (axi_rid),
        .m_axi_rdata     (axi_rdata),
        .m_axi_rlast     (axi_rlast),
        .m_axi_rresp     (axi_rresp)
    );

    axi_memory_model memory_model (
        .clk               (clk),
        .reset_n           (reset_n),
        .force_read_error  (force_read_error),
        .force_write_error (force_write_error),
        .s_axi_awvalid     (axi_awvalid),
        .s_axi_awready     (axi_awready),
        .s_axi_awid        (axi_awid),
        .s_axi_awaddr      (axi_awaddr),
        .s_axi_awlen       (axi_awlen),
        .s_axi_awsize      (axi_awsize),
        .s_axi_awburst     (axi_awburst),
        .s_axi_wvalid      (axi_wvalid),
        .s_axi_wready      (axi_wready),
        .s_axi_wdata       (axi_wdata),
        .s_axi_wstrb       (axi_wstrb),
        .s_axi_wlast       (axi_wlast),
        .s_axi_bvalid      (axi_bvalid),
        .s_axi_bready      (axi_bready),
        .s_axi_bid         (axi_bid),
        .s_axi_bresp       (axi_bresp),
        .s_axi_arvalid     (axi_arvalid),
        .s_axi_arready     (axi_arready),
        .s_axi_arid        (axi_arid),
        .s_axi_araddr      (axi_araddr),
        .s_axi_arlen       (axi_arlen),
        .s_axi_arsize      (axi_arsize),
        .s_axi_arburst     (axi_arburst),
        .s_axi_rvalid      (axi_rvalid),
        .s_axi_rready      (axi_rready),
        .s_axi_rid         (axi_rid),
        .s_axi_rdata       (axi_rdata),
        .s_axi_rlast       (axi_rlast),
        .s_axi_rresp       (axi_rresp)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function automatic logic [7:0] expected_byte(
        input logic [ADDR_WIDTH-1:0] address
    );
        expected_byte = (address ^ (address >> 8)) & 8'hff;
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

    function automatic logic [DATA_WIDTH-1:0] memory_word(
        input logic [ADDR_WIDTH-1:0] address
    );
        memory_word = {
            memory_model.memory[address + 3],
            memory_model.memory[address + 2],
            memory_model.memory[address + 1],
            memory_model.memory[address]
        };
    endfunction

    task automatic clear_response(
        input logic [REQ_ID_WIDTH-1:0] request_id
    );
        begin
            response_seen[request_id]  = 1'b0;
            response_data[request_id]  = '0;
            response_error[request_id] = 1'b0;
        end
    endtask

    task automatic send_request(
        input logic [REQ_ID_WIDTH-1:0] request_id,
        input logic [ADDR_WIDTH-1:0]   address,
        input logic                    write_request,
        input logic [DATA_WIDTH-1:0]   write_data,
        input logic [WORD_BYTES-1:0]   write_strobe
    );
        begin
            clear_response(request_id);
            @(negedge clk);
            cpu_req_valid = 1'b1;
            cpu_req_id    = request_id;
            cpu_req_addr  = address;
            cpu_req_write = write_request;
            cpu_req_wdata = write_data;
            cpu_req_wstrb = write_strobe;

            do @(posedge clk); while (!cpu_req_ready);

            @(negedge clk);
            cpu_req_valid = 1'b0;
        end
    endtask

    task automatic check_response(
        input logic [REQ_ID_WIDTH-1:0] request_id,
        input logic [DATA_WIDTH-1:0]   expected_data,
        input logic                    expected_error,
        input logic                    check_data
    );
        begin
            while (!response_seen[request_id])
                @(posedge clk);

            if (response_error[request_id] !== expected_error) begin
                $fatal(1, "ID %0d error mismatch: got %0b expected %0b",
                       request_id, response_error[request_id], expected_error);
            end

            if (check_data && response_data[request_id] !== expected_data) begin
                $fatal(1, "ID %0d data mismatch: got %08h expected %08h",
                       request_id, response_data[request_id], expected_data);
            end
        end
    endtask

    task automatic request_flush;
        begin
            @(negedge clk);
            flush_valid = 1'b1;
            do @(posedge clk); while (!flush_ready);
            @(negedge clk);
            flush_valid = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (reset_n) begin
            if (cpu_rsp_valid && cpu_rsp_ready) begin
                if (response_seen[cpu_rsp_id])
                    $fatal(1, "Duplicate response for ID %0d", cpu_rsp_id);
                response_seen[cpu_rsp_id]  <= 1'b1;
                response_data[cpu_rsp_id]  <= cpu_rsp_rdata;
                response_error[cpu_rsp_id] <= cpu_rsp_error;
            end

            if (axi_arvalid && axi_arready)
                read_burst_count <= read_burst_count + 1;
            if (axi_awvalid && axi_awready)
                write_burst_count <= write_burst_count + 1;
        end
    end

    initial begin
        reset_n          = 1'b0;
        cpu_req_valid    = 1'b0;
        cpu_req_id       = '0;
        cpu_req_addr     = '0;
        cpu_req_write    = 1'b0;
        cpu_req_wdata    = '0;
        cpu_req_wstrb    = '0;
        cpu_rsp_ready    = 1'b1;
        flush_valid      = 1'b0;
        force_read_error = 1'b0;
        force_write_error = 1'b0;
        read_burst_count = 0;
        write_burst_count = 0;

        for (response_id_number = 0;
             response_id_number < ID_COUNT;
             response_id_number = response_id_number + 1) begin
            response_seen[response_id_number]  = 1'b0;
            response_data[response_id_number]  = '0;
            response_error[response_id_number] = 1'b0;
        end

        repeat (5) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;

        // 1. Basic miss followed by a same-line hit.
        send_request(4'h1, 32'h0000_1004, 1'b0, '0, '0);
        check_response(4'h1, expected_word(32'h0000_1004), 1'b0, 1'b1);
        reads_before = read_burst_count;
        send_request(4'h2, 32'h0000_1008, 1'b0, '0, '0);
        check_response(4'h2, expected_word(32'h0000_1008), 1'b0, 1'b1);
        if (read_burst_count != reads_before)
            $fatal(1, "Same-line hit unexpectedly accessed AXI");

        // 2. Four independent misses can be outstanding together.
        send_request(4'h3, 32'h0000_3000, 1'b0, '0, '0);
        send_request(4'h4, 32'h0000_3440, 1'b0, '0, '0);
        send_request(4'h5, 32'h0000_3880, 1'b0, '0, '0);
        send_request(4'h6, 32'h0000_3cc0, 1'b0, '0, '0);
        check_response(4'h3, expected_word(32'h0000_3000), 1'b0, 1'b1);
        check_response(4'h4, expected_word(32'h0000_3440), 1'b0, 1'b1);
        check_response(4'h5, expected_word(32'h0000_3880), 1'b0, 1'b1);
        check_response(4'h6, expected_word(32'h0000_3cc0), 1'b0, 1'b1);

        // 3. A read SLVERR becomes an error response for the original CPU ID.
        force_read_error = 1'b1;
        send_request(4'h7, 32'h0000_7000, 1'b0, '0, '0);
        do @(posedge clk); while (!(axi_arvalid && axi_arready));
        @(negedge clk);
        force_read_error = 1'b0;
        check_response(4'h7, '0, 1'b1, 1'b0);

        // The failed line was not installed, so a retry fetches it normally.
        send_request(4'h8, 32'h0000_7000, 1'b0, '0, '0);
        check_response(4'h8, expected_word(32'h0000_7000), 1'b0, 1'b1);

        // 4. Flush writes a dirty line to memory and invalidates the cache.
        send_request(4'h9, 32'h0000_1200, 1'b1, 32'hdead_beef, 4'hf);
        check_response(4'h9, '0, 1'b0, 1'b0);
        if (memory_word(32'h0000_1200) == 32'hdead_beef)
            $fatal(1, "Write-back store reached memory before flush");

        request_flush();
        while (!flush_done) @(posedge clk);
        if (flush_error)
            $fatal(1, "Successful flush reported an error");
        if (memory_word(32'h0000_1200) !== 32'hdead_beef)
            $fatal(1, "Flush did not write dirty data to memory");

        reads_before = read_burst_count;
        send_request(4'ha, 32'h0000_1200, 1'b0, '0, '0);
        check_response(4'ha, 32'hdead_beef, 1'b0, 1'b1);
        if (read_burst_count != reads_before + 1)
            $fatal(1, "Post-flush access should miss and refill");

        // 5. Failed flush writeback preserves the dirty cache line.
        send_request(4'hb, 32'h0000_2200, 1'b1, 32'hcafe_f00d, 4'hf);
        check_response(4'hb, '0, 1'b0, 1'b0);

        force_write_error = 1'b1;
        request_flush();
        do @(posedge clk); while (!(axi_awvalid && axi_awready));
        @(negedge clk);
        force_write_error = 1'b0;
        while (!flush_done) @(posedge clk);
        if (!flush_error)
            $fatal(1, "Failed AXI write should make flush_error high");

        reads_before = read_burst_count;
        send_request(4'hc, 32'h0000_2200, 1'b0, '0, '0);
        check_response(4'hc, 32'hcafe_f00d, 1'b0, 1'b1);
        if (read_burst_count != reads_before)
            $fatal(1, "Dirty line was lost after failed flush");

        // Retry succeeds and finally commits the preserved dirty data.
        request_flush();
        while (!flush_done) @(posedge clk);
        if (flush_error)
            $fatal(1, "Flush retry unexpectedly failed");
        if (memory_word(32'h0000_2200) !== 32'hcafe_f00d)
            $fatal(1, "Flush retry did not update memory");

        $display("ALL PHASE 7 DESIGN-CONTROL TESTS PASSED");
        repeat (5) @(posedge clk);
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "Simulation timeout");
    end

endmodule
