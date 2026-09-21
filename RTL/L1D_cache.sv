module l1d_cache
    import cache_pkg::*;
(
    input  logic                      clk,
    input  logic                      reset_n,

    // CPU/LSU request channel.
    input  logic                      cpu_req_valid,
    output logic                      cpu_req_ready,
    input  logic [ADDR_WIDTH-1:0]     cpu_req_addr,
    input  logic                      cpu_req_write,
    input  logic [DATA_WIDTH-1:0]     cpu_req_wdata,
    input  logic [WORD_BYTES-1:0]     cpu_req_wstrb,

    // CPU/LSU response channel. Store responses return zero data.
    output logic                      cpu_rsp_valid,
    input  logic                      cpu_rsp_ready,
    output logic [DATA_WIDTH-1:0]     cpu_rsp_rdata,

    // AXI4 write-address channel.
    output logic                      m_axi_awvalid,
    input  logic                      m_axi_awready,
    output logic [ADDR_WIDTH-1:0]     m_axi_awaddr,
    output logic [7:0]                m_axi_awlen,
    output logic [2:0]                m_axi_awsize,
    output logic [1:0]                m_axi_awburst,

    // AXI4 write-data channel.
    output logic                      m_axi_wvalid,
    input  logic                      m_axi_wready,
    output logic [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output logic [AXI_BYTES-1:0]      m_axi_wstrb,
    output logic                      m_axi_wlast,

    // AXI4 write-response channel.
    input  logic                      m_axi_bvalid,
    output logic                      m_axi_bready,
    input  logic [1:0]                m_axi_bresp,

    // AXI4 read-address channel.
    output logic                      m_axi_arvalid,
    input  logic                      m_axi_arready,
    output logic [ADDR_WIDTH-1:0]     m_axi_araddr,
    output logic [7:0]                m_axi_arlen,
    output logic [2:0]                m_axi_arsize,
    output logic [1:0]                m_axi_arburst,

    // AXI4 read-data channel.
    input  logic                      m_axi_rvalid,
    output logic                      m_axi_rready,
    input  logic [AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input  logic                      m_axi_rlast,
    input  logic [1:0]                m_axi_rresp
);

    cache_state_t state_q;
    cache_state_t state_d;

    // 64 sets x 2 ways x 32 bytes = 4 KiB of cache data.
    logic  valid_array [0:NUM_SETS-1][0:NUM_WAYS-1];
    logic  dirty_array [0:NUM_SETS-1][0:NUM_WAYS-1];
    tag_t  tag_array   [0:NUM_SETS-1][0:NUM_WAYS-1];
    line_t data_array  [0:NUM_SETS-1][0:NUM_WAYS-1];

    // For a 2-way cache, one bit identifies the next LRU victim.
    logic lru_victim_array [0:NUM_SETS-1];

    // Saved CPU request. The cache is still blocking in Phase 4.
    logic [ADDR_WIDTH-1:0] request_addr_q;
    logic                  request_write_q;
    logic [DATA_WIDTH-1:0] request_wdata_q;
    logic [WORD_BYTES-1:0] request_wstrb_q;

    // Stage-1 lookup registers. Stage 0 reads both ways; Stage 1 compares the
    // registered tags and performs the hit/miss decision.
    logic  lookup_valid_q [0:NUM_WAYS-1];
    logic  lookup_dirty_q [0:NUM_WAYS-1];
    tag_t  lookup_tag_q   [0:NUM_WAYS-1];
    line_t lookup_line_q  [0:NUM_WAYS-1];

    // Miss information remains stable throughout writeback and refill.
    way_t                  victim_way_q;
    logic [ADDR_WIDTH-1:0] victim_addr_q;
    line_t                 victim_line_q;
    line_t                 refill_line_q;
    axi_beat_t             axi_beat_q;

    logic [DATA_WIDTH-1:0] response_data_q;

    logic [INDEX_BITS-1:0]      cpu_set_index;
    logic [INDEX_BITS-1:0]      request_set_index;
    logic [OFFSET_BITS-1:0]     request_byte_offset;
    logic [WORD_INDEX_BITS-1:0] request_word_index;
    tag_t                       request_tag;
    logic [ADDR_WIDTH-1:0]      request_line_addr;

    logic [NUM_WAYS-1:0] way_hit;
    logic                hit;
    way_t                hit_way;
    way_t                victim_way;
    logic                victim_is_dirty;
    logic [DATA_WIDTH-1:0] selected_word;

    integer set_number;
    integer way_number;
    integer capture_way_number;
    integer store_byte_number;

    assign cpu_set_index = cpu_req_addr[OFFSET_BITS + INDEX_BITS - 1
                                        : OFFSET_BITS];

    assign request_byte_offset = request_addr_q[OFFSET_BITS-1:0];
    assign request_set_index = request_addr_q[OFFSET_BITS + INDEX_BITS - 1
                                              : OFFSET_BITS];
    assign request_tag = request_addr_q[ADDR_WIDTH-1
                                        : OFFSET_BITS + INDEX_BITS];
    assign request_word_index =
        request_byte_offset[OFFSET_BITS-1:$clog2(WORD_BYTES)];
    assign request_line_addr = {
        request_addr_q[ADDR_WIDTH-1:OFFSET_BITS],
        {OFFSET_BITS{1'b0}}
    };

    // Stage-1 tag comparison checks both ways in parallel.
    assign way_hit[0] = lookup_valid_q[0]
                        && (lookup_tag_q[0] == request_tag);
    assign way_hit[1] = lookup_valid_q[1]
                        && (lookup_tag_q[1] == request_tag);
    assign hit = |way_hit;

    always_comb begin
        hit_way = '0;

        if (way_hit[0])
            hit_way = 1'b0;
        else if (way_hit[1])
            hit_way = 1'b1;
    end

    // Prefer an invalid way. Use LRU only when both ways are valid.
    always_comb begin
        if (!lookup_valid_q[0])
            victim_way = 1'b0;
        else if (!lookup_valid_q[1])
            victim_way = 1'b1;
        else
            victim_way = lru_victim_array[request_set_index];
    end

    assign victim_is_dirty = lookup_valid_q[victim_way]
                             && lookup_dirty_q[victim_way];

    assign selected_word = lookup_line_q[hit_way]
                           [(request_word_index * DATA_WIDTH) +: DATA_WIDTH];

    // CPU and AXI output logic. AXI payloads remain stable whenever VALID is
    // asserted because all payload information is held in registers.
    always_comb begin
        cpu_req_ready = 1'b0;
        cpu_rsp_valid = 1'b0;
        cpu_rsp_rdata = response_data_q;

        m_axi_awvalid = 1'b0;
        m_axi_awaddr  = victim_addr_q;
        m_axi_awlen   = AXI_LINE_LEN;
        m_axi_awsize  = AXI_WORD_SIZE;
        m_axi_awburst = AXI_BURST_INCR;

        m_axi_wvalid = 1'b0;
        m_axi_wdata  = victim_line_q
                       [(axi_beat_q * AXI_DATA_WIDTH) +: AXI_DATA_WIDTH];
        m_axi_wstrb  = {AXI_BYTES{1'b1}};
        m_axi_wlast  = (axi_beat_q == AXI_BEATS_PER_LINE - 1);

        m_axi_bready = 1'b0;

        m_axi_arvalid = 1'b0;
        m_axi_araddr  = request_line_addr;
        m_axi_arlen   = AXI_LINE_LEN;
        m_axi_arsize  = AXI_WORD_SIZE;
        m_axi_arburst = AXI_BURST_INCR;

        m_axi_rready = 1'b0;

        case (state_q)
            IDLE: begin
                cpu_req_ready = 1'b1;
            end

            WRITEBACK_AW: begin
                m_axi_awvalid = 1'b1;
            end

            WRITEBACK_W: begin
                m_axi_wvalid = 1'b1;
            end

            WRITEBACK_B: begin
                m_axi_bready = 1'b1;
            end

            REFILL_AR: begin
                m_axi_arvalid = 1'b1;
            end

            REFILL_R: begin
                m_axi_rready = 1'b1;
            end

            RESPONSE: begin
                cpu_rsp_valid = 1'b1;
            end

            default: begin
                // LOOKUP, INSTALL and REPLAY_READ are internal operations.
            end
        endcase
    end

    always_comb begin
        state_d = state_q;

        case (state_q)
            IDLE: begin
                if (cpu_req_valid && cpu_req_ready)
                    state_d = LOOKUP;
            end

            LOOKUP: begin
                if (hit)
                    state_d = RESPONSE;
                else if (victim_is_dirty)
                    state_d = WRITEBACK_AW;
                else
                    state_d = REFILL_AR;
            end

            WRITEBACK_AW: begin
                if (m_axi_awvalid && m_axi_awready)
                    state_d = WRITEBACK_W;
            end

            WRITEBACK_W: begin
                if (m_axi_wvalid && m_axi_wready && m_axi_wlast)
                    state_d = WRITEBACK_B;
            end

            WRITEBACK_B: begin
                if (m_axi_bvalid && m_axi_bready)
                    state_d = REFILL_AR;
            end

            REFILL_AR: begin
                if (m_axi_arvalid && m_axi_arready)
                    state_d = REFILL_R;
            end

            REFILL_R: begin
                if (m_axi_rvalid && m_axi_rready && m_axi_rlast)
                    state_d = INSTALL;
            end

            INSTALL: begin
                state_d = REPLAY_READ;
            end

            REPLAY_READ: begin
                state_d = LOOKUP;
            end

            RESPONSE: begin
                if (cpu_rsp_valid && cpu_rsp_ready)
                    state_d = IDLE;
            end

            default: begin
                state_d = IDLE;
            end
        endcase
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q         <= IDLE;
            request_addr_q  <= '0;
            request_write_q <= 1'b0;
            request_wdata_q <= '0;
            request_wstrb_q <= '0;

            victim_way_q    <= '0;
            victim_addr_q   <= '0;
            victim_line_q   <= '0;
            refill_line_q   <= '0;
            axi_beat_q      <= '0;
            response_data_q <= '0;

            for (capture_way_number = 0;
                 capture_way_number < NUM_WAYS;
                 capture_way_number = capture_way_number + 1) begin
                lookup_valid_q[capture_way_number] <= 1'b0;
                lookup_dirty_q[capture_way_number] <= 1'b0;
                lookup_tag_q[capture_way_number]   <= '0;
                lookup_line_q[capture_way_number]  <= '0;
            end

            for (set_number = 0;
                 set_number < NUM_SETS;
                 set_number = set_number + 1) begin
                lru_victim_array[set_number] <= 1'b0;

                for (way_number = 0;
                     way_number < NUM_WAYS;
                     way_number = way_number + 1) begin
                    valid_array[set_number][way_number] <= 1'b0;
                    dirty_array[set_number][way_number] <= 1'b0;
                    tag_array[set_number][way_number]   <= '0;
                    data_array[set_number][way_number]  <= '0;
                end
            end
        end
        else begin
            state_q <= state_d;

            // Pipeline Stage 0: capture the request and registered outputs of
            // both indexed ways. Stage 1 performs comparison in LOOKUP.
            if (state_q == IDLE && cpu_req_valid && cpu_req_ready) begin
                request_addr_q  <= cpu_req_addr;
                request_write_q <= cpu_req_write;
                request_wdata_q <= cpu_req_wdata;
                request_wstrb_q <= cpu_req_wstrb;

                for (capture_way_number = 0;
                     capture_way_number < NUM_WAYS;
                     capture_way_number = capture_way_number + 1) begin
                    lookup_valid_q[capture_way_number]
                        <= valid_array[cpu_set_index][capture_way_number];
                    lookup_dirty_q[capture_way_number]
                        <= dirty_array[cpu_set_index][capture_way_number];
                    lookup_tag_q[capture_way_number]
                        <= tag_array[cpu_set_index][capture_way_number];
                    lookup_line_q[capture_way_number]
                        <= data_array[cpu_set_index][capture_way_number];
                end
            end

            // Capture the chosen victim before starting AXI activity.
            if (state_q == LOOKUP && !hit) begin
                victim_way_q  <= victim_way;
                victim_line_q <= lookup_line_q[victim_way];
                victim_addr_q <= {
                    lookup_tag_q[victim_way],
                    request_set_index,
                    {OFFSET_BITS{1'b0}}
                };
            end

            // Begin each AXI burst at beat zero.
            if (state_q == WRITEBACK_AW
                && m_axi_awvalid && m_axi_awready) begin
                axi_beat_q <= '0;
            end
            else if (state_q == WRITEBACK_W
                     && m_axi_wvalid && m_axi_wready) begin
                if (m_axi_wlast)
                    axi_beat_q <= '0;
                else
                    axi_beat_q <= axi_beat_q + 1'b1;
            end

            if (state_q == REFILL_AR
                && m_axi_arvalid && m_axi_arready) begin
                axi_beat_q    <= '0;
                refill_line_q <= '0;
            end
            else if (state_q == REFILL_R
                     && m_axi_rvalid && m_axi_rready) begin
                refill_line_q
                    [(axi_beat_q * AXI_DATA_WIDTH) +: AXI_DATA_WIDTH]
                    <= m_axi_rdata;

                if (m_axi_rlast)
                    axi_beat_q <= '0;
                else
                    axi_beat_q <= axi_beat_q + 1'b1;
            end

            // Install the complete refill as a clean, valid cache line.
            if (state_q == INSTALL) begin
                data_array[request_set_index][victim_way_q]
                    <= refill_line_q;
                tag_array[request_set_index][victim_way_q]
                    <= request_tag;
                valid_array[request_set_index][victim_way_q]
                    <= 1'b1;
                dirty_array[request_set_index][victim_way_q]
                    <= 1'b0;
                lru_victim_array[request_set_index]
                    <= ~victim_way_q;
            end

            // Read the newly installed arrays into the lookup pipeline before
            // replaying the original load or store.
            if (state_q == REPLAY_READ) begin
                for (capture_way_number = 0;
                     capture_way_number < NUM_WAYS;
                     capture_way_number = capture_way_number + 1) begin
                    lookup_valid_q[capture_way_number]
                        <= valid_array[request_set_index][capture_way_number];
                    lookup_dirty_q[capture_way_number]
                        <= dirty_array[request_set_index][capture_way_number];
                    lookup_tag_q[capture_way_number]
                        <= tag_array[request_set_index][capture_way_number];
                    lookup_line_q[capture_way_number]
                        <= data_array[request_set_index][capture_way_number];
                end
            end

            // Stage-1 hit processing.
            if (state_q == LOOKUP && hit) begin
                if (request_write_q) begin
                    for (store_byte_number = 0;
                         store_byte_number < WORD_BYTES;
                         store_byte_number = store_byte_number + 1) begin
                        if (request_wstrb_q[store_byte_number]) begin
                            data_array[request_set_index][hit_way]
                                [(request_word_index * DATA_WIDTH)
                                 + (store_byte_number * 8) +: 8]
                                <= request_wdata_q
                                   [(store_byte_number * 8) +: 8];
                        end
                    end

                    if (|request_wstrb_q)
                        dirty_array[request_set_index][hit_way] <= 1'b1;

                    response_data_q <= '0;
                end
                else begin
                    response_data_q <= selected_word;
                end

                lru_victim_array[request_set_index] <= ~hit_way;
            end

`ifndef SYNTHESIS
            if (state_q == WRITEBACK_B
                && m_axi_bvalid && m_axi_bready
                && m_axi_bresp != AXI_RESP_OKAY) begin
                $fatal(1, "AXI write response error: BRESP=%02b",
                       m_axi_bresp);
            end

            if (state_q == REFILL_R
                && m_axi_rvalid && m_axi_rready
                && m_axi_rresp != AXI_RESP_OKAY) begin
                $fatal(1, "AXI read response error: RRESP=%02b",
                       m_axi_rresp);
            end

            if (state_q == REFILL_R
                && m_axi_rvalid && m_axi_rready) begin
                if (m_axi_rlast
                    != (axi_beat_q == AXI_BEATS_PER_LINE - 1)) begin
                    $fatal(1,
                        "AXI RLAST arrived on incorrect refill beat %0d",
                        axi_beat_q);
                end
            end
`endif
        end
    end

endmodule
