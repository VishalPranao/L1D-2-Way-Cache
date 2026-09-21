# Phase 2: Two-Way Read-Only Blocking L1 Data Cache

This milestone upgrades the Phase 1 direct-mapped cache into a two-way
set-associative cache while keeping the controller blocking and read-only.

## Configuration

- 32-bit byte addresses
- 32-bit CPU load data
- 32-byte cache lines
- 64 sets
- 2 ways per set
- 4 KiB data capacity
- one LRU-victim bit per set
- one outstanding CPU request
- simplified whole-line memory refill interface

## Files

```text
l1d-cache-phase2-2way/
|-- README.md
|-- rtl/
|   |-- cache_pkg.sv
|   `-- l1d_cache.sv
`-- tb/
    |-- simple_memory.sv
    `-- tb_l1d_cache.sv
```

No simulation script is required. Add the four SystemVerilog files to a
ModelSim/Questa project and compile them in this order:

1. `rtl/cache_pkg.sv`
2. `rtl/l1d_cache.sv`
3. `tb/simple_memory.sv`
4. `tb/tb_l1d_cache.sv`

Start simulation using `tb_l1d_cache` as the top-level module and select
Run-All from the GUI.

## Tests

The directed testbench verifies:

1. A cold miss fills Way 0.
2. A same-set/different-tag line uses invalid Way 1.
3. Hits can be returned from both Way 0 and Way 1.
4. A third same-set line invokes LRU replacement.
5. The most recently used line survives replacement.
6. The LRU line misses after eviction.
7. Accesses to a different set do not disturb Set 0.
8. Every lower-memory request is 32-byte aligned.

Expected final message:

```text
ALL PHASE 2 TWO-WAY L1D CACHE TESTS PASSED
```

Stores, dirty bits, writeback, AXI, pipelining and MSHRs remain intentionally
out of scope for this phase.
