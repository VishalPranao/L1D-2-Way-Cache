module response_fifo
    import cache_pkg::*;
#(
    parameter int DEPTH = RESPONSE_DEPTH
)(
    input  logic                    clk,
    input  logic                    reset_n,

    input  logic                    push_valid,
    output logic                    push_ready,
    input  logic [REQ_ID_WIDTH-1:0] push_id,
    input  logic [DATA_WIDTH-1:0]   push_data,

    output logic                    pop_valid,
    input  logic                    pop_ready,
    output logic [REQ_ID_WIDTH-1:0] pop_id,
    output logic [DATA_WIDTH-1:0]   pop_data
);

    localparam int POINTER_WIDTH = $clog2(DEPTH);
    localparam int COUNT_WIDTH   = $clog2(DEPTH + 1);

    logic [REQ_ID_WIDTH-1:0] id_memory [0:DEPTH-1];
    logic [DATA_WIDTH-1:0] data_memory [0:DEPTH-1];

    logic [POINTER_WIDTH-1:0] read_pointer_q;
    logic [POINTER_WIDTH-1:0] write_pointer_q;
    logic [COUNT_WIDTH-1:0] count_q;

    logic push_fire;
    logic pop_fire;

    assign push_ready = (count_q < DEPTH);
    assign pop_valid  = (count_q != 0);
    assign pop_id     = id_memory[read_pointer_q];
    assign pop_data   = data_memory[read_pointer_q];

    assign push_fire = push_valid && push_ready;
    assign pop_fire  = pop_valid && pop_ready;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            read_pointer_q  <= '0;
            write_pointer_q <= '0;
            count_q         <= '0;
        end
        else begin
            if (push_fire) begin
                id_memory[write_pointer_q]   <= push_id;
                data_memory[write_pointer_q] <= push_data;
                write_pointer_q <= write_pointer_q + 1'b1;
            end

            if (pop_fire)
                read_pointer_q <= read_pointer_q + 1'b1;

            case ({push_fire, pop_fire})
                2'b10: count_q <= count_q + 1'b1;
                2'b01: count_q <= count_q - 1'b1;
                default: count_q <= count_q;
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (DEPTH < 2 || (DEPTH & (DEPTH - 1)) != 0)
            $fatal(1, "response_fifo DEPTH must be a power of two >= 2");
    end
`endif

endmodule
