module l1d_cache
    import cache_pkg::*;
(
    input  logic                  clk,
    input  logic                  reset_n,

    // CPU/LSU request interface. Phase 1 supports aligned loads only.
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

    // Phase 1 direct-mapped cache arrays. Each set has exactly one entry.
    logic  valid_array [0:NUM_SETS-1];    // Each set in the data array has a corresponding tag and valid array 
    tag_t  tag_array   [0:NUM_SETS-1];
    line_t data_array  [0:NUM_SETS-1];    // Equal to logic [255:0] data_array [0:63];  which has the 2KB cache

    // The blocking cache remembers one CPU request at a time.
    logic [ADDR_WIDTH-1:0] request_addr_q;
    line_t                 refill_line_q;
    logic [DATA_WIDTH-1:0] response_data_q;

    logic [OFFSET_BITS-1:0]     byte_offset;
    logic [INDEX_BITS-1:0]      set_index;
    logic [WORD_INDEX_BITS-1:0] word_index;
    tag_t                       request_tag;

    logic                  hit;
    logic [DATA_WIDTH-1:0] selected_word;

    integer set_number;

    // Address breakdown for the registered CPU request.
    assign byte_offset = request_addr_q[OFFSET_BITS-1:0];
    assign set_index = request_addr_q[OFFSET_BITS + INDEX_BITS - 1
                                      : OFFSET_BITS];
    assign request_tag = request_addr_q[ADDR_WIDTH-1
                                        : OFFSET_BITS + INDEX_BITS];

    // Bits [1:0] select a byte inside a 32-bit word. The remaining offset
    // bits select one of the eight words inside the 32-byte line.
    assign word_index = byte_offset[OFFSET_BITS-1:$clog2(DATA_WIDTH/8)];

    assign hit = valid_array[set_index]
                 && (tag_array[set_index] == request_tag);

    // Lowest-addressed word is stored in data_array[set][31:0].
    assign selected_word = data_array[set_index]
                           [(word_index * DATA_WIDTH) +: DATA_WIDTH];

    // Output and handshake logic. Defaults are inactive unless the current
    // FSM state explicitly enables an interface operation.
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

    // Next-state logic.
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
                // Replay the original request after the line is installed.
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

            // Only valid bits must be reset for correctness. Tags and data
            // may contain unknown values while their corresponding valid bit
            // is zero.
            for (set_number = 0; set_number < NUM_SETS; set_number++) begin
                valid_array[set_number] <= 1'b0;
            end
        end
        else begin
            state_q <= state_d;

            // Capture a new CPU request only when both valid and ready are 1.
            if (state_q == IDLE && cpu_req_valid && cpu_req_ready) begin
                request_addr_q <= cpu_req_addr;
            end

            // Capture the entire returned cache line.
            if (state_q == REFILL_WAIT
                && mem_rsp_valid && mem_rsp_ready) begin
                refill_line_q <= mem_rsp_data;
            end

            // Install the refill into the direct-mapped location.
            if (state_q == INSTALL) begin
                data_array[set_index]  <= refill_line_q;
                tag_array[set_index]   <= request_tag;
                valid_array[set_index] <= 1'b1;
            end

            // Hold response data stable throughout the RESPONSE state.
            if (state_q == LOOKUP && hit) begin
                response_data_q <= selected_word;
            end
        end
    end

endmodule
