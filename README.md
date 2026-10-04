# Phase 7: Completed L1D Cache Control Design

This phase keeps the Phase 6 non-blocking data path and finishes the main
design-side control features: fair arbitration, AXI error handling, safe abort
of failed misses, and a full-cache clean-and-invalidate operation.

The emphasis is RTL design. The testbench is intentionally directed and small;
random testing, coverage, and a large assertion suite are left for a later DV
exercise.

## Configuration

- 32-bit CPU address and data
- 32-byte cache lines
- 64 sets, 2 ways: 4 KiB of cache-line data
- write-back and write-allocate
- byte-enabled stores
- four MSHRs, four ordered requests per MSHR
- hit-under-miss, miss-under-miss, and same-line merging
- 16-entry response FIFO
- 32-bit AXI4 data bus, eight beats per cache line
- AXI IDs identify the owning MSHR

## What Phase 7 Adds

### 1. Fair round-robin arbitration

Phase 6 always searched MSHRs from entry zero. Phase 7 remembers the entry
after each winner and begins the next search there.

Round-robin selection is used for:

- dirty-victim writeback,
- AXI refill-address issue,
- completed-request response/apply,
- cache-line installation.

The response side also alternates priority when a normal cache hit and an MSHR
response are ready together. This prevents one continuously active source from
starving the other.

### 2. AXI error handling

`cpu_rsp_error` is carried through the response FIFO with the original CPU
request ID.

On a refill read error (`RRESP != OKAY`):

1. the cache consumes and discards the refill,
2. the partially received line is never installed,
3. every CPU request merged into that MSHR receives an error response,
4. the reserved victim way is released,
5. the old victim line remains unchanged.

On a dirty-victim writeback error (`BRESP != OKAY`), the miss is aborted in the
same way. The dirty victim is preserved because losing it would lose the only
up-to-date copy of the data.

An early or missing `RLAST` is also treated as a failed refill, so a partial line
cannot become valid cache data.

### 3. Full-cache flush

The maintenance interface is:

```systemverilog
input  logic flush_valid;
output logic flush_ready;
output logic flush_done;
output logic flush_error;
```

The request uses a ready/valid handshake. Holding `flush_valid` high blocks new
CPU requests and allows existing MSHRs and queued CPU responses to drain. Once
`flush_ready` is high, the controller accepts the request and scans every set
and way.

- Invalid entry: skip it.
- Clean valid entry: invalidate it immediately.
- Dirty valid entry: write the full line through AXI, then invalidate it only
  after an OKAY write response.

`flush_done` pulses for one cycle. `flush_error` is high with that pulse if a
dirty-line writeback failed. On failure, that dirty line remains valid and
dirty, so software can retry the flush without losing data.

### 4. Control safety retained from Phase 6

- One active MSHR owns each missing line.
- Requests to the same missing line merge in arrival order.
- A victim way cannot be selected by another MSHR while reserved.
- A request for a dirty victim's old address waits until writeback is complete.
- AXI read responses use `RID` to reach the correct refill buffer.
- AXI write-data bursts remain serialized because AXI4 has no `WID`.
- Independent requests may finish out of order; the CPU ID identifies each
  response.

## Main state flows

Successful miss:

```text
WRITEBACK_PENDING (only for a dirty victim)
  -> REFILL_REQUEST -> REFILL_WAIT -> PREPARE
  -> APPLY merged operations -> INSTALL_PENDING -> FREE
```

Failed miss:

```text
AXI read/write error
  -> ERROR_RESPONSE for every merged CPU request
  -> release reservation without changing victim -> FREE
```

Flush:

```text
FLUSH_CHECK
  -> clean line: invalidate and advance
  -> dirty line: ADDRESS -> DATA -> RESPONSE -> invalidate and advance
  -> final set/way: flush_done
```

## Repository

```text
l1d-cache-phase7-control/
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

Create a project and compile as SystemVerilog in this order:

1. `rtl/cache_pkg.sv`
2. `rtl/response_fifo.sv`
3. `rtl/l1d_cache.sv`
4. `tb/axi_memory_model.sv`
5. `tb/tb_l1d_cache.sv`

Start simulation with `tb_l1d_cache` as the top-level and select **Run >
Run -All**.

Expected final message:

```text
ALL PHASE 7 DESIGN-CONTROL TESTS PASSED
```

Useful wave signals:

- `dut.lookup_state_q`
- `dut.mshr_valid_q`, `dut.mshr_state_q`
- `dut.writeback_state_q`
- `dut.flush_state_q`, `dut.flush_set_q`, `dut.flush_way_q`
- `dut.writeback_rr_q`, `dut.ar_rr_q`, `dut.apply_rr_q`, `dut.install_rr_q`
- `cpu_rsp_error`, `flush_done`, `flush_error`
- AXI `ARID/RID`, `AWID/BID`, `RRESP`, and `BRESP`

## Small directed testbench

The included testbench covers only the design paths introduced or retained in
this phase:

1. miss followed by a same-line hit,
2. four independent outstanding misses,
3. AXI read error returned to the CPU and a successful retry,
4. successful dirty-line flush and later refill,
5. failed flush preserving dirty cache data, followed by a successful retry.

## Deliberate limits

This is a practical single-core educational L1D cache, not a complete CPU
memory subsystem. It does not implement coherence, atomics, virtual address
translation, ECC, or a load/store queue. Independent requests can complete out
of order, so an in-order CPU must retire responses by request ID or place an
ordering unit in front of the cache when architectural ordering requires it.
