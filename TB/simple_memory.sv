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

    logic [7:0] memory [0:MEM_BYTES-1];

    logic                  busy_q;
    logic [ADDR_WIDTH-1:0] pending_addr_q;
    integer                wait_count_q;

    logic  rsp_valid_q;
    line_t rsp_data_q;

    integer init_byte_number;
    integer resp_byte_number;

    assign mem_req_ready = !busy_q && !rsp_valid_q;
    assign mem_rsp_valid = rsp_valid_q;
    assign mem_rsp_data  = rsp_data_q;

    // Deterministic byte pattern. It depends on more than the lowest eight
    // address bits, so addresses separated by the cache capacity can still
    // contain different values.
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
            // Keep response valid asserted until the cache accepts it.
            if (rsp_valid_q && mem_rsp_ready)
                rsp_valid_q <= 1'b0;

            // Accept one aligned cache-line request.
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
                    // Return LINE_BYTES consecutive bytes in little-endian
                    // cache-line order.
                    for (resp_byte_number = 0;
                         resp_byte_number < LINE_BYTES;
                         resp_byte_number = resp_byte_number + 1) begin
                        rsp_data_q[(resp_byte_number * 8) +: 8]
                            <= memory[pending_addr_q + resp_byte_number];
                    end

                    busy_q       <= 1'b0;
                    wait_count_q <= 0;
                    rsp_valid_q  <= 1'b1;
                end
            end
        end
    end

endmodule
