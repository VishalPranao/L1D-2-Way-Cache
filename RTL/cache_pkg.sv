package cache_pkg;

    parameter int ADDR_WIDTH     = 32;
    parameter int DATA_WIDTH     = 32;
    parameter int LINE_BYTES     = 32;
    parameter int NUM_SETS       = 64;
    parameter int NUM_WAYS       = 2;
    parameter int AXI_DATA_WIDTH = 32;

    localparam int LINE_BITS       = LINE_BYTES * 8;
    localparam int OFFSET_BITS     = $clog2(LINE_BYTES);
    localparam int INDEX_BITS      = $clog2(NUM_SETS);
    localparam int TAG_BITS        = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;
    localparam int WORD_BYTES      = DATA_WIDTH / 8;
    localparam int WORDS_PER_LINE  = LINE_BYTES / WORD_BYTES;
    localparam int WORD_INDEX_BITS = $clog2(WORDS_PER_LINE);
    localparam int WAY_BITS        = $clog2(NUM_WAYS);

    localparam int AXI_BYTES            = AXI_DATA_WIDTH / 8;
    localparam int AXI_BEATS_PER_LINE   = LINE_BYTES / AXI_BYTES;
    localparam int AXI_BEAT_COUNT_BITS  = $clog2(AXI_BEATS_PER_LINE);

    localparam logic [7:0] AXI_LINE_LEN = AXI_BEATS_PER_LINE - 1;
    localparam logic [2:0] AXI_WORD_SIZE = $clog2(AXI_BYTES);
    localparam logic [1:0] AXI_BURST_INCR = 2'b01;
    localparam logic [1:0] AXI_RESP_OKAY  = 2'b00;

    typedef logic [LINE_BITS-1:0] line_t;
    typedef logic [TAG_BITS-1:0]  tag_t;
    typedef logic [WAY_BITS-1:0]  way_t;
    typedef logic [AXI_BEAT_COUNT_BITS-1:0] axi_beat_t;

    typedef enum logic [3:0] {
        IDLE,
        LOOKUP,
        WRITEBACK_AW,
        WRITEBACK_W,
        WRITEBACK_B,
        REFILL_AR,
        REFILL_R,
        INSTALL,
        REPLAY_READ,
        RESPONSE
    } cache_state_t;

endpackage
