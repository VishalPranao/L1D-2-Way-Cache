# Phase 6: Multi-MSHR Non-Blocking L1D Cache

Phase 6 builds on the Phase 5 one-MSHR cache and adds true miss-under-miss
execution. Four independent misses can own MSHRs simultaneously, several AXI
read requests may be outstanding, and responses are routed with AXI IDs.

## Configuration

- 32-bit CPU addresses and data
- 4-bit CPU request/response IDs
- 32-byte cache lines
- 64 sets and 2 ways per set
- 4 KiB data capacity
- write-back and write-allocate policy
- byte-enabled stores
- four MSHRs
- four dependent requests per MSHR
- 16-entry CPU response FIFO
- 32-bit AXI4 data bus and eight beats per line
- 2-bit AXI IDs, with each AXI ID equal to its MSHR index

The concurrency parameters are in `rtl/cache_pkg.sv`:

```systemverilog
parameter int NUM_MSHRS      = 4;
parameter int MERGE_DEPTH    = 4;
parameter int RESPONSE_DEPTH = 16;
```

## Major Changes from Phase 5

| Function | Phase 5 | Phase 6 |
| --- | --- | --- |
| MSHRs | One | Four |
| Additional independent miss | Waits | Allocates another MSHR |
| Same-line secondary miss | Waits and retries | Merges into the existing MSHR |
| AXI reads | One outstanding | Several outstanding with `ARID/RID` |
| CPU responses | One response register | 16-entry response FIFO |
| Victim protection | One invalidated victim | Explicit per-set/per-way reservations |
| Refill completion | One possible installer | Installation arbiter |
| Dirty writeback | One miss engine | Several pending; one serialized W burst at a time |

## Request Decision Order

For each lookup, the controller follows this order:

1. Cache hit: return or modify the cached word.
2. Active MSHR line match: append the request to that MSHR's merge queue.
3. Reserved-victim address match: wait so stale dirty-victim memory cannot be
   read before writeback.
4. New miss: select an unreserved victim and allocate a free MSHR.
5. No resource: refresh the array snapshot and retry.

This ordering prevents duplicate MSHRs for one line and prevents two MSHRs from
reserving the same physical cache way.

## Same-Line Merging

Each MSHR holds as many as four ordered dependent requests. A request record
contains its CPU ID, load/store type, word index, store data, and byte strobes.

After refill:

```text
MSHR_PREPARE
  -> MSHR_APPLY request 0
  -> MSHR_APPLY request 1
  -> ...
  -> MSHR_INSTALL_PENDING
  -> MSHR_FREE
```

Operations are applied in arrival order. Therefore, a merged load following a
merged store to the same word observes the store-modified data. At least one
effective store marks the installed line dirty.

## AXI Read Concurrency

The read-address arbiter selects an MSHR in `MSHR_REFILL_REQUEST`, latches its
index, and sends:

```text
ARID   = MSHR index
ARADDR = requested line address
ARLEN  = 7
```

The return path uses `RID` to choose the correct refill buffer and per-MSHR beat
counter. Different IDs may complete out of request order.

The supplied memory model accepts one outstanding read per AXI ID. It returns
complete bursts without beat interleaving, but deliberately gives higher IDs a
shorter initial latency so the testbench observes out-of-order completion.

## Dirty Writeback

Several MSHRs may wait in `MSHR_WRITEBACK_PENDING`. The writeback arbiter grants
one entry and sends its complete burst through `AW/W/B` before granting another.
This is intentional because AXI4 has no `WID`; write-data bursts are not mixed.

Independent clean-miss AXI reads can still proceed while a dirty writeback is
active.

## Set and Way Conflict Safety

`reserved_array[set][way]` records ways owned by MSHRs.

- A reserved way cannot hit.
- Victim selection ignores reserved ways.
- Two misses to the two different ways of one set may proceed.
- A third different-line miss to that two-way set waits.
- A request for an evicted victim address waits until the owning MSHR finishes.
- The install arbiter writes only one completed refill into the arrays per
  cycle.

## Files

```text
l1d-cache-phase6-multi-mshr/
|-- README.md
|-- rtl/
|   |-- cache_pkg.sv
|   |-- response_fifo.sv
|   `-- l1d_cache.sv
`-- tb/
    |-- axi_memory_model.sv
    `-- tb_l1d_cache.sv
```

## ModelSim/Questa GUI

Create a project and compile in this order:

1. `rtl/cache_pkg.sv`
2. `rtl/response_fifo.sv`
3. `rtl/l1d_cache.sv`
4. `tb/axi_memory_model.sv`
5. `tb/tb_l1d_cache.sv`

Simulate `tb_l1d_cache`, then choose **Run > Run -All**.

Expected completion message:

```text
ALL PHASE 6 MULTI-MSHR AND MISS-UNDER-MISS TESTS PASSED
```

Useful Wave-window signals include:

- `dut.lookup_state_q`
- `dut.mshr_valid_q`
- `dut.mshr_state_q`
- `dut.mshr_line_addr_q`
- `dut.mshr_req_count_q`
- `dut.reserved_array`
- `dut.writeback_state_q`
- `dut.ar_hold_valid_q` and `dut.ar_hold_index_q`
- `dut.response_queue.count_q`
- CPU request and response IDs
- AXI `ARID`, `RID`, `AWID`, and `BID`

## Directed Verification

The testbench checks:

- two independent concurrent misses,
- a cache hit under multiple misses,
- out-of-order AXI completion and CPU response IDs,
- three same-line loads sharing one refill,
- store-miss plus load merging with correct operation ordering,
- all four MSHRs occupied and a fifth miss retrying,
- two reserved ways and a third same-set miss waiting,
- dirty writeback concurrent with an independent clean refill,
- dirty victim data reaching lower memory,
- response FIFO payload stability under CPU backpressure,
- correct burst length, alignment, IDs, `RLAST`, and `WLAST`,
- one response for every accepted CPU request.

The RTL also contains simulation assertions for duplicate line ownership,
duplicate victim reservation, merge queue overflow, AXI response errors, and
incorrect burst termination.

## Intentional Phase 6 Limits

- Four MSHRs and four merged requests per line are fixed educational defaults.
- AXI writebacks are serialized.
- The lookup pipe holds one unresolved request when all resources are busy.
- Global load/store ordering, fences, atomics, cache flush/invalidate commands,
  AXI error recovery, and coherence are reserved for Phase 7.

## Remaining Phase

Phase 7 completes the control plane with architectural ordering rules,
maintenance operations, error recovery, fairness improvements, stronger
assertions, randomized verification, functional coverage, and final corner-case
handling.
