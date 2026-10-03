module l1d_cache
    import cache_pkg::*;
(
    input  logic                        clk,
    input  logic                        reset_n,

    // CPU/LSU request channel. IDs allow a younger hit to respond before an
    // older miss without making the two responses ambiguous.
    input  logic                        cpu_req_valid,
    output logic                        cpu_req_ready,
    input  logic [REQ_ID_WIDTH-1:0]     cpu_req_id,
    input  logic [ADDR_WIDTH-1:0]       cpu_req_addr,
    input  logic                        cpu_req_write,
    input  logic [DATA_WIDTH-1:0]       cpu_req_wdata,
    input  logic [WORD_BYTES-1:0]       cpu_req_wstrb,

    // CPU/LSU response channel. Store responses return zero data.
    output logic                        cpu_rsp_valid,
    input  logic                        cpu_rsp_ready,
    output logic [REQ_ID_WIDTH-1:0]     cpu_rsp_id,
    output logic [DATA_WIDTH-1:0]       cpu_rsp_rdata,

    // AXI4 write-address channel.
    output logic                        m_axi_awvalid,
    input  logic                        m_axi_awready,
    output logic [ADDR_WIDTH-1:0]       m_axi_awaddr,
    output logic [7:0]                  m_axi_awlen,
    output logic [2:0]                  m_axi_awsize,
    output logic [1:0]                  m_axi_awburst,

    // AXI4 write-data channel.
    output logic                        m_axi_wvalid,
    input  logic                        m_axi_wready,
    output logic [AXI_DATA_WIDTH-1:0]   m_axi_wdata,
    output logic [AXI_BYTES-1:0]        m_axi_wstrb,
    output logic                        m_axi_wlast,

    // AXI4 write-response channel.
    input  logic                        m_axi_bvalid,
    output logic                        m_axi_bready,
    input  logic [1:0]                  m_axi_bresp,

    // AXI4 read-address channel.
    output logic                        m_axi_arvalid,
    input  logic                        m_axi_arready,
    output logic [ADDR_WIDTH-1:0]       m_axi_araddr,
    output logic [7:0]                  m_axi_arlen,
    output logic [2:0]                  m_axi_arsize,
    output logic [1:0]                  m_axi_arburst,

    // AXI4 read-data channel.
    input  logic                        m_axi_rvalid,
    output logic                        m_axi_rready,
    input  logic [AXI_DATA_WIDTH-1:0]   m_axi_rdata,
    input  logic                        m_axi_rlast,
    input  logic [1:0]                  m_axi_rresp
);

    lookup_state_t lookup_state_q;
    lookup_state_t lookup_state_d;
    miss_state_t   miss_state_q;
    miss_state_t   miss_state_d;

    // 64 sets x 2 ways x 32 bytes = 4 KiB of cache data.
    logic  valid_array [0:NUM_SETS-1][0:NUM_WAYS-1];
    logic  dirty_array [0:NUM_SETS-1][0:NUM_WAYS-1];
    tag_t  tag_array   [0:NUM_SETS-1][0:NUM_WAYS-1];
    line_t data_array  [0:NUM_SETS-1][0:NUM_WAYS-1];

    // For a 2-way cache, this bit identifies the next LRU victim.
    logic lru_victim_array [0:NUM_SETS-1];

    // Lookup request and the registered outputs of both indexed ways.
    logic [REQ_ID_WIDTH-1:0] lookup_req_id_q;
    logic [ADDR_WIDTH-1:0]   lookup_req_addr_q;
    logic                    lookup_req_write_q;
    logic [DATA_WIDTH-1:0]   lookup_req_wdata_q;
    logic [WORD_BYTES-1:0]   lookup_req_wstrb_q;

    logic  lookup_valid_q [0:NUM_WAYS-1];
    logic  lookup_dirty_q [0:NUM_WAYS-1];
    tag_t  lookup_tag_q   [0:NUM_WAYS-1];
    line_t lookup_line_q  [0:NUM_WAYS-1];

    // One miss-status holding register (MSHR). It owns all information needed
    // to finish exactly one miss while the lookup path continues serving hits.
    logic                        mshr_valid_q;
    logic [REQ_ID_WIDTH-1:0]     mshr_req_id_q;
    logic                        mshr_write_q;
    logic [DATA_WIDTH-1:0]       mshr_wdata_q;
    logic [WORD_BYTES-1:0]       mshr_wstrb_q;
    logic [INDEX_BITS-1:0]       mshr_set_index_q;
    logic [WORD_INDEX_BITS-1:0]  mshr_word_index_q;
    tag_t                        mshr_tag_q;
    logic [ADDR_WIDTH-1:0]       mshr_line_addr_q;
    way_t                        mshr_victim_way_q;
    logic [ADDR_WIDTH-1:0]       mshr_victim_addr_q;
    line_t                       mshr_victim_line_q;
    line_t                       mshr_refill_line_q;
    axi_beat_t                   mshr_axi_beat_q;

    // A one-entry response register supplies stable ready/valid behavior.
    logic                        response_valid_q;
    logic [REQ_ID_WIDTH-1:0]     response_id_q;
    logic [DATA_WIDTH-1:0]       response_data_q;

    logic [INDEX_BITS-1:0]       cpu_set_index;
    logic [INDEX_BITS-1:0]       lookup_set_index;
    logic [OFFSET_BITS-1:0]      lookup_byte_offset;
    logic [WORD_INDEX_BITS-1:0]  lookup_word_index;
    tag_t                        lookup_req_tag;
    logic [ADDR_WIDTH-1:0]       lookup_line_addr;

    logic [NUM_WAYS-1:0]         way_hit;
    logic                        lookup_hit;
    way_t                        lookup_hit_way;
    way_t                        lookup_victim_way;
    logic                        lookup_victim_dirty;
    logic [DATA_WIDTH-1:0]       lookup_selected_word;

    line_t                       install_line;
    logic [DATA_WIDTH-1:0]       install_response_data;

    logic response_can_accept;
    logic lookup_blocked;
    logic lookup_hit_complete;
    logic miss_allocate;
    logic miss_install_complete;

    integer set_number;
    integer way_number;
    integer capture_way_number;
    integer store_byte_number;
    integer install_byte_number;

    assign cpu_set_index = cpu_req_addr[OFFSET_BITS + INDEX_BITS - 1
                                        : OFFSET_BITS];

    assign lookup_byte_offset = lookup_req_addr_q[OFFSET_BITS-1:0];
    assign lookup_set_index = lookup_req_addr_q
        [OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];
    assign lookup_req_tag = lookup_req_addr_q
        [ADDR_WIDTH-1 : OFFSET_BITS + INDEX_BITS];
    assign lookup_word_index = lookup_byte_offset
        [OFFSET_BITS-1 : $clog2(WORD_BYTES)];
    assign lookup_line_addr = {
        lookup_req_addr_q[ADDR_WIDTH-1:OFFSET_BITS],
        {OFFSET_BITS{1'b0}}
    };

    // Stage-1 tag comparison checks both ways in parallel.
    assign way_hit[0] = lookup_valid_q[0]
                        && (lookup_tag_q[0] == lookup_req_tag);
    assign way_hit[1] = lookup_valid_q[1]
                        && (lookup_tag_q[1] == lookup_req_tag);
    assign lookup_hit = |way_hit;

    always_comb begin
        lookup_hit_way = '0;

        if (way_hit[0])
            lookup_hit_way = way_t'(0);
        else if (way_hit[1])
            lookup_hit_way = way_t'(1);
    end

    // Prefer an invalid way. Use LRU only when both ways are valid.
    always_comb begin
        if (!lookup_valid_q[0])
            lookup_victim_way = way_t'(0);
        else if (!lookup_valid_q[1])
            lookup_victim_way = way_t'(1);
        else
            lookup_victim_way = lru_victim_array[lookup_set_index];
    end

    assign lookup_victim_dirty =
        lookup_valid_q[lookup_victim_way]
        && lookup_dirty_q[lookup_victim_way];

    assign lookup_selected_word = lookup_line_q[lookup_hit_way]
        [(lookup_word_index * DATA_WIDTH) +: DATA_WIDTH];

    // A store miss is merged directly into the completed refill line. This
    // avoids replaying the original store through the lookup pipe.
    always_comb begin
        install_line = mshr_refill_line_q;

        if (mshr_write_q) begin
            for (install_byte_number = 0;
                 install_byte_number < WORD_BYTES;
                 install_byte_number = install_byte_number + 1) begin
                if (mshr_wstrb_q[install_byte_number]) begin
                    install_line
                        [(mshr_word_index_q * DATA_WIDTH)
                         + (install_byte_number * 8) +: 8]
                        = mshr_wdata_q
                          [(install_byte_number * 8) +: 8];
                end
            end
        end
    end

    assign install_response_data = mshr_write_q
        ? '0
        : install_line
          [(mshr_word_index_q * DATA_WIDTH) +: DATA_WIDTH];

    assign cpu_rsp_valid = response_valid_q;
    assign cpu_rsp_id    = response_id_q;
    assign cpu_rsp_rdata = response_data_q;

    assign response_can_accept = !response_valid_q || cpu_rsp_ready;
    assign lookup_blocked = (miss_state_q == MISS_INSTALL);

    // The lookup slot remains usable throughout writeback/refill. It is only
    // paused for the cycle in which the miss engine writes the arrays.
    assign cpu_req_ready = (lookup_state_q == LOOKUP_IDLE)
                           && !lookup_blocked;

    assign lookup_hit_complete =
        (lookup_state_q == LOOKUP_COMPARE)
        && !lookup_blocked
        && lookup_hit
        && response_can_accept;

    assign miss_allocate =
        (lookup_state_q == LOOKUP_COMPARE)
        && !lookup_blocked
        && !lookup_hit
        && !mshr_valid_q
        && (miss_state_q == MISS_IDLE);

    assign miss_install_complete =
        (miss_state_q == MISS_INSTALL)
        && response_can_accept;

    // CPU lookup controller. A second miss waits here until the single MSHR
    // becomes free; it does not launch another AXI transaction in Phase 5.
    always_comb begin
        lookup_state_d = lookup_state_q;

        case (lookup_state_q)
            LOOKUP_IDLE: begin
                if (cpu_req_valid && cpu_req_ready)
                    lookup_state_d = LOOKUP_COMPARE;
            end

            LOOKUP_COMPARE: begin
                if (lookup_blocked) begin
                    // The array changed at install, so refresh the registered
                    // way data before comparing this request again.
                    lookup_state_d = LOOKUP_REFRESH;
                end
                else if (lookup_hit) begin
                    if (response_can_accept)
                        lookup_state_d = LOOKUP_IDLE;
                end
                else if (mshr_valid_q) begin
                    lookup_state_d = LOOKUP_WAIT_MSHR;
                end
                else if (miss_state_q == MISS_IDLE) begin
                    lookup_state_d = LOOKUP_IDLE;
                end
            end

            LOOKUP_WAIT_MSHR: begin
                if (!mshr_valid_q)
                    lookup_state_d = LOOKUP_REFRESH;
            end

            LOOKUP_REFRESH: begin
                if (!lookup_blocked)
                    lookup_state_d = LOOKUP_COMPARE;
            end

            default: begin
                lookup_state_d = LOOKUP_IDLE;
            end
        endcase
    end

    // Independent miss engine. Only this controller owns the AXI channels.
    always_comb begin
        miss_state_d = miss_state_q;

        case (miss_state_q)
            MISS_IDLE: begin
                if (miss_allocate) begin
                    if (lookup_victim_dirty)
                        miss_state_d = MISS_WRITEBACK_AW;
                    else
                        miss_state_d = MISS_REFILL_AR;
                end
            end

            MISS_WRITEBACK_AW: begin
                if (m_axi_awvalid && m_axi_awready)
                    miss_state_d = MISS_WRITEBACK_W;
            end

            MISS_WRITEBACK_W: begin
                if (m_axi_wvalid && m_axi_wready && m_axi_wlast)
                    miss_state_d = MISS_WRITEBACK_B;
            end

            MISS_WRITEBACK_B: begin
                if (m_axi_bvalid && m_axi_bready)
                    miss_state_d = MISS_REFILL_AR;
            end

            MISS_REFILL_AR: begin
                if (m_axi_arvalid && m_axi_arready)
                    miss_state_d = MISS_REFILL_R;
            end

            MISS_REFILL_R: begin
                if (m_axi_rvalid && m_axi_rready && m_axi_rlast)
                    miss_state_d = MISS_INSTALL;
            end

            MISS_INSTALL: begin
                if (miss_install_complete)
                    miss_state_d = MISS_IDLE;
            end

            default: begin
                miss_state_d = MISS_IDLE;
            end
        endcase
    end

    // AXI output logic. All payloads come from MSHR registers and therefore
    // remain stable whenever VALID is asserted and READY is low.
    always_comb begin
        m_axi_awvalid = 1'b0;
        m_axi_awaddr  = mshr_victim_addr_q;
        m_axi_awlen   = AXI_LINE_LEN;
        m_axi_awsize  = AXI_WORD_SIZE;
        m_axi_awburst = AXI_BURST_INCR;

        m_axi_wvalid = 1'b0;
        m_axi_wdata  = mshr_victim_line_q
            [(mshr_axi_beat_q * AXI_DATA_WIDTH) +: AXI_DATA_WIDTH];
        m_axi_wstrb  = {AXI_BYTES{1'b1}};
        m_axi_wlast  = (mshr_axi_beat_q == AXI_BEATS_PER_LINE - 1);

        m_axi_bready = 1'b0;

        m_axi_arvalid = 1'b0;
        m_axi_araddr  = mshr_line_addr_q;
        m_axi_arlen   = AXI_LINE_LEN;
        m_axi_arsize  = AXI_WORD_SIZE;
        m_axi_arburst = AXI_BURST_INCR;

        m_axi_rready = 1'b0;

        case (miss_state_q)
            MISS_WRITEBACK_AW: m_axi_awvalid = 1'b1;
            MISS_WRITEBACK_W:  m_axi_wvalid  = 1'b1;
            MISS_WRITEBACK_B:  m_axi_bready  = 1'b1;
            MISS_REFILL_AR:     m_axi_arvalid = 1'b1;
            MISS_REFILL_R:      m_axi_rready  = 1'b1;
            default: begin
                // MISS_IDLE and MISS_INSTALL perform no AXI transfer.
            end
        endcase
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            lookup_state_q       <= LOOKUP_IDLE;
            miss_state_q         <= MISS_IDLE;

            lookup_req_id_q      <= '0;
            lookup_req_addr_q    <= '0;
            lookup_req_write_q   <= 1'b0;
            lookup_req_wdata_q   <= '0;
            lookup_req_wstrb_q   <= '0;

            mshr_valid_q         <= 1'b0;
            mshr_req_id_q        <= '0;
            mshr_write_q         <= 1'b0;
            mshr_wdata_q         <= '0;
            mshr_wstrb_q         <= '0;
            mshr_set_index_q     <= '0;
            mshr_word_index_q    <= '0;
            mshr_tag_q           <= '0;
            mshr_line_addr_q     <= '0;
            mshr_victim_way_q    <= '0;
            mshr_victim_addr_q   <= '0;
            mshr_victim_line_q   <= '0;
            mshr_refill_line_q   <= '0;
            mshr_axi_beat_q      <= '0;

            response_valid_q     <= 1'b0;
            response_id_q        <= '0;
            response_data_q      <= '0;

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
            lookup_state_q <= lookup_state_d;
            miss_state_q   <= miss_state_d;

            // Remove an accepted response. A new response generated in the
            // same cycle overrides this assignment and keeps VALID asserted.
            if (response_valid_q && cpu_rsp_ready)
                response_valid_q <= 1'b0;

            // Lookup Stage 0: accept a request and register both indexed ways.
            if (lookup_state_q == LOOKUP_IDLE
                && cpu_req_valid && cpu_req_ready) begin
                lookup_req_id_q    <= cpu_req_id;
                lookup_req_addr_q  <= cpu_req_addr;
                lookup_req_write_q <= cpu_req_write;
                lookup_req_wdata_q <= cpu_req_wdata;
                lookup_req_wstrb_q <= cpu_req_wstrb;

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

            // A request held behind the MSHR must re-read the arrays after the
            // refill installs, because its original snapshot may be stale.
            if (lookup_state_q == LOOKUP_REFRESH && !lookup_blocked) begin
                for (capture_way_number = 0;
                     capture_way_number < NUM_WAYS;
                     capture_way_number = capture_way_number + 1) begin
                    lookup_valid_q[capture_way_number]
                        <= valid_array[lookup_set_index][capture_way_number];
                    lookup_dirty_q[capture_way_number]
                        <= dirty_array[lookup_set_index][capture_way_number];
                    lookup_tag_q[capture_way_number]
                        <= tag_array[lookup_set_index][capture_way_number];
                    lookup_line_q[capture_way_number]
                        <= data_array[lookup_set_index][capture_way_number];
                end
            end

            // Complete an ordinary cache hit independently of the miss engine.
            if (lookup_hit_complete) begin
                response_valid_q <= 1'b1;
                response_id_q    <= lookup_req_id_q;

                if (lookup_req_write_q) begin
                    for (store_byte_number = 0;
                         store_byte_number < WORD_BYTES;
                         store_byte_number = store_byte_number + 1) begin
                        if (lookup_req_wstrb_q[store_byte_number]) begin
                            data_array[lookup_set_index][lookup_hit_way]
                                [(lookup_word_index * DATA_WIDTH)
                                 + (store_byte_number * 8) +: 8]
                                <= lookup_req_wdata_q
                                   [(store_byte_number * 8) +: 8];
                        end
                    end

                    if (|lookup_req_wstrb_q)
                        dirty_array[lookup_set_index][lookup_hit_way]
                            <= 1'b1;

                    response_data_q <= '0;
                end
                else begin
                    response_data_q <= lookup_selected_word;
                end

                lru_victim_array[lookup_set_index] <= ~lookup_hit_way;
            end

            // Allocate the single MSHR and reserve its victim. Invalidating the
            // victim immediately prevents a later lookup from hitting stale
            // data or modifying the snapshotted writeback line.
            if (miss_allocate) begin
                mshr_valid_q       <= 1'b1;
                mshr_req_id_q      <= lookup_req_id_q;
                mshr_write_q       <= lookup_req_write_q;
                mshr_wdata_q       <= lookup_req_wdata_q;
                mshr_wstrb_q       <= lookup_req_wstrb_q;
                mshr_set_index_q   <= lookup_set_index;
                mshr_word_index_q  <= lookup_word_index;
                mshr_tag_q         <= lookup_req_tag;
                mshr_line_addr_q   <= lookup_line_addr;
                mshr_victim_way_q  <= lookup_victim_way;
                mshr_victim_line_q <= lookup_line_q[lookup_victim_way];
                mshr_victim_addr_q <= {
                    lookup_tag_q[lookup_victim_way],
                    lookup_set_index,
                    {OFFSET_BITS{1'b0}}
                };
                mshr_refill_line_q <= '0;
                mshr_axi_beat_q    <= '0;

                valid_array[lookup_set_index][lookup_victim_way] <= 1'b0;
                dirty_array[lookup_set_index][lookup_victim_way] <= 1'b0;
            end

            // AXI writeback beat tracking.
            if (miss_state_q == MISS_WRITEBACK_AW
                && m_axi_awvalid && m_axi_awready) begin
                mshr_axi_beat_q <= '0;
            end
            else if (miss_state_q == MISS_WRITEBACK_W
                     && m_axi_wvalid && m_axi_wready) begin
                if (m_axi_wlast)
                    mshr_axi_beat_q <= '0;
                else
                    mshr_axi_beat_q <= mshr_axi_beat_q + 1'b1;
            end

            // AXI refill assembly.
            if (miss_state_q == MISS_REFILL_AR
                && m_axi_arvalid && m_axi_arready) begin
                mshr_axi_beat_q    <= '0;
                mshr_refill_line_q <= '0;
            end
            else if (miss_state_q == MISS_REFILL_R
                     && m_axi_rvalid && m_axi_rready) begin
                mshr_refill_line_q
                    [(mshr_axi_beat_q * AXI_DATA_WIDTH)
                     +: AXI_DATA_WIDTH]
                    <= m_axi_rdata;

                if (m_axi_rlast)
                    mshr_axi_beat_q <= '0;
                else
                    mshr_axi_beat_q <= mshr_axi_beat_q + 1'b1;
            end

            // Install the refill, merge a store miss if required, and create
            // the original miss response. The MSHR is now free.
            if (miss_install_complete) begin
                data_array[mshr_set_index_q][mshr_victim_way_q]
                    <= install_line;
                tag_array[mshr_set_index_q][mshr_victim_way_q]
                    <= mshr_tag_q;
                valid_array[mshr_set_index_q][mshr_victim_way_q]
                    <= 1'b1;
                dirty_array[mshr_set_index_q][mshr_victim_way_q]
                    <= mshr_write_q && (|mshr_wstrb_q);
                lru_victim_array[mshr_set_index_q]
                    <= ~mshr_victim_way_q;

                response_valid_q <= 1'b1;
                response_id_q    <= mshr_req_id_q;
                response_data_q  <= install_response_data;
                mshr_valid_q     <= 1'b0;
            end

`ifndef SYNTHESIS
            if (miss_state_q == MISS_WRITEBACK_B
                && m_axi_bvalid && m_axi_bready
                && m_axi_bresp != AXI_RESP_OKAY) begin
                $fatal(1, "AXI write response error: BRESP=%02b",
                       m_axi_bresp);
            end

            if (miss_state_q == MISS_REFILL_R
                && m_axi_rvalid && m_axi_rready
                && m_axi_rresp != AXI_RESP_OKAY) begin
                $fatal(1, "AXI read response error: RRESP=%02b",
                       m_axi_rresp);
            end

            if (miss_state_q == MISS_REFILL_R
                && m_axi_rvalid && m_axi_rready) begin
                if (m_axi_rlast
                    != (mshr_axi_beat_q == AXI_BEATS_PER_LINE - 1)) begin
                    $fatal(1,
                        "AXI RLAST arrived on incorrect refill beat %0d",
                        mshr_axi_beat_q);
                end
            end

            if (way_hit == {NUM_WAYS{1'b1}}) begin
                $fatal(1, "Both ways hit the same lookup request");
            end
`endif
        end
    end

endmodule
