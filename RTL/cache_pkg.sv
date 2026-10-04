package cache_pkg;

    parameter int ADDR_WIDTH       = 32;
    parameter int DATA_WIDTH       = 32;
    parameter int LINE_BYTES       = 32;
    parameter int NUM_SETS         = 64;
    parameter int NUM_WAYS         = 2;
    parameter int AXI_DATA_WIDTH   = 32;
    parameter int REQ_ID_WIDTH     = 4;

    // Non-blocking cache parameters.
    parameter int NUM_MSHRS        = 4;
    parameter int MERGE_DEPTH      = 4;
    parameter int RESPONSE_DEPTH   = 16;

    localparam int LINE_BITS       = LINE_BYTES * 8;
    localparam int OFFSET_BITS     = $clog2(LINE_BYTES);
    localparam int INDEX_BITS      = $clog2(NUM_SETS);
    localparam int TAG_BITS        = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;
    localparam int WORD_BYTES      = DATA_WIDTH / 8;
    localparam int WORDS_PER_LINE  = LINE_BYTES / WORD_BYTES;
    localparam int WORD_INDEX_BITS = $clog2(WORDS_PER_LINE);
    localparam int WAY_BITS        = $clog2(NUM_WAYS);

    localparam int AXI_BYTES           = AXI_DATA_WIDTH / 8;
    localparam int AXI_BEATS_PER_LINE  = LINE_BYTES / AXI_BYTES;
    localparam int AXI_BEAT_COUNT_BITS = $clog2(AXI_BEATS_PER_LINE);

    localparam int MSHR_INDEX_WIDTH = $clog2(NUM_MSHRS);
    localparam int AXI_ID_WIDTH      = MSHR_INDEX_WIDTH;
    localparam int MERGE_INDEX_WIDTH = $clog2(MERGE_DEPTH);
    localparam int MERGE_COUNT_WIDTH = $clog2(MERGE_DEPTH + 1);

    localparam logic [7:0] AXI_LINE_LEN = AXI_BEATS_PER_LINE - 1;
    localparam logic [2:0] AXI_WORD_SIZE = $clog2(AXI_BYTES);
    localparam logic [1:0] AXI_BURST_INCR = 2'b01;
    localparam logic [1:0] AXI_RESP_OKAY  = 2'b00;
    localparam logic [1:0] AXI_RESP_EXOKAY = 2'b01;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;
    localparam logic [1:0] AXI_RESP_DECERR = 2'b11;

    typedef logic [LINE_BITS-1:0] line_t;
    typedef logic [TAG_BITS-1:0] tag_t;
    typedef logic [WAY_BITS-1:0] way_t;
    typedef logic [MSHR_INDEX_WIDTH-1:0] mshr_index_t;
    typedef logic [AXI_ID_WIDTH-1:0] axi_id_t;
    typedef logic [AXI_BEAT_COUNT_BITS-1:0] axi_beat_t;
    typedef logic [WORD_INDEX_BITS-1:0] word_index_t;

    typedef enum logic [1:0] {
        LOOKUP_IDLE,
        LOOKUP_COMPARE,
        LOOKUP_RETRY
    } lookup_state_t;

    typedef enum logic [3:0] {
        MSHR_FREE,
        MSHR_WRITEBACK_PENDING,
        MSHR_WRITEBACK_ACTIVE,
        MSHR_REFILL_REQUEST,
        MSHR_REFILL_ISSUE,
        MSHR_REFILL_WAIT,
        MSHR_PREPARE,
        MSHR_APPLY,
        MSHR_INSTALL_PENDING,
        MSHR_ERROR_RESPONSE
    } mshr_state_t;

    typedef enum logic [1:0] {
        WB_IDLE,
        WB_ADDRESS,
        WB_DATA,
        WB_RESPONSE
    } writeback_state_t;

    // A maintenance request performs a full clean-and-invalidate operation.
    // Dirty lines are written to memory before they are invalidated.
    typedef enum logic [2:0] {
        FLUSH_IDLE,
        FLUSH_CHECK,
        FLUSH_ADDRESS,
        FLUSH_DATA,
        FLUSH_RESPONSE
    } flush_state_t;

endpackage
