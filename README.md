# Phase 4: Pipelined Write-Back Cache with AXI4

Phase 4 combines three major upgrades to the Phase 3 cache:

1. dirty-victim eviction and writeback,
2. a registered two-stage cache lookup,
3. AXI4 incrementing bursts for refill and writeback.

The cache remains blocking: one CPU request owns the cache until its response
is accepted. Non-blocking behavior begins in Phase 5.

## Configuration

- 32-bit CPU addresses and data
- 32-byte cache lines
- 64 sets, 2 ways per set
- 4 KiB data capacity
- LRU replacement
- write-back and write-allocate policy
- byte-enabled stores
- 32-bit AXI4 data bus
- 8 AXI beats per cache line
- `ARLEN/AWLEN = 7`, `ARSIZE/AWSIZE = 2`, incrementing bursts

The standalone educational interface includes the AXI4 `AR/R` and `AW/W/B`
channels needed by this cache. IDs and optional protection/cache/QoS signals
are omitted because Phase 4 permits only one memory transaction at a time.

## Lookup Pipeline

```text
Stage 0: accept CPU request and register both indexed ways
Stage 1: compare both tags, select the hit way, and process hit/miss
```

The registered lookup separates array access from tag comparison. Because this
phase is still blocking, it improves structure and timing boundaries rather
than accepting a new request every cycle.

## Miss Sequences

Clean or invalid victim:

```text
LOOKUP -> REFILL_AR -> REFILL_R -> INSTALL -> REPLAY_READ -> LOOKUP
```

Dirty victim:

```text
LOOKUP
  -> WRITEBACK_AW
  -> WRITEBACK_W (8 beats)
  -> WRITEBACK_B
  -> REFILL_AR
  -> REFILL_R (8 beats)
  -> INSTALL
  -> REPLAY_READ
  -> LOOKUP
```

The victim address is reconstructed from its stored tag, the request set index,
and a zero line offset. The complete victim line is saved before AXI writeback.

## Files

```text
l1d-cache-phase4-axi/
|-- README.md
|-- rtl/
|   |-- cache_pkg.sv
|   `-- l1d_cache.sv
`-- tb/
    |-- axi_memory_model.sv
    `-- tb_l1d_cache.sv
```

## ModelSim/Questa GUI

Compile in this order:

1. `rtl/cache_pkg.sv`
2. `rtl/l1d_cache.sv`
3. `tb/axi_memory_model.sv`
4. `tb/tb_l1d_cache.sv`

Simulate `tb_l1d_cache` and select **Run-All**.

Expected final message:

```text
ALL PHASE 4 PIPELINE, WRITEBACK AND AXI TESTS PASSED
```

## Directed Verification

The testbench checks:

- cold AXI refill,
- store hit and read-after-write,
- clean replacement,
- dirty-victim writeback before refill,
- eight read and write beats per line,
- aligned AXI addresses and correct burst fields,
- correct `RLAST` and `WLAST` positions,
- reloading data previously written back to memory,
- masked byte and halfword stores,
- store-miss write allocation and replay,
- one response for every accepted CPU request.

## Consolidated Remaining Plan

- **Phase 5:** one MSHR, decoupled miss handling, hit-under-miss.
- **Phase 6:** multiple MSHRs, miss-under-miss, merging, set-conflict and
  concurrency safety.
- **Phase 7:** ordering, backpressure, arbitration, replay/wakeup, maintenance,
  error handling, assertions, randomized verification and coverage.
