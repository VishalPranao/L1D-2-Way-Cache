package cache_pkg;

    parameter int ADDR_WIDTH = 32;
    parameter int DATA_WIDTH = 32;

    // Phase 1 configuration:
    // 64 sets x 1 way x 32 bytes = 2 KiB direct-mapped cache.
    parameter int LINE_BYTES = 32;
    parameter int NUM_SETS   = 64;

    localparam int LINE_BITS   = LINE_BYTES * 8;
    localparam int OFFSET_BITS = $clog2(LINE_BYTES);
    localparam int INDEX_BITS  = $clog2(NUM_SETS);
    localparam int TAG_BITS    = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;
    localparam int WORD_BYTES  = DATA_WIDTH / 8;
    localparam int WORDS_PER_LINE = LINE_BYTES / WORD_BYTES;
    localparam int WORD_INDEX_BITS = $clog2(WORDS_PER_LINE);

    typedef logic [LINE_BITS-1:0] line_t;
    typedef logic [TAG_BITS-1:0]  tag_t;

    typedef enum logic [2:0] {
        IDLE,
        LOOKUP,
        REFILL_REQ,
        REFILL_WAIT,
        INSTALL,
        RESPONSE
    } cache_state_t;

endpackage
