module simple_memory
    import cache_pkg::*;
#(
    parameter int MEM_BYTES = 64 * 1024,
    parameter int LATENCY   = 3
)(
    input  logic                  clk,
    input  logic                  reset_n,

    input  logic                  mem_req_valid,
    output logic                  mem_req_ready,
    input  logic [ADDR_WIDTH-1:0] mem_req_addr,

    output logic                  mem_rsp_valid,
    input  logic                  mem_rsp_ready,
    output line_t                 mem_rsp_data
);

    // Phase 3 lower memory supplies refill lines only. Dirty-line writes are
    // deliberately added with the Phase 4 writeback interface.

    logic [7:0] memory [0:MEM_BYTES-1];

    logic                  busy_q;
    logic [ADDR_WIDTH-1:0] pending_addr_q;
    integer                wait_count_q;

    logic  rsp_valid_q;
    line_t rsp_data_q;

    // Separate loop variables avoid the always_ff multiple-driver error that
    // occurs when one shared integer is used by both procedural blocks.
    integer init_byte_number;
    integer response_byte_number;

    assign mem_req_ready = !busy_q && !rsp_valid_q;
    assign mem_rsp_valid = rsp_valid_q;
    assign mem_rsp_data  = rsp_data_q;

    initial begin
        for (init_byte_number = 0;
             init_byte_number < MEM_BYTES;
             init_byte_number = init_byte_number + 1) begin
            memory[init_byte_number] =
                (init_byte_number ^ (init_byte_number >> 8)) & 8'hFF;
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            busy_q         <= 1'b0;
            pending_addr_q <= '0;
            wait_count_q   <= 0;
            rsp_valid_q    <= 1'b0;
            rsp_data_q     <= '0;
        end
        else begin
            // Hold the response until the cache accepts it.
            if (rsp_valid_q && mem_rsp_ready)
                rsp_valid_q <= 1'b0;

            if (mem_req_valid && mem_req_ready) begin
                pending_addr_q <= mem_req_addr;
                wait_count_q   <= LATENCY;
                busy_q         <= 1'b1;
            end
            else if (busy_q) begin
                if (wait_count_q > 1) begin
                    wait_count_q <= wait_count_q - 1;
                end
                else begin
                    for (response_byte_number = 0;
                         response_byte_number < LINE_BYTES;
                         response_byte_number = response_byte_number + 1) begin
                        rsp_data_q[(response_byte_number * 8) +: 8]
                            <= memory[pending_addr_q + response_byte_number];
                    end

                    busy_q       <= 1'b0;
                    wait_count_q <= 0;
                    rsp_valid_q  <= 1'b1;
                end
            end
        end
    end

endmodule
