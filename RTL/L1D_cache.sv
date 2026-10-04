module l1d_cache
    import cache_pkg::*;
(
    input  logic                      clk,
    input  logic                      reset_n,

    // CPU/LSU request channel.
    input  logic                      cpu_req_valid,
    output logic                      cpu_req_ready,
    input  logic [REQ_ID_WIDTH-1:0]   cpu_req_id,
    input  logic [ADDR_WIDTH-1:0]     cpu_req_addr,
    input  logic                      cpu_req_write,
    input  logic [DATA_WIDTH-1:0]     cpu_req_wdata,
    input  logic [WORD_BYTES-1:0]     cpu_req_wstrb,

    // CPU/LSU response channel. Responses may return out of request order.
    output logic                      cpu_rsp_valid,
    input  logic                      cpu_rsp_ready,
    output logic [REQ_ID_WIDTH-1:0]   cpu_rsp_id,
    output logic [DATA_WIDTH-1:0]     cpu_rsp_rdata,

    // AXI4 write-address channel.
    output logic                      m_axi_awvalid,
    input  logic                      m_axi_awready,
    output logic [AXI_ID_WIDTH-1:0]   m_axi_awid,
    output logic [ADDR_WIDTH-1:0]     m_axi_awaddr,
    output logic [7:0]                m_axi_awlen,
    output logic [2:0]                m_axi_awsize,
    output logic [1:0]                m_axi_awburst,

    // AXI4 write-data channel. AXI4 has no WID, so writebacks are serialized.
    output logic                      m_axi_wvalid,
    input  logic                      m_axi_wready,
    output logic [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output logic [AXI_BYTES-1:0]      m_axi_wstrb,
    output logic                      m_axi_wlast,

    // AXI4 write-response channel.
    input  logic                      m_axi_bvalid,
    output logic                      m_axi_bready,
    input  logic [AXI_ID_WIDTH-1:0]   m_axi_bid,
    input  logic [1:0]                m_axi_bresp,

    // AXI4 read-address channel.
    output logic                      m_axi_arvalid,
    input  logic                      m_axi_arready,
    output logic [AXI_ID_WIDTH-1:0]   m_axi_arid,
    output logic [ADDR_WIDTH-1:0]     m_axi_araddr,
    output logic [7:0]                m_axi_arlen,
    output logic [2:0]                m_axi_arsize,
    output logic [1:0]                m_axi_arburst,

    // AXI4 read-data channel. RID routes each beat to its owning MSHR.
    input  logic                      m_axi_rvalid,
    output logic                      m_axi_rready,
    input  logic [AXI_ID_WIDTH-1:0]   m_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input  logic                      m_axi_rlast,
    input  logic [1:0]                m_axi_rresp
);

    // ---------------------------------------------------------------------
    // Cache arrays
    // ---------------------------------------------------------------------

    logic  valid_array    [0:NUM_SETS-1][0:NUM_WAYS-1];
    logic  dirty_array    [0:NUM_SETS-1][0:NUM_WAYS-1];
    logic  reserved_array [0:NUM_SETS-1][0:NUM_WAYS-1];
    tag_t  tag_array      [0:NUM_SETS-1][0:NUM_WAYS-1];
    line_t data_array     [0:NUM_SETS-1][0:NUM_WAYS-1];
    logic  lru_victim_array [0:NUM_SETS-1];

    // ---------------------------------------------------------------------
    // Lookup pipeline
    // ---------------------------------------------------------------------

    lookup_state_t lookup_state_q;
    lookup_state_t lookup_state_d;

    logic [REQ_ID_WIDTH-1:0] lookup_req_id_q;
    logic [ADDR_WIDTH-1:0]   lookup_req_addr_q;
    logic                    lookup_req_write_q;
    logic [DATA_WIDTH-1:0]   lookup_req_wdata_q;
    logic [WORD_BYTES-1:0]   lookup_req_wstrb_q;

    logic  lookup_valid_q    [0:NUM_WAYS-1];
    logic  lookup_dirty_q    [0:NUM_WAYS-1];
    logic  lookup_reserved_q [0:NUM_WAYS-1];
    tag_t  lookup_tag_q      [0:NUM_WAYS-1];
    line_t lookup_line_q     [0:NUM_WAYS-1];

    logic [INDEX_BITS-1:0]      cpu_set_index;
    logic [INDEX_BITS-1:0]      lookup_set_index;
    logic [OFFSET_BITS-1:0]     lookup_byte_offset;
    word_index_t                lookup_word_index;
    tag_t                       lookup_req_tag;
    logic [ADDR_WIDTH-1:0]      lookup_line_addr;

    logic [NUM_WAYS-1:0]        way_hit;
    logic                       lookup_hit;
    way_t                       lookup_hit_way;
    logic [DATA_WIDTH-1:0]      lookup_selected_word;

    logic                       lookup_victim_available;
    way_t                       lookup_victim_way;
    logic                       lookup_victim_dirty;

    // ---------------------------------------------------------------------
    // Multi-entry MSHR table
    // ---------------------------------------------------------------------

    logic                        mshr_valid_q [0:NUM_MSHRS-1];
    mshr_state_t                 mshr_state_q [0:NUM_MSHRS-1];
    logic [ADDR_WIDTH-1:0]       mshr_line_addr_q [0:NUM_MSHRS-1];
    logic [INDEX_BITS-1:0]       mshr_set_index_q [0:NUM_MSHRS-1];
    tag_t                        mshr_tag_q [0:NUM_MSHRS-1];
    way_t                        mshr_victim_way_q [0:NUM_MSHRS-1];
    logic                        mshr_victim_valid_q [0:NUM_MSHRS-1];
    logic [ADDR_WIDTH-1:0]       mshr_victim_addr_q [0:NUM_MSHRS-1];
    line_t                       mshr_victim_line_q [0:NUM_MSHRS-1];
    line_t                       mshr_refill_line_q [0:NUM_MSHRS-1];
    line_t                       mshr_work_line_q [0:NUM_MSHRS-1];
    logic                        mshr_line_dirty_q [0:NUM_MSHRS-1];
    axi_beat_t                   mshr_refill_beat_q [0:NUM_MSHRS-1];

    logic [MERGE_COUNT_WIDTH-1:0] mshr_req_count_q [0:NUM_MSHRS-1];
    logic [MERGE_INDEX_WIDTH-1:0] mshr_process_index_q [0:NUM_MSHRS-1];

    logic [REQ_ID_WIDTH-1:0]     mshr_req_id_q
        [0:NUM_MSHRS-1][0:MERGE_DEPTH-1];
    logic                        mshr_req_write_q
        [0:NUM_MSHRS-1][0:MERGE_DEPTH-1];
    word_index_t                 mshr_req_word_index_q
        [0:NUM_MSHRS-1][0:MERGE_DEPTH-1];
    logic [DATA_WIDTH-1:0]       mshr_req_wdata_q
        [0:NUM_MSHRS-1][0:MERGE_DEPTH-1];
    logic [WORD_BYTES-1:0]       mshr_req_wstrb_q
        [0:NUM_MSHRS-1][0:MERGE_DEPTH-1];

    logic                        mshr_match_valid;
    mshr_index_t                 mshr_match_index;
    logic                        victim_conflict_valid;
    logic                        free_mshr_valid;
    mshr_index_t                 free_mshr_index;

    logic                        merge_fire;
    logic                        allocate_fire;

    // ---------------------------------------------------------------------
    // Writeback, refill-address, apply, and install arbiters
    // ---------------------------------------------------------------------

    writeback_state_t            writeback_state_q;
    mshr_index_t                 writeback_index_q;
    axi_beat_t                   writeback_beat_q;
    logic                        writeback_select_valid;
    mshr_index_t                 writeback_select_index;

    logic                        ar_hold_valid_q;
    mshr_index_t                 ar_hold_index_q;
    logic                        ar_select_valid;
    mshr_index_t                 ar_select_index;

    logic                        install_select_valid;
    mshr_index_t                 install_select_index;
    logic                        install_fire;

    logic                        apply_select_valid;
    mshr_index_t                 apply_select_index;
    logic                        apply_fire;

    // ---------------------------------------------------------------------
    // Response FIFO and response-source arbitration
    // ---------------------------------------------------------------------

    logic                        response_push_valid;
    logic                        response_push_ready;
    logic [REQ_ID_WIDTH-1:0]     response_push_id;
    logic [DATA_WIDTH-1:0]       response_push_data;
    logic                        lookup_hit_complete;

    // Loop variables are deliberately unique to their processes. This avoids
    // ModelSim multiple-driver warnings on procedural integer variables.
    integer set_number;
    integer way_number;
    integer capture_way_number;
    integer request_slot_number;
    integer store_byte_number;
    integer apply_byte_number;
    integer match_scan_number;
    integer victim_conflict_scan_number;
    integer free_scan_number;
    integer writeback_scan_number;
    integer ar_scan_number;
    integer install_scan_number;
    integer apply_scan_number;
    integer prepare_scan_number;
    integer assertion_outer_number;
    integer assertion_inner_number;

    function automatic logic state_accepts_merge(
        input mshr_state_t state_value
    );
        begin
            case (state_value)
                MSHR_WRITEBACK_PENDING,
                MSHR_WRITEBACK_ACTIVE,
                MSHR_REFILL_REQUEST,
                MSHR_REFILL_ISSUE,
                MSHR_REFILL_WAIT: state_accepts_merge = 1'b1;
                default: state_accepts_merge = 1'b0;
            endcase
        end
    endfunction

    response_fifo #(
        .DEPTH (RESPONSE_DEPTH)
    ) response_queue (
        .clk        (clk),
        .reset_n    (reset_n),
        .push_valid (response_push_valid),
        .push_ready (response_push_ready),
        .push_id    (response_push_id),
        .push_data  (response_push_data),
        .pop_valid  (cpu_rsp_valid),
        .pop_ready  (cpu_rsp_ready),
        .pop_id     (cpu_rsp_id),
        .pop_data   (cpu_rsp_rdata)
    );

    // ---------------------------------------------------------------------
    // Address decoding and lookup
    // ---------------------------------------------------------------------

    assign cpu_set_index = cpu_req_addr
        [OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];

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

    assign way_hit[0] = lookup_valid_q[0]
                        && !lookup_reserved_q[0]
                        && (lookup_tag_q[0] == lookup_req_tag);
    assign way_hit[1] = lookup_valid_q[1]
                        && !lookup_reserved_q[1]
                        && (lookup_tag_q[1] == lookup_req_tag);
    assign lookup_hit = |way_hit;

    always_comb begin
        lookup_hit_way = '0;

        if (way_hit[0])
            lookup_hit_way = way_t'(0);
        else if (way_hit[1])
            lookup_hit_way = way_t'(1);
    end

    assign lookup_selected_word = lookup_line_q[lookup_hit_way]
        [(lookup_word_index * DATA_WIDTH) +: DATA_WIDTH];

    // Two-way victim selection ignores ways already reserved by older MSHRs.
    always_comb begin
        lookup_victim_available = 1'b0;
        lookup_victim_way       = '0;

        if (!lookup_reserved_q[0] && !lookup_valid_q[0]) begin
            lookup_victim_available = 1'b1;
            lookup_victim_way       = way_t'(0);
        end
        else if (!lookup_reserved_q[1] && !lookup_valid_q[1]) begin
            lookup_victim_available = 1'b1;
            lookup_victim_way       = way_t'(1);
        end
        else if (!lookup_reserved_q
                 [lru_victim_array[lookup_set_index]]) begin
            lookup_victim_available = 1'b1;
            lookup_victim_way = lru_victim_array[lookup_set_index];
        end
        else if (!lookup_reserved_q
                 [~lru_victim_array[lookup_set_index]]) begin
            lookup_victim_available = 1'b1;
            lookup_victim_way = ~lru_victim_array[lookup_set_index];
        end
    end

    assign lookup_victim_dirty = lookup_victim_available
        && lookup_valid_q[lookup_victim_way]
        && lookup_dirty_q[lookup_victim_way];

    // Search active MSHRs by line address. This prevents duplicate refills.
    always_comb begin
        mshr_match_valid = 1'b0;
        mshr_match_index = '0;

        for (match_scan_number = 0;
             match_scan_number < NUM_MSHRS;
             match_scan_number = match_scan_number + 1) begin
            if (!mshr_match_valid
                && mshr_valid_q[match_scan_number]
                && mshr_line_addr_q[match_scan_number]
                   == lookup_line_addr) begin
                mshr_match_valid = 1'b1;
                mshr_match_index = mshr_index_t'(match_scan_number);
            end
        end
    end

    // A request for a line currently reserved as somebody else's victim must
    // wait. This is essential for dirty victims: reading memory before their
    // writeback completes could return stale data.
    always_comb begin
        victim_conflict_valid = 1'b0;

        for (victim_conflict_scan_number = 0;
             victim_conflict_scan_number < NUM_MSHRS;
             victim_conflict_scan_number = victim_conflict_scan_number + 1) begin
            if (mshr_valid_q[victim_conflict_scan_number]
                && mshr_victim_valid_q[victim_conflict_scan_number]
                && mshr_victim_addr_q[victim_conflict_scan_number]
                   == lookup_line_addr) begin
                victim_conflict_valid = 1'b1;
            end
        end
    end

    always_comb begin
        free_mshr_valid = 1'b0;
        free_mshr_index = '0;

        for (free_scan_number = 0;
             free_scan_number < NUM_MSHRS;
             free_scan_number = free_scan_number + 1) begin
            if (!free_mshr_valid && !mshr_valid_q[free_scan_number]) begin
                free_mshr_valid = 1'b1;
                free_mshr_index = mshr_index_t'(free_scan_number);
            end
        end
    end

    // ---------------------------------------------------------------------
    // Arbiters
    // ---------------------------------------------------------------------

    always_comb begin
        writeback_select_valid = 1'b0;
        writeback_select_index = '0;

        for (writeback_scan_number = 0;
             writeback_scan_number < NUM_MSHRS;
             writeback_scan_number = writeback_scan_number + 1) begin
            if (!writeback_select_valid
                && mshr_valid_q[writeback_scan_number]
                && mshr_state_q[writeback_scan_number]
                   == MSHR_WRITEBACK_PENDING) begin
                writeback_select_valid = 1'b1;
                writeback_select_index =
                    mshr_index_t'(writeback_scan_number);
            end
        end
    end

    always_comb begin
        ar_select_valid = 1'b0;
        ar_select_index = '0;

        for (ar_scan_number = 0;
             ar_scan_number < NUM_MSHRS;
             ar_scan_number = ar_scan_number + 1) begin
            if (!ar_select_valid
                && mshr_valid_q[ar_scan_number]
                && mshr_state_q[ar_scan_number]
                   == MSHR_REFILL_REQUEST) begin
                ar_select_valid = 1'b1;
                ar_select_index = mshr_index_t'(ar_scan_number);
            end
        end
    end

    always_comb begin
        install_select_valid = 1'b0;
        install_select_index = '0;

        for (install_scan_number = 0;
             install_scan_number < NUM_MSHRS;
             install_scan_number = install_scan_number + 1) begin
            if (!install_select_valid
                && mshr_valid_q[install_scan_number]
                && mshr_state_q[install_scan_number]
                   == MSHR_INSTALL_PENDING) begin
                install_select_valid = 1'b1;
                install_select_index =
                    mshr_index_t'(install_scan_number);
            end
        end
    end

    assign install_fire = install_select_valid;

    always_comb begin
        apply_select_valid = 1'b0;
        apply_select_index = '0;

        for (apply_scan_number = 0;
             apply_scan_number < NUM_MSHRS;
             apply_scan_number = apply_scan_number + 1) begin
            if (!apply_select_valid
                && mshr_valid_q[apply_scan_number]
                && mshr_state_q[apply_scan_number] == MSHR_APPLY) begin
                apply_select_valid = 1'b1;
                apply_select_index = mshr_index_t'(apply_scan_number);
            end
        end
    end

    // ---------------------------------------------------------------------
    // Lookup decisions and response arbitration
    // ---------------------------------------------------------------------

    assign cpu_req_ready = (lookup_state_q == LOOKUP_IDLE)
                           && !install_fire;

    assign lookup_hit_complete =
        (lookup_state_q == LOOKUP_COMPARE)
        && !install_fire
        && lookup_hit
        && response_push_ready;

    assign merge_fire =
        (lookup_state_q == LOOKUP_COMPARE)
        && !install_fire
        && !lookup_hit
        && mshr_match_valid
        && state_accepts_merge(mshr_state_q[mshr_match_index])
        && (mshr_req_count_q[mshr_match_index] < MERGE_DEPTH);

    assign allocate_fire =
        (lookup_state_q == LOOKUP_COMPARE)
        && !install_fire
        && !lookup_hit
        && !mshr_match_valid
        && !victim_conflict_valid
        && free_mshr_valid
        && lookup_victim_available;

    // Cache hits have response priority. One APPLY entry may produce a second
    // source, but only one item is pushed into the FIFO each cycle.
    assign apply_fire = apply_select_valid
                        && response_push_ready
                        && !lookup_hit_complete;

    always_comb begin
        response_push_valid = 1'b0;
        response_push_id    = '0;
        response_push_data  = '0;

        if (lookup_hit_complete) begin
            response_push_valid = 1'b1;
            response_push_id    = lookup_req_id_q;
            response_push_data  = lookup_req_write_q
                ? '0 : lookup_selected_word;
        end
        else if (apply_fire) begin
            response_push_valid = 1'b1;
            response_push_id = mshr_req_id_q
                [apply_select_index]
                [mshr_process_index_q[apply_select_index]];

            if (mshr_req_write_q
                [apply_select_index]
                [mshr_process_index_q[apply_select_index]]) begin
                response_push_data = '0;
            end
            else begin
                response_push_data = mshr_work_line_q[apply_select_index]
                    [(mshr_req_word_index_q
                      [apply_select_index]
                      [mshr_process_index_q[apply_select_index]]
                      * DATA_WIDTH) +: DATA_WIDTH];
            end
        end
    end

    always_comb begin
        lookup_state_d = lookup_state_q;

        case (lookup_state_q)
            LOOKUP_IDLE: begin
                if (cpu_req_valid && cpu_req_ready)
                    lookup_state_d = LOOKUP_COMPARE;
            end

            LOOKUP_COMPARE: begin
                if (install_fire) begin
                    lookup_state_d = LOOKUP_RETRY;
                end
                else if (lookup_hit) begin
                    if (response_push_ready)
                        lookup_state_d = LOOKUP_IDLE;
                end
                else if (merge_fire || allocate_fire) begin
                    lookup_state_d = LOOKUP_IDLE;
                end
                else begin
                    // No MSHR, no merge slot, all target ways reserved, or a
                    // matching MSHR is already draining. Refresh and retry.
                    lookup_state_d = LOOKUP_RETRY;
                end
            end

            LOOKUP_RETRY: begin
                if (!install_fire)
                    lookup_state_d = LOOKUP_COMPARE;
            end

            default: lookup_state_d = LOOKUP_IDLE;
        endcase
    end

    // ---------------------------------------------------------------------
    // AXI channel generation
    // ---------------------------------------------------------------------

    always_comb begin
        m_axi_awvalid = 1'b0;
        m_axi_awid    = writeback_index_q;
        m_axi_awaddr  = mshr_victim_addr_q[writeback_index_q];
        m_axi_awlen   = AXI_LINE_LEN;
        m_axi_awsize  = AXI_WORD_SIZE;
        m_axi_awburst = AXI_BURST_INCR;

        m_axi_wvalid = 1'b0;
        m_axi_wdata  = mshr_victim_line_q[writeback_index_q]
            [(writeback_beat_q * AXI_DATA_WIDTH) +: AXI_DATA_WIDTH];
        m_axi_wstrb  = {AXI_BYTES{1'b1}};
        m_axi_wlast  = (writeback_beat_q == AXI_BEATS_PER_LINE - 1);

        m_axi_bready = 1'b0;

        case (writeback_state_q)
            WB_ADDRESS:  m_axi_awvalid = 1'b1;
            WB_DATA:     m_axi_wvalid  = 1'b1;
            WB_RESPONSE: m_axi_bready  = 1'b1;
            default: begin
                // WB_IDLE only performs arbitration.
            end
        endcase
    end

    assign m_axi_arvalid = ar_hold_valid_q;
    assign m_axi_arid    = ar_hold_index_q;
    assign m_axi_araddr  = mshr_line_addr_q[ar_hold_index_q];
    assign m_axi_arlen   = AXI_LINE_LEN;
    assign m_axi_arsize  = AXI_WORD_SIZE;
    assign m_axi_arburst = AXI_BURST_INCR;

    assign m_axi_rready = mshr_valid_q[m_axi_rid]
                          && (mshr_state_q[m_axi_rid]
                              == MSHR_REFILL_WAIT);

    // ---------------------------------------------------------------------
    // Sequential control and data updates
    // ---------------------------------------------------------------------

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            lookup_state_q    <= LOOKUP_IDLE;
            lookup_req_id_q   <= '0;
            lookup_req_addr_q <= '0;
            lookup_req_write_q <= 1'b0;
            lookup_req_wdata_q <= '0;
            lookup_req_wstrb_q <= '0;

            writeback_state_q <= WB_IDLE;
            writeback_index_q <= '0;
            writeback_beat_q  <= '0;
            ar_hold_valid_q   <= 1'b0;
            ar_hold_index_q   <= '0;

            for (capture_way_number = 0;
                 capture_way_number < NUM_WAYS;
                 capture_way_number = capture_way_number + 1) begin
                lookup_valid_q[capture_way_number]    <= 1'b0;
                lookup_dirty_q[capture_way_number]    <= 1'b0;
                lookup_reserved_q[capture_way_number] <= 1'b0;
                lookup_tag_q[capture_way_number]      <= '0;
                lookup_line_q[capture_way_number]     <= '0;
            end

            for (set_number = 0;
                 set_number < NUM_SETS;
                 set_number = set_number + 1) begin
                lru_victim_array[set_number] <= 1'b0;

                for (way_number = 0;
                     way_number < NUM_WAYS;
                     way_number = way_number + 1) begin
                    valid_array[set_number][way_number]    <= 1'b0;
                    dirty_array[set_number][way_number]    <= 1'b0;
                    reserved_array[set_number][way_number] <= 1'b0;
                    tag_array[set_number][way_number]      <= '0;
                    data_array[set_number][way_number]     <= '0;
                end
            end

            for (prepare_scan_number = 0;
                 prepare_scan_number < NUM_MSHRS;
                 prepare_scan_number = prepare_scan_number + 1) begin
                mshr_valid_q[prepare_scan_number]          <= 1'b0;
                mshr_state_q[prepare_scan_number]          <= MSHR_FREE;
                mshr_line_addr_q[prepare_scan_number]      <= '0;
                mshr_set_index_q[prepare_scan_number]      <= '0;
                mshr_tag_q[prepare_scan_number]            <= '0;
                mshr_victim_way_q[prepare_scan_number]     <= '0;
                mshr_victim_valid_q[prepare_scan_number]   <= 1'b0;
                mshr_victim_addr_q[prepare_scan_number]    <= '0;
                mshr_victim_line_q[prepare_scan_number]    <= '0;
                mshr_refill_line_q[prepare_scan_number]    <= '0;
                mshr_work_line_q[prepare_scan_number]      <= '0;
                mshr_line_dirty_q[prepare_scan_number]     <= 1'b0;
                mshr_refill_beat_q[prepare_scan_number]    <= '0;
                mshr_req_count_q[prepare_scan_number]      <= '0;
                mshr_process_index_q[prepare_scan_number]  <= '0;

                for (request_slot_number = 0;
                     request_slot_number < MERGE_DEPTH;
                     request_slot_number = request_slot_number + 1) begin
                    mshr_req_id_q[prepare_scan_number]
                        [request_slot_number] <= '0;
                    mshr_req_write_q[prepare_scan_number]
                        [request_slot_number] <= 1'b0;
                    mshr_req_word_index_q[prepare_scan_number]
                        [request_slot_number] <= '0;
                    mshr_req_wdata_q[prepare_scan_number]
                        [request_slot_number] <= '0;
                    mshr_req_wstrb_q[prepare_scan_number]
                        [request_slot_number] <= '0;
                end
            end
        end
        else begin
            lookup_state_q <= lookup_state_d;

            // Stage 0 request capture.
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
                    lookup_reserved_q[capture_way_number]
                        <= reserved_array[cpu_set_index][capture_way_number];
                    lookup_tag_q[capture_way_number]
                        <= tag_array[cpu_set_index][capture_way_number];
                    lookup_line_q[capture_way_number]
                        <= data_array[cpu_set_index][capture_way_number];
                end
            end

            // Resource waits and array installations require a fresh snapshot.
            if (lookup_state_q == LOOKUP_RETRY && !install_fire) begin
                for (capture_way_number = 0;
                     capture_way_number < NUM_WAYS;
                     capture_way_number = capture_way_number + 1) begin
                    lookup_valid_q[capture_way_number]
                        <= valid_array[lookup_set_index][capture_way_number];
                    lookup_dirty_q[capture_way_number]
                        <= dirty_array[lookup_set_index][capture_way_number];
                    lookup_reserved_q[capture_way_number]
                        <= reserved_array[lookup_set_index][capture_way_number];
                    lookup_tag_q[capture_way_number]
                        <= tag_array[lookup_set_index][capture_way_number];
                    lookup_line_q[capture_way_number]
                        <= data_array[lookup_set_index][capture_way_number];
                end
            end

            // Normal load/store hit.
            if (lookup_hit_complete) begin
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
                end

                lru_victim_array[lookup_set_index] <= ~lookup_hit_way;
            end

            // New miss allocation and first dependent request.
            if (allocate_fire) begin
                mshr_valid_q[free_mshr_index]       <= 1'b1;
                mshr_state_q[free_mshr_index]
                    <= lookup_victim_dirty
                       ? MSHR_WRITEBACK_PENDING
                       : MSHR_REFILL_REQUEST;
                mshr_line_addr_q[free_mshr_index]   <= lookup_line_addr;
                mshr_set_index_q[free_mshr_index]   <= lookup_set_index;
                mshr_tag_q[free_mshr_index]         <= lookup_req_tag;
                mshr_victim_way_q[free_mshr_index]  <= lookup_victim_way;
                mshr_victim_valid_q[free_mshr_index]
                    <= lookup_valid_q[lookup_victim_way];
                mshr_victim_line_q[free_mshr_index]
                    <= lookup_line_q[lookup_victim_way];
                mshr_victim_addr_q[free_mshr_index] <= {
                    lookup_tag_q[lookup_victim_way],
                    lookup_set_index,
                    {OFFSET_BITS{1'b0}}
                };
                mshr_refill_line_q[free_mshr_index] <= '0;
                mshr_work_line_q[free_mshr_index]   <= '0;
                mshr_line_dirty_q[free_mshr_index]  <= 1'b0;
                mshr_refill_beat_q[free_mshr_index] <= '0;
                mshr_req_count_q[free_mshr_index]   <= 1;
                mshr_process_index_q[free_mshr_index] <= '0;

                mshr_req_id_q[free_mshr_index][0]
                    <= lookup_req_id_q;
                mshr_req_write_q[free_mshr_index][0]
                    <= lookup_req_write_q;
                mshr_req_word_index_q[free_mshr_index][0]
                    <= lookup_word_index;
                mshr_req_wdata_q[free_mshr_index][0]
                    <= lookup_req_wdata_q;
                mshr_req_wstrb_q[free_mshr_index][0]
                    <= lookup_req_wstrb_q;

                reserved_array[lookup_set_index][lookup_victim_way]
                    <= 1'b1;
            end

            // Same-line secondary miss merge.
            if (merge_fire) begin
                mshr_req_id_q[mshr_match_index]
                    [mshr_req_count_q[mshr_match_index]]
                    <= lookup_req_id_q;
                mshr_req_write_q[mshr_match_index]
                    [mshr_req_count_q[mshr_match_index]]
                    <= lookup_req_write_q;
                mshr_req_word_index_q[mshr_match_index]
                    [mshr_req_count_q[mshr_match_index]]
                    <= lookup_word_index;
                mshr_req_wdata_q[mshr_match_index]
                    [mshr_req_count_q[mshr_match_index]]
                    <= lookup_req_wdata_q;
                mshr_req_wstrb_q[mshr_match_index]
                    [mshr_req_count_q[mshr_match_index]]
                    <= lookup_req_wstrb_q;
                mshr_req_count_q[mshr_match_index]
                    <= mshr_req_count_q[mshr_match_index] + 1'b1;
            end

            // Serialized dirty-victim writeback engine.
            case (writeback_state_q)
                WB_IDLE: begin
                    if (writeback_select_valid) begin
                        writeback_index_q <= writeback_select_index;
                        writeback_beat_q  <= '0;
                        writeback_state_q <= WB_ADDRESS;
                        mshr_state_q[writeback_select_index]
                            <= MSHR_WRITEBACK_ACTIVE;
                    end
                end

                WB_ADDRESS: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        writeback_beat_q  <= '0;
                        writeback_state_q <= WB_DATA;
                    end
                end

                WB_DATA: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        if (m_axi_wlast) begin
                            writeback_beat_q  <= '0;
                            writeback_state_q <= WB_RESPONSE;
                        end
                        else begin
                            writeback_beat_q
                                <= writeback_beat_q + 1'b1;
                        end
                    end
                end

                WB_RESPONSE: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        writeback_state_q <= WB_IDLE;
                        mshr_state_q[writeback_index_q]
                            <= MSHR_REFILL_REQUEST;
                    end
                end

                default: writeback_state_q <= WB_IDLE;
            endcase

            // Latch one stable AXI read-address request.
            if (!ar_hold_valid_q && ar_select_valid) begin
                ar_hold_valid_q <= 1'b1;
                ar_hold_index_q <= ar_select_index;
                mshr_state_q[ar_select_index] <= MSHR_REFILL_ISSUE;
            end

            if (ar_hold_valid_q && m_axi_arvalid && m_axi_arready) begin
                ar_hold_valid_q <= 1'b0;
                mshr_state_q[ar_hold_index_q] <= MSHR_REFILL_WAIT;
                mshr_refill_line_q[ar_hold_index_q] <= '0;
                mshr_refill_beat_q[ar_hold_index_q] <= '0;
            end

            // RID independently routes every returned read beat.
            if (m_axi_rvalid && m_axi_rready) begin
                mshr_refill_line_q[m_axi_rid]
                    [(mshr_refill_beat_q[m_axi_rid] * AXI_DATA_WIDTH)
                     +: AXI_DATA_WIDTH]
                    <= m_axi_rdata;

                if (m_axi_rlast) begin
                    mshr_refill_beat_q[m_axi_rid] <= '0;
                    mshr_state_q[m_axi_rid] <= MSHR_PREPARE;
                end
                else begin
                    mshr_refill_beat_q[m_axi_rid]
                        <= mshr_refill_beat_q[m_axi_rid] + 1'b1;
                end
            end

            // The PREPARE cycle copies the now-complete refill, including its
            // final beat, before merged requests begin modifying it.
            for (prepare_scan_number = 0;
                 prepare_scan_number < NUM_MSHRS;
                 prepare_scan_number = prepare_scan_number + 1) begin
                if (mshr_valid_q[prepare_scan_number]
                    && mshr_state_q[prepare_scan_number] == MSHR_PREPARE) begin
                    mshr_work_line_q[prepare_scan_number]
                        <= mshr_refill_line_q[prepare_scan_number];
                    mshr_line_dirty_q[prepare_scan_number] <= 1'b0;
                    mshr_process_index_q[prepare_scan_number] <= '0;
                    mshr_state_q[prepare_scan_number] <= MSHR_APPLY;
                end
            end

            // Apply one merged operation and create one CPU response per cycle.
            if (apply_fire) begin
                if (mshr_req_write_q
                    [apply_select_index]
                    [mshr_process_index_q[apply_select_index]]) begin
                    for (apply_byte_number = 0;
                         apply_byte_number < WORD_BYTES;
                         apply_byte_number = apply_byte_number + 1) begin
                        if (mshr_req_wstrb_q
                            [apply_select_index]
                            [mshr_process_index_q[apply_select_index]]
                            [apply_byte_number]) begin
                            mshr_work_line_q[apply_select_index]
                                [(mshr_req_word_index_q
                                  [apply_select_index]
                                  [mshr_process_index_q[apply_select_index]]
                                  * DATA_WIDTH)
                                 + (apply_byte_number * 8) +: 8]
                                <= mshr_req_wdata_q
                                   [apply_select_index]
                                   [mshr_process_index_q[apply_select_index]]
                                   [(apply_byte_number * 8) +: 8];
                        end
                    end

                    if (|mshr_req_wstrb_q
                        [apply_select_index]
                        [mshr_process_index_q[apply_select_index]]) begin
                        mshr_line_dirty_q[apply_select_index] <= 1'b1;
                    end
                end

                if ({1'b0, mshr_process_index_q[apply_select_index]}
                    == (mshr_req_count_q[apply_select_index] - 1'b1)) begin
                    mshr_state_q[apply_select_index]
                        <= MSHR_INSTALL_PENDING;
                end
                else begin
                    mshr_process_index_q[apply_select_index]
                        <= mshr_process_index_q[apply_select_index] + 1'b1;
                end
            end

            // Single array-write-port installation arbiter.
            if (install_fire) begin
                data_array
                    [mshr_set_index_q[install_select_index]]
                    [mshr_victim_way_q[install_select_index]]
                    <= mshr_work_line_q[install_select_index];
                tag_array
                    [mshr_set_index_q[install_select_index]]
                    [mshr_victim_way_q[install_select_index]]
                    <= mshr_tag_q[install_select_index];
                valid_array
                    [mshr_set_index_q[install_select_index]]
                    [mshr_victim_way_q[install_select_index]]
                    <= 1'b1;
                dirty_array
                    [mshr_set_index_q[install_select_index]]
                    [mshr_victim_way_q[install_select_index]]
                    <= mshr_line_dirty_q[install_select_index];
                reserved_array
                    [mshr_set_index_q[install_select_index]]
                    [mshr_victim_way_q[install_select_index]]
                    <= 1'b0;
                lru_victim_array
                    [mshr_set_index_q[install_select_index]]
                    <= ~mshr_victim_way_q[install_select_index];

                mshr_valid_q[install_select_index] <= 1'b0;
                mshr_state_q[install_select_index] <= MSHR_FREE;
                mshr_req_count_q[install_select_index] <= '0;
                mshr_process_index_q[install_select_index] <= '0;
            end

`ifndef SYNTHESIS
            if (m_axi_rvalid
                && (!mshr_valid_q[m_axi_rid]
                    || mshr_state_q[m_axi_rid] != MSHR_REFILL_WAIT)) begin
                $fatal(1,
                    "AXI RID %0d does not identify an MSHR waiting for data",
                    m_axi_rid);
            end

            if (m_axi_bvalid && m_axi_bready) begin
                if (m_axi_bresp != AXI_RESP_OKAY)
                    $fatal(1, "AXI write response error: BRESP=%02b",
                           m_axi_bresp);

                if (m_axi_bid != writeback_index_q)
                    $fatal(1,
                        "AXI BID %0d does not match writeback MSHR %0d",
                        m_axi_bid, writeback_index_q);
            end

            if (m_axi_rvalid && m_axi_rready) begin
                if (m_axi_rresp != AXI_RESP_OKAY)
                    $fatal(1, "AXI read response error: RRESP=%02b",
                           m_axi_rresp);

                if (m_axi_rlast
                    != (mshr_refill_beat_q[m_axi_rid]
                        == AXI_BEATS_PER_LINE - 1)) begin
                    $fatal(1,
                        "AXI RLAST arrived on wrong beat for MSHR %0d",
                        m_axi_rid);
                end
            end

            if (way_hit == {NUM_WAYS{1'b1}})
                $fatal(1, "Both cache ways hit the same request");

            for (assertion_outer_number = 0;
                 assertion_outer_number < NUM_MSHRS;
                 assertion_outer_number = assertion_outer_number + 1) begin
                if (mshr_valid_q[assertion_outer_number]
                    && mshr_req_count_q[assertion_outer_number]
                       > MERGE_DEPTH) begin
                    $fatal(1, "MSHR %0d merge queue overflow",
                           assertion_outer_number);
                end

                for (assertion_inner_number = assertion_outer_number + 1;
                     assertion_inner_number < NUM_MSHRS;
                     assertion_inner_number = assertion_inner_number + 1) begin
                    if (mshr_valid_q[assertion_outer_number]
                        && mshr_valid_q[assertion_inner_number]
                        && mshr_line_addr_q[assertion_outer_number]
                           == mshr_line_addr_q[assertion_inner_number]) begin
                        $fatal(1,
                            "Duplicate MSHRs %0d and %0d own the same line",
                            assertion_outer_number,
                            assertion_inner_number);
                    end

                    if (mshr_valid_q[assertion_outer_number]
                        && mshr_valid_q[assertion_inner_number]
                        && mshr_set_index_q[assertion_outer_number]
                           == mshr_set_index_q[assertion_inner_number]
                        && mshr_victim_way_q[assertion_outer_number]
                           == mshr_victim_way_q[assertion_inner_number]) begin
                        $fatal(1,
                            "MSHRs %0d and %0d reserve the same cache way",
                            assertion_outer_number,
                            assertion_inner_number);
                    end
                end
            end
`endif
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (NUM_WAYS != 2)
            $fatal(1, "This educational implementation requires NUM_WAYS=2");
        if (NUM_MSHRS != (1 << AXI_ID_WIDTH))
            $fatal(1, "NUM_MSHRS must be a power of two");
        if (MERGE_DEPTH < 2)
            $fatal(1, "MERGE_DEPTH must be at least two");
    end
`endif

endmodule
