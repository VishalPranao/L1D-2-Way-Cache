module axi_memory_model
    import cache_pkg::*;
#(
    parameter int MEM_BYTES    = 64 * 1024,
    parameter int READ_LATENCY = 3
)(
    input  logic                      clk,
    input  logic                      reset_n,

    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,
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
    output logic [1:0]                s_axi_bresp,

    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,
    input  logic [ADDR_WIDTH-1:0]     s_axi_araddr,
    input  logic [7:0]                s_axi_arlen,
    input  logic [2:0]                s_axi_arsize,
    input  logic [1:0]                s_axi_arburst,

    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready,
    output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic                      s_axi_rlast,
    output logic [1:0]                s_axi_rresp
);

    logic [7:0] memory [0:MEM_BYTES-1];

    logic                  read_active_q;
    logic [ADDR_WIDTH-1:0] read_base_q;
    logic [7:0]            read_len_q;
    logic [7:0]            read_beat_q;
    integer                read_wait_q;

    logic                  write_active_q;
    logic [ADDR_WIDTH-1:0] write_base_q;
    logic [7:0]            write_len_q;
    logic [7:0]            write_beat_q;
    logic                  bvalid_q;

    integer init_byte_number;
    integer read_byte_number;
    integer write_byte_number;

    assign s_axi_arready = !read_active_q;
    assign s_axi_rvalid  = read_active_q && (read_wait_q == 0);
    assign s_axi_rlast   = (read_beat_q == read_len_q);
    assign s_axi_rresp   = AXI_RESP_OKAY;

    assign s_axi_awready = !write_active_q && !bvalid_q;
    assign s_axi_wready  = write_active_q;
    assign s_axi_bvalid  = bvalid_q;
    assign s_axi_bresp   = AXI_RESP_OKAY;

    // Read data is presented little-endian, matching the cache-line layout.
    always_comb begin
        s_axi_rdata = '0;

        if (read_active_q) begin
            for (read_byte_number = 0;
                 read_byte_number < AXI_BYTES;
                 read_byte_number = read_byte_number + 1) begin
                s_axi_rdata[(read_byte_number * 8) +: 8]
                    = memory[read_base_q
                             + (read_beat_q * AXI_BYTES)
                             + read_byte_number];
            end
        end
    end

    initial begin
        for (init_byte_number = 0;
             init_byte_number < MEM_BYTES;
             init_byte_number = init_byte_number + 1) begin
            memory[init_byte_number]
                = (init_byte_number ^ (init_byte_number >> 8)) & 8'hFF;
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            read_active_q <= 1'b0;
            read_base_q   <= '0;
            read_len_q    <= '0;
            read_beat_q   <= '0;
            read_wait_q   <= 0;
        end
        else begin
            if (s_axi_arvalid && s_axi_arready) begin
                read_active_q <= 1'b1;
                read_base_q   <= s_axi_araddr;
                read_len_q    <= s_axi_arlen;
                read_beat_q   <= '0;
                read_wait_q   <= READ_LATENCY;
            end
            else if (read_active_q && read_wait_q > 0) begin
                read_wait_q <= read_wait_q - 1;
            end
            else if (s_axi_rvalid && s_axi_rready) begin
                if (s_axi_rlast) begin
                    read_active_q <= 1'b0;
                    read_beat_q   <= '0;
                end
                else begin
                    read_beat_q <= read_beat_q + 1'b1;
                end
            end
        end
    end

    // Plain always is used because the byte memory is also initialized by the
    // initial block. Using always_ff here would make ModelSim report that the
    // memory variable is driven by more than one process.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            write_active_q <= 1'b0;
            write_base_q   <= '0;
            write_len_q    <= '0;
            write_beat_q   <= '0;
            bvalid_q       <= 1'b0;
        end
        else begin
            if (bvalid_q && s_axi_bready)
                bvalid_q <= 1'b0;

            if (s_axi_awvalid && s_axi_awready) begin
                write_active_q <= 1'b1;
                write_base_q   <= s_axi_awaddr;
                write_len_q    <= s_axi_awlen;
                write_beat_q   <= '0;
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
                || s_axi_arsize != AXI_WORD_SIZE) begin
                $fatal(1, "Unsupported AXI read burst configuration");
            end
        end

        if (reset_n && s_axi_awvalid && s_axi_awready) begin
            if (s_axi_awburst != AXI_BURST_INCR
                || s_axi_awsize != AXI_WORD_SIZE) begin
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
