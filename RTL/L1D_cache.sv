module l1d_cache
    import cache_pkg::*;
(
    input  logic                  clk,
    input  logic                  reset_n,

    // CPU/LSU request interface. Phase 2 supports aligned loads only.
    input  logic                  cpu_req_valid,
    output logic                  cpu_req_ready,
    input  logic [ADDR_WIDTH-1:0] cpu_req_addr,

    // CPU/LSU response interface.
    output logic                  cpu_rsp_valid,
    input  logic                  cpu_rsp_ready,
    output logic [DATA_WIDTH-1:0] cpu_rsp_rdata,

    // Simplified lower-memory line request interface.
    output logic                  mem_req_valid,
    input  logic                  mem_req_ready,
    output logic [ADDR_WIDTH-1:0] mem_req_addr,

    // Simplified lower-memory line response interface.
    input  logic                  mem_rsp_valid,
    output logic                  mem_rsp_ready,
    input  line_t                 mem_rsp_data
);

    cache_state_t state_q;
    cache_state_t state_d;

    // Two entries (ways) exist in every set.
    logic  valid_array [0:NUM_SETS-1][0:NUM_WAYS-1];
    tag_t  tag_array   [0:NUM_SETS-1][0:NUM_WAYS-1];
    line_t data_array  [0:NUM_SETS-1][0:NUM_WAYS-1];

    // For this 2-way cache, one bit per set identifies the way that should be
    // replaced next when both ways are valid.
    //   0 -> Way 0 is the next replacement victim.
    //   1 -> Way 1 is the next replacement victim.
    logic lru_victim_array [0:NUM_SETS-1];

    // The blocking cache remembers one CPU request and one miss at a time.
    logic [ADDR_WIDTH-1:0] request_addr_q;
    line_t                 refill_line_q;
    logic [DATA_WIDTH-1:0] response_data_q;
    way_t                  victim_way_q;

    logic [OFFSET_BITS-1:0]     byte_offset;
    logic [INDEX_BITS-1:0]      set_index;
    logic [WORD_INDEX_BITS-1:0] word_index;
    tag_t                       request_tag;

    logic [NUM_WAYS-1:0] way_hit;
    logic                hit;
    way_t                hit_way;
    way_t                victim_way;

    logic [DATA_WIDTH-1:0] selected_word;

    integer set_number;
    integer way_number;

    // Address breakdown for the registered CPU request.
    assign byte_offset = request_addr_q[OFFSET_BITS-1:0];
    assign set_index = request_addr_q[OFFSET_BITS + INDEX_BITS - 1
                                      : OFFSET_BITS];
    assign request_tag = request_addr_q[ADDR_WIDTH-1
                                        : OFFSET_BITS + INDEX_BITS];

    // Bits [1:0] select a byte inside a 32-bit word. The remaining offset
    // bits select one of eight words inside the 32-byte cache line.
    assign word_index = byte_offset[OFFSET_BITS-1:$clog2(DATA_WIDTH/8)];

    // Both ways in the indexed set are compared in parallel.
    assign way_hit[0] = valid_array[set_index][0]
                        && (tag_array[set_index][0] == request_tag);

    assign way_hit[1] = valid_array[set_index][1]
                        && (tag_array[set_index][1] == request_tag);

    assign hit = |way_hit;

    // Exactly one way should match. Way 0 is the default when neither way
    // matches; that default is ignored whenever hit is zero.
    always_comb begin
        hit_way = '0;

        if (way_hit[0])
            hit_way = 1'b0;
        else if (way_hit[1])
            hit_way = 1'b1;
    end

    // Prefer an invalid way. Only use LRU when both ways already contain
    // valid cache lines.
    always_comb begin
        if (!valid_array[set_index][0])
            victim_way = 1'b0;
        else if (!valid_array[set_index][1])
            victim_way = 1'b1;
        else
            victim_way = lru_victim_array[set_index];
    end

    assign selected_word = data_array[set_index][hit_way]
                           [(word_index * DATA_WIDTH) +: DATA_WIDTH];

    // Output and handshake logic.
    always_comb begin
        cpu_req_ready = 1'b0;
        cpu_rsp_valid = 1'b0;
        cpu_rsp_rdata = response_data_q;

        mem_req_valid = 1'b0;
        mem_req_addr  = {
            request_addr_q[ADDR_WIDTH-1:OFFSET_BITS],
            {OFFSET_BITS{1'b0}}
        };
        mem_rsp_ready = 1'b0;

        case (state_q)
            IDLE: begin
                cpu_req_ready = 1'b1;
            end

            REFILL_REQ: begin
                mem_req_valid = 1'b1;
            end

            REFILL_WAIT: begin
                mem_rsp_ready = 1'b1;
            end

            RESPONSE: begin
                cpu_rsp_valid = 1'b1;
            end

            default: begin
                // LOOKUP and INSTALL perform internal cache operations.
            end
        endcase
    end

    // Next-state logic is almost unchanged from Phase 1.
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
                else
                    state_d = REFILL_REQ;
            end

            REFILL_REQ: begin
                if (mem_req_valid && mem_req_ready)
                    state_d = REFILL_WAIT;
            end

            REFILL_WAIT: begin
                if (mem_rsp_valid && mem_rsp_ready)
                    state_d = INSTALL;
            end

            INSTALL: begin
                // Replay the original request through the normal lookup path.
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

    // State, request, refill and cache-array registers.
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q         <= IDLE;
            request_addr_q  <= '0;
            refill_line_q   <= '0;
            response_data_q <= '0;
            victim_way_q    <= '0;

            for (set_number = 0;
                 set_number < NUM_SETS;
                 set_number = set_number + 1) begin

                lru_victim_array[set_number] <= 1'b0;

                for (way_number = 0;
                     way_number < NUM_WAYS;
                     way_number = way_number + 1) begin
                    valid_array[set_number][way_number] <= 1'b0;
                end
            end
        end
        else begin
            state_q <= state_d;

            // Capture a new CPU request.
            if (state_q == IDLE && cpu_req_valid && cpu_req_ready)
                request_addr_q <= cpu_req_addr;

            // On a miss, remember which way will receive the refill. This
            // selection stays stable while lower memory is being accessed.
            if (state_q == LOOKUP && !hit)
                victim_way_q <= victim_way;

            // Capture a complete cache-line response from lower memory.
            if (state_q == REFILL_WAIT
                && mem_rsp_valid && mem_rsp_ready)
                refill_line_q <= mem_rsp_data;

            // Install the refill only into the selected victim way.
            if (state_q == INSTALL) begin
                data_array[set_index][victim_way_q]  <= refill_line_q;
                tag_array[set_index][victim_way_q]   <= request_tag;
                valid_array[set_index][victim_way_q] <= 1'b1;

                // The newly installed way is now most recently used, so the
                // opposite way should be selected next if both are valid.
                lru_victim_array[set_index] <= ~victim_way_q;
            end

            // On a hit, return data from the matching way and mark the other
            // way as the next replacement victim.
            if (state_q == LOOKUP && hit) begin
                response_data_q <= selected_word;
                lru_victim_array[set_index] <= ~hit_way;
            end
        end
    end

endmodule
