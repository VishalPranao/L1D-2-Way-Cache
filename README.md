# Phase 5: Non-Blocking L1D Cache with One MSHR

This phase builds directly on the Phase 4 pipelined, write-back AXI cache. It
adds one miss-status holding register (MSHR), separates lookup from miss
handling, and permits load or store hits to complete while one older miss is
being written back or refilled.

## Configuration

- 32-bit CPU addresses and data
- 4-bit CPU request/response IDs
- 32-byte cache lines
- 64 sets and 2 ways per set
- 4 KiB data capacity
- LRU replacement
- write-back and write-allocate policy
- byte-enabled stores
- one MSHR and one AXI memory transaction at a time
- 32-bit AXI4 data bus and eight beats per cache line

## What Changed from Phase 4

Phase 4 had one global blocking FSM. Once a miss occurred, that FSM stopped all
new CPU lookups until writeback, refill, install, and response were complete.

Phase 5 has two independent controllers:

1. The lookup controller accepts a request, reads both ways, compares tags, and
   completes cache hits.
2. The miss engine owns the single MSHR and performs dirty writeback, refill,
   and installation through AXI.

Because the controllers run concurrently, a younger hit can respond before the
older miss. `cpu_req_id` is copied to `cpu_rsp_id` so the CPU can identify these
out-of-order responses.

## One-MSHR Behavior

The MSHR stores the complete context of one miss:

- request ID, load/store type, write data, and byte strobes,
- requested line address, tag, set, and word index,
- selected victim way, victim address, and victim data,
- refill buffer and AXI beat counter.

At allocation, the selected victim way is invalidated immediately. Its complete
data is already snapshotted in the MSHR, so later hits cannot read stale victim
data or modify a line while it is being written back.

A store miss is merged directly into the completed refill buffer before the
line is installed. It does not replay through the lookup pipeline.

## Supported Concurrency

| Request while MSHR is busy | Phase 5 action |
| --- | --- |
| Hit in a non-reserved cache way | Complete normally; may respond before the miss |
| Store hit in a non-reserved way | Update bytes, set dirty, and respond |
| Request to the line being refilled | Wait, refresh array data after install, then hit |
| A different cache miss | Wait in `LOOKUP_WAIT_MSHR`, then retry after the MSHR frees |

The last row is intentionally not miss-under-miss. Multiple outstanding misses,
request merging, and multiple MSHRs belong to Phase 6.

## Controller Sequences

Lookup controller:

```text
LOOKUP_IDLE -> LOOKUP_COMPARE -> hit response
                               -> MSHR allocation
                               -> LOOKUP_WAIT_MSHR -> LOOKUP_REFRESH -> compare
```

Clean or invalid victim:

```text
MISS_IDLE -> MISS_REFILL_AR -> MISS_REFILL_R -> MISS_INSTALL -> MISS_IDLE
```

Dirty victim:

```text
MISS_IDLE
  -> MISS_WRITEBACK_AW
  -> MISS_WRITEBACK_W (8 beats)
  -> MISS_WRITEBACK_B
  -> MISS_REFILL_AR
  -> MISS_REFILL_R (8 beats)
  -> MISS_INSTALL
  -> MISS_IDLE
```

## Files

```text
l1d-cache-phase5-mshr/
|-- README.md
|-- rtl/
|   |-- cache_pkg.sv
|   `-- l1d_cache.sv
`-- tb/
    |-- axi_memory_model.sv
    `-- tb_l1d_cache.sv
```

## ModelSim/Questa GUI

Create a project and compile in this order:

1. `rtl/cache_pkg.sv`
2. `rtl/l1d_cache.sv`
3. `tb/axi_memory_model.sv`
4. `tb/tb_l1d_cache.sv`

Simulate `tb_l1d_cache`, then choose **Run > Run -All**.

Expected final message:

```text
ALL PHASE 5 ONE-MSHR AND HIT-UNDER-MISS TESTS PASSED
```

Useful internal signals to add to the Wave window:

- `dut.lookup_state_q`
- `dut.miss_state_q`
- `dut.mshr_valid_q`
- `dut.mshr_req_id_q`
- `dut.mshr_line_addr_q`
- `cpu_req_valid`, `cpu_req_ready`, and `cpu_req_id`
- `cpu_rsp_valid`, `cpu_rsp_ready`, and `cpu_rsp_id`
- all five AXI channel handshakes

## Directed Verification

The testbench checks:

- load hit under a clean miss with out-of-order response IDs,
- store hit under miss and read-after-write,
- a same-line request waiting and retrying after refill,
- a second miss waiting for the single MSHR,
- dirty victim writeback with a concurrent unrelated hit,
- victim writeback data reaching lower memory,
- direct masked-store merge into a refill line,
- exactly eight AXI beats per cache line,
- aligned AXI addresses and correct burst fields,
- stable CPU response payload under backpressure,
- one response for every accepted CPU request.

## Remaining Plan

- **Phase 6:** multiple MSHRs, miss-under-miss, same-line merging, AXI IDs,
  wakeup/replay, and set-conflict safety.
- **Phase 7:** complete corner-case control, ordering rules, maintenance,
  error handling, assertions, randomized verification, and coverage.
