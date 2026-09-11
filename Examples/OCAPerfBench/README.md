# OCAPerfBench

Measures OCP.1 performance: the PDU and parameter codec, command round trips over
the local, TCP and UDP transports, the notification pipeline, steady-state
throughput over time, and latency from the moment of connection. It uses only the
OCP.1 API, so the same source builds against any revision of SwiftOCA.
`compare.sh` builds two revisions with it and puts them side by side.

It lives on the `perfbench` branch and is not meant to be merged: `compare.sh`
copies the harness into each revision it builds, so the revisions being compared
need not contain it.

## Comparing two revisions

From a checkout of the `perfbench` branch:

```sh
git fetch origin
Examples/OCAPerfBench/compare.sh origin/main origin/ocp2
```

Any two refs the checkout can resolve will do (branches, tags, commits). For each,
the script:

1. exports the commit (`git archive`) into a build directory of its own,
   `~/.cache/ocaperf/<commit>`, the first time it sees that commit,
2. copies in this branch's `PerfBench.swift` and adds an `OCAPerfBench` target to
   its `Package.swift`, so both revisions run the same harness source,
3. copies in this checkout's `Package.resolved`, so both build against the same
   dependencies, and
4. builds it in release mode with debug info (`-Xswiftc -g -Xcc -g`, which leaves
   the generated code unchanged), from scratch the first time, then incrementally.

Files are copied in only when their contents differ, so a later run of the same
commit rebuilds only what changed, usually nothing, and takes seconds. A branch
that moves, or is force-pushed, gets a new commit and so a new build directory,
built once. Old ones stay until you remove them (`rm -rf ~/.cache/ocaperf`).

It then runs the two binaries alternately, reversing the order every round, and
prints one line per benchmark: the median across rounds of each run's median, and
the second ref's difference from the first. Figures are ns/op, except
`*.maxrss.KiB` (peak memory in KiB); lower is better throughout, so a positive
difference is a slowdown.

| option | default | meaning |
|---|---|---|
| `-r rounds` | 5 | runs of each binary, per mode |
| `-s seconds` | 15 | length of each profile run |
| `-p port` | 56000 | first port; each run moves on by 100 |
| `-m modes` | `codec e2e profile` | which modes to run, from `codec e2e notify profile connect` |
| `-o dir` | none | keep the raw results (`results.tsv`) and any perf data here |

| environment | meaning |
|---|---|
| `SWIFT` | the swift command to build with, e.g. `SWIFT="swiftly run +6.3.3 swift"` |
| `BUILD_FLAGS` | extra flags for the release build (default `-Xswiftc -g -Xcc -g`: debug info, for `perf`) |
| `PIN` | a prefix for each benchmark run, e.g. `PIN="taskset -c 2,3"`; it does not pin the builds |
| `PERF` | if set, record each `profile` and `connect` run with `perf record` into the `-o` directory (default `./ocaperf-results`) |
| `PERF_ARGS` | options for `perf record` (default `--call-graph dwarf -F 999`) |
| `OCAPERF_CACHE` | where the per-commit build directories are kept (default `${XDG_CACHE_HOME:-~/.cache}/ocaperf`) |
| `BENCH_TRANSPORT` | transport for `profile` (default `local`) and `connect` (default `tcp`): `local`, `tcp` or `udp` |
| `BENCH_SLICE` | `profile`: seconds per reported slice (default 5) |
| `BENCH_CONNECTIONS` | `connect`: fresh connections per run (default 5) |
| `BENCH_BLOCKS` | `connect`: blocks timed on each connection (default 40) |
| `BENCH_BLOCK_SIZE` | `connect`: round trips per block (default 500) |

The first run of a commit builds it from scratch, which takes a few minutes; after
that, a run with the defaults takes around 10 minutes.

## What is measured

| benchmark | what it isolates |
|---|---|
| `encodePdu.*`, `decodePdu.*` | PDU framing and message coding, one message and eight batched, at 4 bytes, 1 KiB and 8 KiB of parameters |
| `encode.*`, `decode.*` | parameter marshaling as a command handler sees it: a float, a record, blobs of 64 B to 8 KiB |
| `roundtrip.local.*` | the coding and dispatch path with the transport taken out: the local transport hands whole PDUs across a channel |
| `roundtrip.tcp.*`, `roundtrip.udp.*` | the same exchanges over loopback TCP and UDP |
| `*.getDeviceName` | an empty command and a short response |
| `*.setLabel.1k`, `*.getLabel.1k` | a 1 KiB command with an empty response, and the reverse |
| `*.getDeviceName.late` | the first exchange repeated last: if it differs from `getDeviceName`, something in the connection's early life costs more |
| `notify.local.propertyChanged` | property changes on the device until the controller observes the last; intermediate values may be coalesced |
| `profile.<transport>.getDeviceName` | the smallest round trip in a loop for `-s` seconds, as ns per round trip |
| `profile.<transport>.tNNNNs` | the same loop, slice by slice (`BENCH_SLICE` seconds each): a rising series means a cost that grows with the number of requests |
| `profile.<transport>.maxrss.KiB` | peak resident memory at the end of the loop |
| `connect.<transport>.blockNNN` | round-trip time in consecutive blocks from the moment of connection, with no warm-up, across `BENCH_CONNECTIONS` fresh connections |
| `connect.<transport>.firstblock.cNN` | the first block of each connection: if only `c01` is slow, the early cost is paid once per process; if every connection's is, per connection |

## Getting stable numbers

Differences of a few percent are within run-to-run noise unless they repeat. To
keep the noise down:

- Use an otherwise idle machine, with nothing else building or indexing.
- On Linux, set the performance governor
  (`sudo cpupower frequency-set -g performance`). The script prints the governor it
  saw.
- Pin the runs: `PIN="taskset -c 2"` puts controller and device on one core, which
  measures the total CPU work of an exchange; `PIN="taskset -c 2,3"` gives them a
  core each, which is closer to real use. Choose two physical cores sharing a cache,
  not hyperthread siblings and not CPU 0 (see `lscpu -e=CPU,CORE,SOCKET,NODE,L3`).
  Set `PIN` rather than running the script under `taskset`: that would pin the
  builds as well, and the script warns if it finds itself pinned.
- On a laptop, stay on mains power throughout: moving to battery can change clock
  speed mid-run.
- If a difference matters, run again with more rounds (`-r 9`) and check it holds.

## Investigating a difference

Whether a steady-state cost grows over time, and peak memory:

```sh
BENCH_SLICE=10 Examples/OCAPerfBench/compare.sh -m profile -s 120 -r 3 origin/main origin/ocp2
```

How long the first exchanges on a connection cost more, and whether every
connection pays it:

```sh
BENCH_TRANSPORT=tcp Examples/OCAPerfBench/compare.sh -m connect -r 5 origin/main origin/ocp2
```

Where the time goes, with `perf`:

```sh
PERF=1 Examples/OCAPerfBench/compare.sh -m profile -s 30 -r 1 -o perf-profile origin/main origin/ocp2
perf diff perf-profile/perf-a-profile-1.data perf-profile/perf-b-profile-1.data |
  swift demangle --simplified | less
perf report -i perf-profile/perf-b-profile-1.data --no-children | swift demangle --simplified | less
```

The same works for `-m connect`, which records mostly the early life of each
connection. The binaries stay in their build directories, and `perf record` also
keeps copies in its build-id cache (`~/.debug`), so reports resolve symbols later.
If `perf` refuses to record, allow it with `sudo sysctl kernel.perf_event_paranoid=1`.

Both revisions are optimised builds with debug info, so `perf` names functions,
including inlined ones, and has line numbers. Recording uses DWARF call graphs,
since optimised Swift code need not keep frame pointers; that makes the data files
large, hence the lower sampling rate (`-F 999`). To confirm a binary has debug info:
`readelf -S ~/.cache/ocaperf/<commit>/.build/release/OCAPerfBench | grep debug_info`.

## Running the binary directly

On the `perfbench` branch, which is `main` plus this benchmark:

```sh
swift build -c release -Xswiftc -g -Xcc -g --product OCAPerfBench
BENCH_ONLY=codec .build/release/OCAPerfBench
BENCH_ONLY=e2e BENCH_PORT=56000 .build/release/OCAPerfBench
BENCH_ONLY=notify .build/release/OCAPerfBench
BENCH_ONLY=profile BENCH_SECONDS=20 .build/release/OCAPerfBench
BENCH_ONLY=profile BENCH_TRANSPORT=tcp BENCH_PORT=56000 .build/release/OCAPerfBench
BENCH_ONLY=connect BENCH_PORT=56000 .build/release/OCAPerfBench
```

Without `BENCH_ONLY`, it runs the codec benchmarks, then the end-to-end ones. The
TCP and UDP round trips run only when `BENCH_PORT` is set. Each benchmark prints

```
RESULT <name> <min> <median> <max> <samples>
```

and profile mode also prints `PROFILE <count> round trips in <seconds>s <transport>`.

## Instructions for an agent

To compare the OCP.1 performance of two revisions on this machine:

1. In a SwiftOCA checkout, run `git fetch origin` and `git checkout perfbench`
   (or `git checkout -b perfbench origin/perfbench` the first time).
2. Check the machine is idle, and on Linux that the CPU governor is
   `performance` if you are allowed to set it.
3. Run
   `Examples/OCAPerfBench/compare.sh -r 5 origin/main origin/ocp2 | tee perf-compare.txt`,
   substituting the refs you were asked to compare, and adding `SWIFT=...` if the
   default `swift` is not the toolchain to use.
4. If either build fails, stop and report the first error. Do not change code.
5. Report the table as printed, the two commits and the machine lines above it,
   and every benchmark that differs by more than 5%, stating whether it is slower
   or faster in the second ref. Treat smaller differences as noise unless the
   user asks for a repeat run with more rounds.
6. Run the commands under "Investigating a difference" only if asked to.
