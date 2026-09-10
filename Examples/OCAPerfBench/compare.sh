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
#   Examples/OCAPerfBench/compare.sh [-r rounds] [-s seconds] [-p port] ref-a ref-b
#
# Each revision is checked out into a temporary worktree, given this directory's
# PerfBench.swift and an OCAPerfBench target (so the refs need not contain the
# benchmark, and both build the same harness source), given this checkout's
# Package.resolved (so both build against the same dependencies), and built in
# release mode. The two binaries then run alternately, reversing the order each
# round, so that drift in load or clock speed falls on both alike. For each benchmark
# it prints the median across rounds of each run's median, and ref-b's difference
# from ref-a. Every figure is ns/op, so lower is better and a positive difference is
# a slowdown.
#
# Environment:
#   SWIFT  the swift command to build with (default: swift),
#          e.g. SWIFT="swiftly run +6.3.3 swift"
#   PIN    a prefix for each benchmark run, e.g. PIN="taskset -c 2" to pin one core

set -eu

usage() {
  echo "usage: $0 [-r rounds] [-s seconds] [-p port] ref-a ref-b" >&2
  exit 64
}

rounds=5
seconds=15
port=56000
while getopts r:s:p: opt; do
  case $opt in
  r) rounds=$OPTARG ;;
  s) seconds=$OPTARG ;;
  p) port=$OPTARG ;;
  *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -eq 2 ] || usage
ref_a=$1
ref_b=$2

swift=${SWIFT:-swift}
pin=${PIN:-}
here=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel)
work=$(mktemp -d "${TMPDIR:-/tmp}/ocaperf.XXXXXX")
tab=$(printf '\t')

cleanup() {
  git -C "$repo" worktree remove --force "$work/a" 2>/dev/null || true
  git -C "$repo" worktree remove --force "$work/b" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT INT TERM

# Gives a checkout this directory's harness and, unless it has one, an OCAPerfBench
# target, placed before the OCAEventBenchmark target that every revision has.
inject() { # dir
  mkdir -p "$1/Examples/OCAPerfBench"
  cp "$here/PerfBench.swift" "$1/Examples/OCAPerfBench/"
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
  git -C "$repo" worktree add --quiet --detach "$work/$1" "$2"
  inject "$work/$1"
  if [ -f "$repo/Package.resolved" ]; then
    cp "$repo/Package.resolved" "$work/$1/"
  fi
  echo "building $1: $2 ($(git -C "$repo" rev-parse --short "$2"))" >&2
  (cd "$work/$1" && $swift build -c release --product OCAPerfBench >&2)
}

run() { # label mode
  bin=$work/$1/.build/release/OCAPerfBench
  case $2 in
  e2e) BENCH_ONLY=e2e BENCH_PORT=$port $pin "$bin" ;;
  profile) BENCH_ONLY=profile BENCH_SECONDS=$seconds $pin "$bin" ;;
  *) BENCH_ONLY=$2 $pin "$bin" ;;
  esac 2>/dev/null | sed "s/^/$1$tab/" >>"$work/results.tsv"
  port=$((port + 10)) # a fresh pair of ports for each end-to-end run
}

build a "$ref_a"
build b "$ref_b"

for mode in codec e2e profile; do
  round=1
  while [ "$round" -le "$rounds" ]; do
    if [ $((round % 2)) -eq 1 ]; then order="a b"; else order="b a"; fi
    for label in $order; do
      echo "round $round/$rounds: $mode, $label" >&2
      run "$label" "$mode"
    done
    round=$((round + 1))
  done
done

echo
echo "a = $ref_a ($(git -C "$repo" rev-parse --short "$ref_a"))"
echo "b = $ref_b ($(git -C "$repo" rev-parse --short "$ref_b"))"
echo "$rounds rounds; $(uname -srm); $(getconf _NPROCESSORS_ONLN 2>/dev/null || echo '?') CPUs"
if [ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
  echo "cpufreq governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
fi
echo
printf '%-44s %12s %12s %9s\n' benchmark "a ns/op" "b ns/op" "b vs a"

# one "label <tab> name <tab> ns/op" line per run and benchmark: a RESULT line's
# median, or a PROFILE line converted to ns per round trip
awk -F'\t' '
  $2 == "RESULT" { print $1 "\t" $3 "\t" $5 }
  $2 == "PROFILE" {
    split($3, f, " ")
    if (f[1] > 0) print $1 "\tprofile.local.getDeviceName\t" (f[5] + 0) * 1e9 / f[1]
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
