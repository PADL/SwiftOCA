#!/bin/sh
#
# Copyright (c) 2026 PADL Software Pty Ltd
#
# Licensed under the Apache License, Version 2.0 (the License);
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an 'AS IS' BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Compares the OCP.1 performance of two revisions of SwiftOCA with OCAPerfBench.
#
#   Examples/OCAPerfBench/compare.sh [-r rounds] [-s seconds] [-p port]
#                                    [-m modes] [-o dir] ref-a ref-b
#
# Each revision is exported into a build directory of its own, kept between runs
# and keyed by commit, given this directory's PerfBench.swift and an OCAPerfBench
# target (so the refs need not contain the benchmark, and both build the same harness
# source) and this checkout's Package.resolved (so both build against the same
# dependencies), and built in release mode: from scratch the first time, then
# incrementally, so a later run of the same commit rebuilds only what changed. The
# two binaries then run alternately, reversing the order each round, so that drift
# in load or clock speed falls on both alike. For each benchmark it prints the median
# across rounds of each run's median, and ref-b's difference from ref-a. Lower is
# better throughout, so a positive difference is a slowdown.
#
# Modes (-m, default "codec e2e profile"): codec, e2e, notify, profile, connect.
# See README.md for what each measures.
#
# Environment:
#   SWIFT          the swift command to build with (default: swift),
#                  e.g. SWIFT="swiftly run +6.3.3 swift"
#   PIN            a prefix for each benchmark run, e.g. PIN="taskset -c 2,3"; the
#                  builds are not pinned, so do not wrap this script in taskset
#   PERF           if set, record each profile and connect run with `perf record -g`
#                  into the -o directory (default ./ocaperf-results), for `perf diff`
#   OCAPERF_CACHE  where the per-commit build directories are kept
#                  (default: ${XDG_CACHE_HOME:-~/.cache}/ocaperf)
#   BENCH_TRANSPORT, BENCH_SLICE, BENCH_CONNECTIONS, BENCH_BLOCKS, BENCH_BLOCK_SIZE
#                  pass through to the harness; see README.md

set -eu

usage() {
  echo "usage: $0 [-r rounds] [-s seconds] [-p port] [-m modes] [-o dir] ref-a ref-b" >&2
  exit 64
}

rounds=5
seconds=15
port=56000
modes="codec e2e profile"
outdir=
while getopts r:s:p:m:o: opt; do
  case $opt in
  r) rounds=$OPTARG ;;
  s) seconds=$OPTARG ;;
  p) port=$OPTARG ;;
  m) modes=$OPTARG ;;
  o) outdir=$OPTARG ;;
  *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -eq 2 ] || usage
ref_a=$1
ref_b=$2
for mode in $modes; do
  case $mode in
  codec | e2e | notify | profile | connect) ;;
  *)
    echo "unknown mode: $mode" >&2
    usage
    ;;
  esac
done

swift=${SWIFT:-swift}
pin=${PIN:-}
perf=${PERF:-}
cache=${OCAPERF_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/ocaperf}
if [ -n "$perf" ] && [ -z "$outdir" ]; then outdir=ocaperf-results; fi
if [ -n "$outdir" ]; then
  mkdir -p "$outdir"
  outdir=$(cd "$outdir" && pwd)
fi
here=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel)
work=$(mktemp -d "${TMPDIR:-/tmp}/ocaperf.XXXXXX")
tab=$(printf '\t')

cleanup() {
  rm -rf "$work" # the per-commit build directories stay in the cache
}
trap cleanup EXIT INT TERM

# Wrapping the script in taskset pins the builds as well as the runs.
if command -v nproc >/dev/null 2>&1; then
  usable=$(nproc)
  online=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo "$usable")
  if [ "$usable" -lt "$online" ]; then
    echo "note: this script may use only $usable of $online CPUs, so its builds are" \
      "limited too; set PIN to pin the runs instead of wrapping it in taskset" >&2
  fi
fi

# Copies $1 to $2 unless $2 already has the same contents, so that an unchanged file
# keeps its timestamp and the next incremental build has nothing to recompile.
update() { # from to
  cmp -s "$1" "$2" 2>/dev/null || cp "$1" "$2"
}

# Gives a build directory this directory's harness and, unless it has one, an
# OCAPerfBench target, placed before the OCAEventBenchmark target every revision has.
inject() { # dir
  mkdir -p "$1/Examples/OCAPerfBench"
  update "$here/PerfBench.swift" "$1/Examples/OCAPerfBench/PerfBench.swift"
  if ! grep -q 'name: "OCAPerfBench"' "$1/Package.swift"; then
    awk '
      /name: "OCAEventBenchmark",/ && !done {
        print "  .executableTarget("
        print "    name: \"OCAPerfBench\","
        print "    dependencies: [\"SwiftOCA\", \"SwiftOCADevice\"],"
        print "    path: \"Examples/OCAPerfBench\""
        print "  ),"
        done = 1
      }
      { if (NR > 1) print prev; prev = $0 }
      END { print prev }' "$1/Package.swift" >"$1/Package.swift.new"
    mv "$1/Package.swift.new" "$1/Package.swift"
    if ! grep -q 'name: "OCAPerfBench"' "$1/Package.swift"; then
      echo "could not add the OCAPerfBench target to $1/Package.swift" >&2
      exit 1
    fi
  fi
}

build() { # label ref
  sha=$(git -C "$repo" rev-parse --verify "$2^{commit}")
  dir=$cache/$sha
  if [ ! -d "$dir" ]; then
    mkdir -p "$cache"
    export=$(mktemp -d "$cache/.export.XXXXXX")
    git -C "$repo" archive "$sha" | tar -x -C "$export"
    mv "$export" "$dir"
  fi
  inject "$dir"
  if [ -f "$repo/Package.resolved" ]; then
    update "$repo/Package.resolved" "$dir/Package.resolved"
  fi
  echo "building $1: $2 ($(git -C "$repo" rev-parse --short "$sha")) in $dir" >&2
  (cd "$dir" && $swift build -c release --product OCAPerfBench >&2)
  ln -s "$dir" "$work/$1"
}

run() { # label mode round
  bin=$work/$1/.build/release/OCAPerfBench
  data=
  record=
  if [ -n "$perf" ]; then
    case $2 in
    profile | connect)
      data=$outdir/perf-$1-$2-$3.data
      record="perf record -g -o $data --"
      ;;
    esac
  fi
  case $2 in
  e2e) BENCH_ONLY=e2e BENCH_PORT=$port $pin "$bin" ;;
  profile) BENCH_ONLY=profile BENCH_PORT=$port BENCH_SECONDS=$seconds $record $pin "$bin" ;;
  connect) BENCH_ONLY=connect BENCH_PORT=$port $record $pin "$bin" ;;
  *) BENCH_ONLY=$2 $pin "$bin" ;;
  esac 2>"$work/stderr" | sed "s/^/$1$tab/" >>"$work/results.tsv"
  if [ -n "$data" ] && [ ! -s "$data" ]; then
    echo "perf recorded nothing for $1, $2, round $3:" >&2
    cat "$work/stderr" >&2
    exit 1
  fi
  port=$((port + 100)) # fresh ports for each run: connect mode uses two per connection
}

build a "$ref_a"
build b "$ref_b"

for mode in $modes; do
  round=1
  while [ "$round" -le "$rounds" ]; do
    if [ $((round % 2)) -eq 1 ]; then order="a b"; else order="b a"; fi
    for label in $order; do
      echo "round $round/$rounds: $mode, $label" >&2
      run "$label" "$mode" "$round"
    done
    round=$((round + 1))
  done
done

if [ -n "$outdir" ]; then
  cp "$work/results.tsv" "$outdir/results.tsv"
fi

echo
echo "a = $ref_a ($(git -C "$repo" rev-parse --short "$ref_a"))"
echo "b = $ref_b ($(git -C "$repo" rev-parse --short "$ref_b"))"
echo "$rounds rounds of $modes; $(uname -srm); $(getconf _NPROCESSORS_ONLN 2>/dev/null || echo '?') CPUs"
if [ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
  echo "cpufreq governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
fi
if [ -n "$pin" ]; then echo "pinned: $pin"; fi
echo "figures are ns/op, except *.maxrss.KiB, peak memory in KiB"
echo
printf '%-44s %12s %12s %9s\n' benchmark a b "b vs a"

# one "label <tab> name <tab> value" line per run and benchmark: a RESULT line's
# median, or a PROFILE line converted to ns per round trip
awk -F'\t' '
  $2 == "RESULT" { print $1 "\t" $3 "\t" $5 }
  $2 == "PROFILE" {
    split($3, f, " ")
    transport = ($4 != "") ? $4 : "local"
    if (f[1] > 0) print $1 "\tprofile." transport ".getDeviceName\t" (f[5] + 0) * 1e9 / f[1]
  }' "$work/results.tsv" |
  sort -t "$tab" -k2,2 -k1,1 -k3,3n |
  awk -F'\t' '
    function flush() {
      if (n) {
        median[key] = (n % 2) ? v[(n + 1) / 2] : (v[n / 2] + v[n / 2 + 1]) / 2
        seen[name] = 1
      }
      n = 0
    }
    { k = $2 "\t" $1; if (k != key) { flush(); key = k; name = $2 } v[++n] = $3 }
    END {
      flush()
      for (nm in seen) {
        a = median[nm "\ta"]; b = median[nm "\tb"]
        if (a == "" || b == "") continue
        printf "%-44s %12.1f %12.1f %+8.1f%%\n", nm, a, b, (a ? (b - a) / a * 100 : 0)
      }
    }' |
  sort

if [ -n "$perf" ]; then
  echo
  echo "perf data is in $outdir. To see where b spends more time than a, for example:"
  echo "  perf diff $outdir/perf-a-profile-1.data $outdir/perf-b-profile-1.data | swift demangle --simplified | less"
fi
