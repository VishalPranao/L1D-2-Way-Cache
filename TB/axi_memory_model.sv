module axi_memory_model
    import cache_pkg::*;
#(
    parameter int MEM_BYTES         = 64 * 1024,
    parameter int BASE_READ_LATENCY = 12
)(
    input  logic                      clk,
    input  logic                      reset_n,

    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,
    input  logic [AXI_ID_WIDTH-1:0]   s_axi_awid,
    input  logic [ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  logic [7:0]                s_axi_awlen,
    input  logic [2:0]                s_axi_awsize,
    input  logic [1:0]                s_axi_awburst,

    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,
    input  logic [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [AXI_BYTES-1:0]      s_axi_wstrb,
    input  logic                      s_axi_wlast,

    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,
    output logic [AXI_ID_WIDTH-1:0]   s_axi_bid,
    output logic [1:0]                s_axi_bresp,

    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,
    input  logic [AXI_ID_WIDTH-1:0]   s_axi_arid,
    input  logic [ADDR_WIDTH-1:0]     s_axi_araddr,
    input  logic [7:0]                s_axi_arlen,
    input  logic [2:0]                s_axi_arsize,
    input  logic [1:0]                s_axi_arburst,

    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready,
    output logic [AXI_ID_WIDTH-1:0]   s_axi_rid,
    output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic                      s_axi_rlast,
    output logic [1:0]                s_axi_rresp
);

    logic [7:0] memory [0:MEM_BYTES-1];

    // One read slot per AXI ID. Requests may be outstanding together, while
    // complete bursts are returned in a deterministic out-of-order sequence.
    logic                  read_valid_q [0:NUM_MSHRS-1];
    logic [ADDR_WIDTH-1:0] read_base_q [0:NUM_MSHRS-1];
    logic [7:0]            read_len_q [0:NUM_MSHRS-1];
    logic [7:0]            read_beat_q [0:NUM_MSHRS-1];
    integer                read_wait_q [0:NUM_MSHRS-1];

    logic                  ready_read_valid;
    axi_id_t               ready_read_id;

    logic                  r_stream_valid_q;
    axi_id_t               r_stream_id_q;
    logic [AXI_DATA_WIDTH-1:0] r_stream_data_q;
    logic                  r_stream_last_q;

    logic                  write_active_q;
    logic [ADDR_WIDTH-1:0] write_base_q;
    logic [7:0]            write_len_q;
    logic [7:0]            write_beat_q;
    axi_id_t               write_id_q;
    logic                  bvalid_q;
    axi_id_t               bid_q;

    integer init_byte_number;
    integer read_slot_number;
    integer read_select_number;
    integer write_byte_number;

    function automatic logic [AXI_DATA_WIDTH-1:0] read_memory_beat(
        input logic [ADDR_WIDTH-1:0] base_address,
        input logic [7:0] beat_number
    );
        integer byte_number;
        begin
            read_memory_beat = '0;

            for (byte_number = 0;
                 byte_number < AXI_BYTES;
                 byte_number = byte_number + 1) begin
                read_memory_beat[(byte_number * 8) +: 8]
                    = memory[base_address
                             + (beat_number * AXI_BYTES)
                             + byte_number];
            end
        end
    endfunction

    initial begin
        for (init_byte_number = 0;
             init_byte_number < MEM_BYTES;
             init_byte_number = init_byte_number + 1) begin
            memory[init_byte_number]
                = (init_byte_number ^ (init_byte_number >> 8)) & 8'hFF;
        end
    end

    assign s_axi_arready = !read_valid_q[s_axi_arid];

    assign s_axi_rvalid = r_stream_valid_q;
    assign s_axi_rid    = r_stream_id_q;
    assign s_axi_rdata  = r_stream_data_q;
    assign s_axi_rlast  = r_stream_last_q;
    assign s_axi_rresp  = AXI_RESP_OKAY;

    assign s_axi_awready = !write_active_q && !bvalid_q;
    assign s_axi_wready  = write_active_q;
    assign s_axi_bvalid  = bvalid_q;
    assign s_axi_bid     = bid_q;
    assign s_axi_bresp   = AXI_RESP_OKAY;

    always_comb begin
        ready_read_valid = 1'b0;
        ready_read_id    = '0;

        for (read_select_number = 0;
             read_select_number < NUM_MSHRS;
             read_select_number = read_select_number + 1) begin
            if (!ready_read_valid
                && read_valid_q[read_select_number]
                && read_wait_q[read_select_number] == 0) begin
                ready_read_valid = 1'b1;
                ready_read_id = axi_id_t'(read_select_number);
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            r_stream_valid_q <= 1'b0;
            r_stream_id_q    <= '0;
            r_stream_data_q  <= '0;
            r_stream_last_q  <= 1'b0;

            for (read_slot_number = 0;
                 read_slot_number < NUM_MSHRS;
                 read_slot_number = read_slot_number + 1) begin
                read_valid_q[read_slot_number] <= 1'b0;
                read_base_q[read_slot_number]  <= '0;
                read_len_q[read_slot_number]   <= '0;
                read_beat_q[read_slot_number]  <= '0;
                read_wait_q[read_slot_number]  <= 0;
            end
        end
        else begin
            if (s_axi_arvalid && s_axi_arready) begin
                read_valid_q[s_axi_arid] <= 1'b1;
                read_base_q[s_axi_arid]  <= s_axi_araddr;
                read_len_q[s_axi_arid]   <= s_axi_arlen;
                read_beat_q[s_axi_arid]  <= '0;

                // Higher IDs receive shorter initial latency. This makes the
                // testbench observe legal out-of-order read completion.
                read_wait_q[s_axi_arid]
                    <= BASE_READ_LATENCY
                       + ((NUM_MSHRS - 1 - s_axi_arid) * 8);
            end

            for (read_slot_number = 0;
                 read_slot_number < NUM_MSHRS;
                 read_slot_number = read_slot_number + 1) begin
                if (read_valid_q[read_slot_number]
                    && read_wait_q[read_slot_number] > 0) begin
                    read_wait_q[read_slot_number]
                        <= read_wait_q[read_slot_number] - 1;
                end
            end

            // Once selected, a complete burst remains on the R channel. The
            // registered payload stays stable whenever RREADY is low.
            if (!r_stream_valid_q && ready_read_valid) begin
                r_stream_valid_q <= 1'b1;
                r_stream_id_q    <= ready_read_id;
                r_stream_data_q  <= read_memory_beat(
                    read_base_q[ready_read_id],
                    read_beat_q[ready_read_id]
                );
                r_stream_last_q <=
                    (read_beat_q[ready_read_id]
                     == read_len_q[ready_read_id]);
            end
            else if (r_stream_valid_q && s_axi_rready) begin
                if (r_stream_last_q) begin
                    read_valid_q[r_stream_id_q] <= 1'b0;
                    read_beat_q[r_stream_id_q]  <= '0;
                    r_stream_valid_q <= 1'b0;
                    r_stream_last_q  <= 1'b0;
                end
                else begin
                    read_beat_q[r_stream_id_q]
                        <= read_beat_q[r_stream_id_q] + 1'b1;
                    r_stream_data_q <= read_memory_beat(
                        read_base_q[r_stream_id_q],
                        read_beat_q[r_stream_id_q] + 1'b1
                    );
                    r_stream_last_q <=
                        ((read_beat_q[r_stream_id_q] + 1'b1)
                         == read_len_q[r_stream_id_q]);
                end
            end
        end
    end

    // Plain always is used because memory is also initialized by an initial
    // block. This avoids ModelSim's multiple-driver always_ff diagnostic.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            write_active_q <= 1'b0;
            write_base_q   <= '0;
            write_len_q    <= '0;
            write_beat_q   <= '0;
            write_id_q     <= '0;
            bvalid_q       <= 1'b0;
            bid_q          <= '0;
        end
        else begin
            if (bvalid_q && s_axi_bready)
                bvalid_q <= 1'b0;

            if (s_axi_awvalid && s_axi_awready) begin
                write_active_q <= 1'b1;
                write_base_q   <= s_axi_awaddr;
                write_len_q    <= s_axi_awlen;
                write_beat_q   <= '0;
                write_id_q     <= s_axi_awid;
            end
            else if (s_axi_wvalid && s_axi_wready) begin
                for (write_byte_number = 0;
                     write_byte_number < AXI_BYTES;
                     write_byte_number = write_byte_number + 1) begin
                    if (s_axi_wstrb[write_byte_number]) begin
                        memory[write_base_q
                               + (write_beat_q * AXI_BYTES)
                               + write_byte_number]
                            <= s_axi_wdata
                               [(write_byte_number * 8) +: 8];
                    end
                end

                if (s_axi_wlast) begin
                    write_active_q <= 1'b0;
                    write_beat_q   <= '0;
                    bvalid_q       <= 1'b1;
                    bid_q          <= write_id_q;
                end
                else begin
                    write_beat_q <= write_beat_q + 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (reset_n && s_axi_arvalid && s_axi_arready) begin
            if (s_axi_arburst != AXI_BURST_INCR
                || s_axi_arsize != AXI_WORD_SIZE
                || s_axi_arlen != AXI_LINE_LEN) begin
                $fatal(1, "Unsupported AXI read burst configuration");
            end
        end

        if (reset_n && s_axi_awvalid && s_axi_awready) begin
            if (s_axi_awburst != AXI_BURST_INCR
                || s_axi_awsize != AXI_WORD_SIZE
                || s_axi_awlen != AXI_LINE_LEN) begin
                $fatal(1, "Unsupported AXI write burst configuration");
            end
        end

        if (reset_n && s_axi_wvalid && s_axi_wready) begin
            if (s_axi_wlast != (write_beat_q == write_len_q)) begin
                $fatal(1, "AXI WLAST asserted on incorrect beat %0d",
                       write_beat_q);
            end
        end
    end
`endif

endmodule
