# Selected-file watching benchmark

Measured November 16, 2026. This is a **release-optimized core/storage comparison**,
not a desktop UI benchmark. Production cache/save behavior was not changed for
these measurements. The existing Scribbit app was not launched, restarted or
otherwise interacted with.

## Conclusion

For the stated mostly-read-only workflow, **keep the watched snapshot design**:
it removes repeated coordinated full-content reads and saves roughly 0.93–1.16 ms
per quiet open/close roundtrip at the four ordinary sizes on this machine.
The storage speedup is real, but the absolute saving is small relative to an
entire animated UI interaction; perceived UI benefit has not been measured.

The tradeoff is not free. Own saves, external edits and unrelated sibling churn
all caused rereads here. Those misses generally had worse timings with watching
in the ordinary-size cases, sometimes substantially worse. Notification timing,
coordination services and scheduling contribute noise; this is not evidence of a
fixed universal miss penalty. Do not optimize own-save publication simply to
improve these numbers without preserving save/race correctness.

At 64 MiB, cached session work still took about 48 ms median, and the isolated
process retained about 202 MiB resident after warmup in **both** modes. Accepting
64 MiB source is neither a 64 MiB process budget nor evidence of smooth editing.
Native layout/undo/preview at that size remain unmeasured.

## Reproduce

Run from the repository root on macOS with Swift/Command Line Tools available:

```sh
Scripts/benchmark-file-watching.sh --quick
OUTPUT="$PWD/build/file-watching-benchmarks-final" Scripts/benchmark-file-watching.sh --stress
```

Without flags, the script measures the four ordinary sizes. `--stress` adds
8/64 MiB with fewer samples. `--quick` is a smoke run, not the reported dataset.
The shell compiles production NoteStore, NoteSession and WatchedNoteStore sources
plus Scripts/FileWatchingBenchmark.swift directly using swiftc -O, Swift 5 mode,
the current architecture and macOS 14 deployment target. No package dependency,
GUI, test app, network request or runtime download is involved. File coordination
may require approved host access in a restricted execution sandbox; do not bypass
NSFileCoordinator on failure. Target size/limit and source code are identical in
both modes, including the 64 MiB acceptance ceiling. The 8/64 MiB controls are
not executable historical prechange builds, which accepted only 2 MiB.

Outputs live below the selected ignored build directory:

| Output | Contents |
| --- | --- |
| environment.json | OS, CPU, RAM, toolchain, commit/dirty state, compiler flags and SHA-256 of measured production/harness sources |
| results.jsonl | Every cell's samples, median/p95, counts, CPU and RSS snapshots |
| summary.md | Full pairwise latency table generated from those results |
| file-watching-benchmark | Optimized executable |
| fixtures/ | Parent for per-cell temporary directories, removed after each subprocess |

The deterministic executable self-test checks nearest-rank median/p95 calculation,
fixture correctness, cache reuse, save invalidation and external replacement.
The driver verifies result/sample shapes, one backing read per measured disk or
forced-miss operation, and read-count bounds. There are **no timing thresholds**
in these checks. A preliminary run stopped on an overly strict quiet-hit
assertion at 64 MiB; the final harness records conservative quiet misses instead
of incorrectly treating asynchronous invalidation as a benchmark failure.

## Environment and method

| Item | Recorded value / scope |
| --- | --- |
| Hardware | Apple M4 Max, arm64, 64 GiB physical RAM |
| OS | macOS 26.7.3 |
| Compiler | Apple Swift 6.3.3, -O, -swift-version 5, arm64-apple-macosx14.0 |
| Production commit | 0ecf94053983df1dbab40885fa99f2c09dec3c1e |
| Working tree | Dirty only because benchmark scripts/report were being added; production cache/save sources unchanged |
| Ordinary sizes | 4 KiB, 64 KiB, 1 MiB, 2 MiB |
| Ordinary iterations | Quiet: 100 measured, 5 warmup; each mutation case: 30 measured, 5 warmup |
| Stress sizes | 8/64 MiB: 8 measured, 2 warmup per case; p95 is the largest of eight samples, not a robust tail estimate |
| Process isolation | Fresh process per mode/size/layer/scenario; pair order alternates by size, not randomized per iteration |
| Fixture | Valid ASCII UTF-8, streamed creation in at most 64 KiB chunks; sentinel byte toggled for edits; no user files |
| Filesystem | Warm/uncontrolled OS page cache after fixture creation; **not cold physical-disk I/O** |
| Thermal / power | Every result reported nominal thermal state and Low Power Mode disabled; background activity was not controlled |
| Wall timing | DispatchTime monotonic clock, microseconds; nearest-rank median and p95 |
| CPU timing | getrusage process user+system delta around each operation; excludes other processes/coordination daemon CPU and is coarse for microsecond hits |
| RSS | mach_task_basic_info resident_size after autoreleasepool teardown; allocator retention/runtime state included, not cache allocation attribution |

Each measured operation uses the same core APIs as production's serial worker,
but runs synchronously in an isolated CLI process. Main-actor scheduling,
bookmark resolution, security-scope acquisition, selection clamping, SwiftUI,
AppKit layout/undo/preview and animation are not included.

| Layer | Timed operation |
| --- | --- |
| store | One NoteStore.read, plus constant-size count/sentinel verification; no source decode beyond DiskNoteStore's normal UTF-8 validation |
| session | NoteSession.open + SHA-256 of decoded UTF-8 source, then clean NoteSession.close + SHA-256 of retained outgoing source, matching both worker fingerprints |

The session total includes close's normal dirty-byte comparison and teardown.
Open-only times stop after the open fingerprint. The harness consumes results to
prevent discarded work. It intentionally does **not** include editor/view work.

| Scenario | Untimed preparation before the measured reopen |
| --- | --- |
| quiet | Already primed/closed selected note; no deliberate external mutation |
| save | Read baseline and save a same-size edit through that mode's real store; measures the following reopen, **not save latency** |
| external | Atomic external same-size replacement, then reopen |
| sibling | Atomic write of an unrelated file in the selected note's directory, then reopen |

Mutation cases pause 20 ms outside the timing before reopening. That is spacing,
not a promise that an asynchronous event has arrived. Actual backing read counts
are reported. Counts refer to wrapper-visible DiskNoteStore.read calls; they do
not instrument DiskNoteStore.save's private conflict-validation reread or physical
device reads. Fixture writes, preparation/saves, warmups, idle waits and output
serialization are outside reported operation wall/CPU samples.

## Primary result: quiet read-only session roundtrip

Times below are milliseconds, including both worker fingerprints and clean close.

| Size | Disk median / p95 ms | Watched median / p95 ms | Median saving ms | Watched backing reads |
| --- | ---: | ---: | ---: | ---: |
| 4 KiB | 1.181 / 2.413 | 0.019 / 0.040 | 1.161 | 0/100 |
| 64 KiB | 1.185 / 2.098 | 0.119 / 0.292 | 1.066 | 0/100 |
| 1 MiB | 1.713 / 2.656 | 0.779 / 0.853 | 0.933 | 0/100 |
| 2 MiB | 2.443 / 3.909 | 1.502 / 2.993 | 0.941 | 0/100 |
| 8 MiB | 9.184 / 22.612 | 7.787 / 16.858 | 1.397 | 0/8 |
| 64 MiB | 52.109 / 87.022 | 48.365 / 53.834 | 3.745 | 1/8 |

All ordinary quiet watched cases avoided 100/100 backing reads. The 64 MiB
session case conservatively reread once in eight samples even without an
intentional mutation. The benchmark does not establish the event's cause; it
must not be described as a guaranteed zero-read path.

### Open-only latency and process CPU

CPU is for the full session roundtrip, not just opening. Microseconds:

| Size | Disk open median / p95 us | Watched open median / p95 us | Disk roundtrip CPU median / p95 us | Watched CPU median / p95 us |
| --- | ---: | ---: | ---: | ---: |
| 4 KiB | 1176.42 / 2406.00 | 12.33 / 26.83 | 245 / 550 | 20 / 42 |
| 64 KiB | 1157.21 / 2070.83 | 59.50 / 174.33 | 297 / 622 | 120 / 294 |
| 1 MiB | 1318.25 / 2056.29 | 385.71 / 424.79 | 1063 / 1724 | 778 / 849 |
| 2 MiB | 1717.79 / 2733.88 | 740.71 / 1484.29 | 1790 / 2907 | 1503 / 2994 |
| 8 MiB | 5679.38 / 16141.88 | 4019.12 / 8085.96 | 8170 / 19424 | 7788 / 16691 |
| 64 MiB | 29145.25 / 59787.21 | 23775.88 / 29508.25 | 51109 / 83715 | 48341 / 52884 |

A store-only hit took about 1–2 us, but the cached session roundtrip grew from
19 us at 4 KiB to 1.50 ms at 2 MiB and 48.36 ms at 64 MiB. UTF-8 decoding,
reencoding/dirty comparison and two SHA-256 passes remain. Treat the stress
percentiles cautiously; the 8 MiB case also showed considerable sample variation.

## Hidden-process memory and idle CPU

These are isolated **session benchmark process** snapshots, not Scribbit's UI
process memory. Each process stayed closed/idle for approximately one second
after warmup; CPU totals below cover that interval only. No recurring workload
or directory churn was injected during it. Small differences are within sampling
and runtime noise, not evidence of better/worse steady-state energy use.

| Size | Disk warmed hidden RSS MiB | Watched warmed hidden RSS MiB | Disk / watched CPU us over ~1 s idle |
| --- | ---: | ---: | ---: |
| 4 KiB | 10.08 | 9.98 | 19 / 24 |
| 64 KiB | 10.38 | 10.25 | 14 / 30 |
| 1 MiB | 13.14 | 13.08 | 18 / 11 |
| 2 MiB | 16.17 | 16.12 | 23 / 16 |
| 8 MiB | 34.06 | 34.08 | 22 / 27 |
| 64 MiB | 202.06 | 202.20 | 18 / 13 |

RSS does **not** isolate the retained Data snapshot: both modes warm runtime and
allocator state, and freed allocations can remain resident. Similar RSS is not
proof that caching costs no memory. The logical policy still retains up to one
selected source snapshot while hidden. The roughly 202 MiB result at 64 MiB in
both processes demonstrates why a source bound is not a process-memory bound.
No whole-app memory, long-duration idle CPU, energy impact, memory-pressure,
editor latency, caret restoration, animation or UI responsiveness was measured.

## All workloads: store versus session

Wall times in microseconds, median / p95. Negative cache benefit is visible as
larger watched numbers; do not dismiss measured regressions as a guaranteed
zero-cost miss. Some cells vary sharply in the other direction too, so precision
about a universal penalty requires repeated/interleaved profiling on a controlled
machine. In this run every watched own-save, external and sibling case performed
a backing read for every measured reopening. Sibling directory traffic therefore
erased the read-only cache advantage despite unchanged note contents.

| Size | Layer | Scenario | Disk median / p95 us | Watched median / p95 us | Watched reads |
| --- | --- | --- | ---: | ---: | ---: |
| 4 KiB | store | quiet | 1093.12 / 1231.62 | 1.25 / 1.67 | 0/100 |
| 4 KiB | store | save | 1868.75 / 2364.42 | 2054.62 / 2960.21 | 30/30 |
| 4 KiB | store | external | 4299.50 / 8813.17 | 5046.33 / 5672.71 | 30/30 |
| 4 KiB | store | sibling | 4700.71 / 5888.08 | 4305.00 / 5515.21 | 30/30 |
| 4 KiB | session | quiet | 1180.58 / 2413.12 | 19.17 / 40.42 | 0/100 |
| 4 KiB | session | save | 1366.67 / 1662.25 | 2070.17 / 3504.58 | 30/30 |
| 4 KiB | session | external | 4565.33 / 6390.00 | 5131.33 / 6454.12 | 30/30 |
| 4 KiB | session | sibling | 3249.71 / 5224.29 | 5004.17 / 7044.71 | 30/30 |
| 64 KiB | store | quiet | 1189.75 / 1463.38 | 2.25 / 2.62 | 0/100 |
| 64 KiB | store | save | 2254.17 / 2692.79 | 3155.54 / 4827.75 | 30/30 |
| 64 KiB | store | external | 4804.83 / 5910.38 | 4950.12 / 5704.67 | 30/30 |
| 64 KiB | store | sibling | 4449.88 / 5140.17 | 4824.17 / 5899.62 | 30/30 |
| 64 KiB | session | quiet | 1185.38 / 2097.88 | 119.08 / 292.00 | 0/100 |
| 64 KiB | session | save | 2083.88 / 2685.08 | 3266.00 / 4638.96 | 30/30 |
| 64 KiB | session | external | 4295.29 / 6385.46 | 5179.17 / 6257.62 | 30/30 |
| 64 KiB | session | sibling | 1564.25 / 5131.50 | 4490.58 / 6084.21 | 30/30 |
| 1 MiB | store | quiet | 1200.25 / 1451.54 | 1.42 / 1.83 | 0/100 |
| 1 MiB | store | save | 1679.96 / 2457.00 | 2894.54 / 3876.58 | 30/30 |
| 1 MiB | store | external | 4696.75 / 5664.38 | 1542.42 / 1872.96 | 30/30 |
| 1 MiB | store | sibling | 4618.62 / 6036.38 | 5558.71 / 6464.88 | 30/30 |
| 1 MiB | session | quiet | 1712.62 / 2655.54 | 779.21 / 853.00 | 0/100 |
| 1 MiB | session | save | 3435.62 / 3933.42 | 4342.58 / 4743.25 | 30/30 |
| 1 MiB | session | external | 4918.00 / 6866.08 | 6948.00 / 8276.08 | 30/30 |
| 1 MiB | session | sibling | 5711.75 / 7633.33 | 6231.33 / 8669.92 | 30/30 |
| 2 MiB | store | quiet | 1186.08 / 1383.04 | 1.38 / 1.54 | 0/100 |
| 2 MiB | store | save | 2342.25 / 2735.04 | 2919.38 / 3301.62 | 30/30 |
| 2 MiB | store | external | 4253.88 / 7261.75 | 5955.33 / 7375.42 | 30/30 |
| 2 MiB | store | sibling | 1491.96 / 2401.17 | 1836.58 / 2761.50 | 30/30 |
| 2 MiB | session | quiet | 2443.50 / 3909.33 | 1502.33 / 2993.04 | 0/100 |
| 2 MiB | session | save | 4514.50 / 4957.92 | 5119.83 / 5521.21 | 30/30 |
| 2 MiB | session | external | 6457.79 / 7698.92 | 6483.21 / 8211.38 | 30/30 |
| 2 MiB | session | sibling | 6492.83 / 8988.88 | 7195.29 / 8699.71 | 30/30 |
| 8 MiB | store | quiet | 1916.46 / 2757.79 | 1.50 / 2.42 | 0/8 |
| 8 MiB | store | save | 3768.71 / 5068.42 | 4572.29 / 5281.96 | 8/8 |
| 8 MiB | store | external | 3792.33 / 4183.00 | 4096.04 / 4716.12 | 8/8 |
| 8 MiB | store | sibling | 1982.33 / 3383.08 | 2146.75 / 2472.12 | 8/8 |
| 8 MiB | session | quiet | 9184.33 / 22612.17 | 7787.46 / 16858.33 | 0/8 |
| 8 MiB | session | save | 10877.38 / 11734.12 | 11707.92 / 12807.38 | 8/8 |
| 8 MiB | session | external | 11070.54 / 11768.17 | 11155.79 / 11515.62 | 8/8 |
| 8 MiB | session | sibling | 11595.79 / 11975.96 | 11408.83 / 11823.71 | 8/8 |
| 64 MiB | store | quiet | 6905.50 / 7209.04 | 1.62 / 2.21 | 0/8 |
| 64 MiB | store | save | 14662.71 / 15046.88 | 14941.21 / 15788.42 | 8/8 |
| 64 MiB | store | external | 9523.04 / 11424.67 | 7724.50 / 9783.71 | 8/8 |
| 64 MiB | store | sibling | 10109.42 / 10737.62 | 10618.96 / 11829.46 | 8/8 |
| 64 MiB | session | quiet | 52109.38 / 87022.33 | 48364.75 / 53833.83 | 1/8 |
| 64 MiB | session | save | 63738.00 / 67358.67 | 63429.88 / 63904.04 | 8/8 |
| 64 MiB | session | external | 54445.92 / 54801.42 | 54442.04 / 58813.50 | 8/8 |
| 64 MiB | session | sibling | 54407.54 / 54803.33 | 54239.54 / 54469.04 | 8/8 |

## Recommendation and remaining work

1. Keep the current implementation for frequent read-only opening: the primary
   workload eliminates backing reads and shows a measurable warm-core benefit.
2. Preserve conservative own-save invalidation for now. It is the safe baseline;
   any future cache publication must account for concurrent writers rather than
   associating our bytes with another writer's post-save metadata.
3. Treat frequent sibling churn as an unfavorable workload. Profile that workload
   before proposing narrower invalidation; do not weaken replacement/delete safety
   merely to preserve benchmark hit rates.
4. Do not advertise 64 MiB as smoothly editable based on this report. With separate
   explicit GUI approval, use disposable notes to measure native layout, undo,
   preview, total RSS and UI latency. No such test has run here.
5. Repeat on the target machine under realistic use before assigning app-wide
   latency/CPU/RAM budgets. These warm-page-cache CLI results cannot establish
   cold storage performance, long-term energy use or perceived animation quality.
