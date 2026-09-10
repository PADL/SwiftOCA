# OCAPerfBench

Measures OCP.1 performance: the PDU and parameter codec, command round trips over
the local, TCP and UDP transports, the notification pipeline, and steady-state
throughput. It uses only the OCP.1 API, so the same source builds against any
revision of SwiftOCA. `compare.sh` builds two revisions with it and puts them side
by side.

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

1. checks it out into a temporary worktree,
2. copies in this branch's `PerfBench.swift` and adds an `OCAPerfBench` target to
   its `Package.swift`, so both revisions run the same harness source,
3. copies in this checkout's `Package.resolved`, so both build against the same
   dependencies, and
4. builds it in release mode.

It then runs the two binaries alternately, reversing the order every round, and
prints one line per benchmark: the median across rounds of each run's median time,
and the second ref's difference from the first. Every figure is ns/op, so lower is
better and a positive difference is a slowdown. The worktrees are removed when it
finishes.

| option | default | meaning |
|---|---|---|
| `-r rounds` | 5 | runs of each binary, per mode |
| `-s seconds` | 15 | length of each profile run |
| `-p port` | 56000 | first TCP port; UDP uses the next, and each end-to-end run moves on by 10 |

| environment | meaning |
|---|---|
| `SWIFT` | the swift command to build with, e.g. `SWIFT="swiftly run +6.3.3 swift"` |
| `PIN` | a prefix for each benchmark run, e.g. `PIN="taskset -c 2"` |

A full run with the defaults takes around 15 to 20 minutes, most of it building.

## What is measured

| benchmark | what it isolates |
|---|---|
| `encodePdu.*`, `decodePdu.*` | PDU framing and message coding, one message and eight batched, at 4 bytes, 1 KiB and 8 KiB of parameters |
| `encode.*`, `decode.*` | parameter marshaling as a command handler sees it: a float, a record, blobs of 64 B to 8 KiB |
| `roundtrip.local.*` | the coding and dispatch path with the transport taken out: the local transport hands whole PDUs across a channel |
| `roundtrip.tcp.*`, `roundtrip.udp.*` | the same exchanges over loopback TCP and UDP |
| `*.getDeviceName` | an empty command and a short response |
| `*.setLabel.1k`, `*.getLabel.1k` | a 1 KiB command with an empty response, and the reverse |
| `*.getDeviceName.late` | the first exchange repeated last: if it differs from `getDeviceName`, the difference is an ordering artefact, not the code |
| `notify.local.propertyChanged` | property changes on the device until the controller observes the last; intermediate values may be coalesced |
| `profile.local.getDeviceName` | the smallest local round trip in a loop for `-s` seconds, as ns per round trip |

## Getting stable numbers

Differences of a few percent are within run-to-run noise unless they repeat. To
keep the noise down:

- Use an otherwise idle machine, with nothing else building or indexing.
- On Linux, set the performance governor
  (`sudo cpupower frequency-set -g performance`) and pin the runs to one core
  (`PIN="taskset -c 2"`). The script prints the governor it saw.
- On a laptop, stay on mains power throughout: moving to battery can change clock
  speed mid-run.
- If a difference matters, run again with more rounds (`-r 9`) and check it holds.

## Running the binary directly

On the `perfbench` branch, which is `main` plus this benchmark:

```sh
swift build -c release --product OCAPerfBench
BENCH_ONLY=codec .build/release/OCAPerfBench
BENCH_ONLY=e2e BENCH_PORT=56000 .build/release/OCAPerfBench
BENCH_ONLY=notify .build/release/OCAPerfBench
BENCH_ONLY=profile BENCH_SECONDS=20 .build/release/OCAPerfBench
```

Without `BENCH_ONLY`, it runs the codec benchmarks, then the end-to-end ones. The
TCP and UDP round trips run only when `BENCH_PORT` is set. Each benchmark prints

```
RESULT <name> <min ns/op> <median ns/op> <max ns/op> <reps>
```

and profile mode prints `PROFILE <count> round trips in <seconds>s`.

To see where the time goes, profile a steady loop: on Linux,
`BENCH_ONLY=profile BENCH_SECONDS=30 perf record -g .build/release/OCAPerfBench`,
then `perf report`; on macOS, run the same loop and attach `sample <pid> 15`.

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
5. Report the table as printed, the two commits and the machine line above it,
   and every benchmark that differs by more than 5%, stating whether it is slower
   or faster in the second ref. Treat smaller differences as noise unless the
   user asks for a repeat run with more rounds.
