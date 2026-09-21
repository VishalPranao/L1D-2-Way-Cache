package cache_pkg;

    parameter int ADDR_WIDTH = 32;
    parameter int DATA_WIDTH = 32;

    // Phase 2 configuration:
    // 64 sets x 2 ways x 32 bytes = 4 KiB data capacity.
    parameter int LINE_BYTES = 32;
    parameter int NUM_SETS   = 64;
    parameter int NUM_WAYS   = 2;

    localparam int LINE_BITS       = LINE_BYTES * 8;
    localparam int OFFSET_BITS     = $clog2(LINE_BYTES);
    localparam int INDEX_BITS      = $clog2(NUM_SETS);
    localparam int TAG_BITS        = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;
    localparam int WORD_BYTES      = DATA_WIDTH / 8;
    localparam int WORDS_PER_LINE  = LINE_BYTES / WORD_BYTES;
    localparam int WORD_INDEX_BITS = $clog2(WORDS_PER_LINE);
    localparam int WAY_BITS        = $clog2(NUM_WAYS);

    typedef logic [LINE_BITS-1:0] line_t;
    typedef logic [TAG_BITS-1:0]  tag_t;
    typedef logic [WAY_BITS-1:0]  way_t;

    typedef enum logic [2:0] {
        IDLE,
        LOOKUP,
        REFILL_REQ,
        REFILL_WAIT,
        INSTALL,
        RESPONSE
    } cache_state_t;

endpackage
