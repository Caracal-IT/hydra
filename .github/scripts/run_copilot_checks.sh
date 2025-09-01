#!/usr/bin/env bash
set -euo pipefail

printf "%s\n" "0.0" > .coverage_current || true
cleanup() { if [ ! -f .coverage_current ]; then printf "%s\n" "0.0" > .coverage_current || true; fi; }
trap cleanup EXIT

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

echo "Ensuring workspace module dependencies"
if command -v go >/dev/null 2>&1; then
  # If go.work exists, sync; ensure src module tidy
  go work sync >/dev/null 2>&1 || true
  if [ -f src/go.mod ]; then (cd src && go mod tidy >/dev/null 2>&1 || true); fi
else
  echo "go not found in PATH"; exit 1
fi

# Ensure go.sum exists (in src module) for caching even when no external deps
if [ -f src/go.mod ]; then
  if [ ! -f src/go.sum ]; then
    echo "Generating src/go.sum via go list"
    (cd src && go list ./... >/dev/null 2>&1 || true)
  fi
  if [ ! -f src/go.sum ]; then
    echo "Creating empty src/go.sum (no external dependencies)"
    : > src/go.sum
  fi
fi

# Verify tests/benchmarks/examples presence
echo "Verifying presence of tests, benchmarks and examples"
FAIL=0
# Collect unique directories containing .go files
pkg_dirs=$(find src -type f -name '*.go' -not -path '*/.git/*' -not -path '*/vendor/*' -print0 | xargs -0 -n1 dirname | sort -u)

for d in $pkg_dirs; do
  gofiles_count=$(find "$d" -maxdepth 1 -type f -name "*.go" | wc -l | tr -d ' ')
  [ "$gofiles_count" -eq 0 ] && continue
  set +o noglob
  test_files=("$d"/*_test.go)
  set -o noglob || true
  if [ "${#test_files[@]}" -eq 1 ] && [ ! -f "${test_files[0]}" ]; then
    # If glob didn't match, array still contains pattern literal
    test_files=()
  fi
  if [ "${#test_files[@]}" -eq 0 ]; then
    echo "ERROR: package $d has Go files but no *_test.go"; FAIL=1; continue
  fi
  has_bench=0; has_example=0
  for tf in "${test_files[@]}"; do
    [ -f "$tf" ] || continue
    grep -E -q '^\s*func\s+Benchmark' "$tf" && has_bench=1 || true
    grep -E -q '^\s*func\s+Example' "$tf" && has_example=1 || true
    [ $has_bench -eq 1 ] && [ $has_example -eq 1 ] && break
  done
  [ $has_bench -eq 0 ] && { echo "ERROR: package $d missing benchmark (func Benchmark...)"; FAIL=1; }
  [ $has_example -eq 0 ] && { echo "ERROR: package $d missing example (func Example...)"; FAIL=1; }
done

if [ $FAIL -ne 0 ]; then echo "Required tests/benchmarks/examples missing"; exit 4; fi

# Run tests with coverage (single module inside src)
rm -f coverage.out || true
if (cd src && go test ./... -coverprofile=coverage.out); then
  mv src/coverage.out coverage.out
else
  echo "Tests failed"; exit 5
fi

COVERAGE_PERCENT_RAW=$(go tool cover -func=coverage.out | awk '/total:/ {print $3}')
COVERAGE_PERCENT=$(printf "%s" "$COVERAGE_PERCENT_RAW" | tr -d '%\n\r' | sed 's/^\s*//;s/\s*$//')
[ -z "$COVERAGE_PERCENT" ] && { echo "Failed to compute coverage"; printf "%s\n" "0.0" > .coverage_current; exit 2; }
printf "%s\n" "$COVERAGE_PERCENT" > .coverage_current

if [ ! -f .coverage_baseline ]; then
  echo "Initializing coverage baseline: $COVERAGE_PERCENT%"
  cp .coverage_current .coverage_baseline
  exit 0
fi
BASELINE=$(tr -d '%\n\r' < .coverage_baseline | sed 's/^\s*//;s/\s*$//')
compare_result=$(awk -v a="$COVERAGE_PERCENT" -v b="$BASELINE" 'BEGIN {print (a+0 < b+0) ? 1 : 0}')
if [ "$compare_result" -eq 1 ]; then
  echo "ERROR: Coverage decreased. Current: ${COVERAGE_PERCENT}%, Baseline: ${BASELINE}%"; exit 3
fi
if awk -v a="$COVERAGE_PERCENT" -v b="$BASELINE" 'BEGIN {exit (a+0 > b+0)?0:1}'; then
  echo "Coverage improved from ${BASELINE}% to ${COVERAGE_PERCENT}%. Updating baseline."
  cp .coverage_current .coverage_baseline
else
  echo "Coverage unchanged at ${COVERAGE_PERCENT}% (baseline ${BASELINE}%)."
fi
exit 0
