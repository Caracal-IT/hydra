#!/usr/bin/env bash
set -euo pipefail

# Ensure we always produce a .coverage_current file for CI artifact upload
printf "%s\n" "0.0" > .coverage_current || true

# Ensure .coverage_current exists even on unexpected exit
cleanup() {
  if [ ! -f .coverage_current ]; then
    printf "%s\n" "0.0" > .coverage_current || true
  fi
}
trap cleanup EXIT

# Run from repository root
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

echo "Running go work sync and go mod tidy to ensure go.sum exists"
# sync go.work and tidy modules
if command -v go >/dev/null 2>&1; then
  go work sync >/dev/null 2>&1 || true
  # run go mod tidy at repository root
  go mod tidy >/dev/null 2>&1 || true
  if [ -d ./src/gohydra ]; then
    (cd ./src/gohydra && go mod tidy >/dev/null 2>&1) || true
  fi
else
  echo "go not found in PATH"
  exit 1
fi

# Ensure go.sum exists for caching in CI
if [ ! -f go.sum ]; then
  echo "Generating go.sum by running go list ./..."
  go list ./... >/dev/null 2>&1 || true
fi

# Verify test files exist for each package that contains go files
echo "Verifying presence of tests, benchmarks and examples for packages with Go source"
FAIL=0

# Use bash nullglob and safe find parsing to collect package directories
shopt -s nullglob
declare -A seen_dirs=()
pkg_dirs=()
while IFS= read -r -d '' f; do
  d=$(dirname "$f")
  case "$d" in
    ./.git*|./vendor*) continue ;;
  esac
  if [ -z "${seen_dirs[$d]:-}" ]; then
    seen_dirs[$d]=1
    pkg_dirs+=("$d")
  fi
done < <(find . -type f -name '*.go' -not -path './.git/*' -not -path './vendor/*' -print0)

for d in "${pkg_dirs[@]}"; do
  # skip empty
  [ -z "$d" ] && continue

  # count Go files in directory
  gofiles_count=$(find "$d" -maxdepth 1 -type f -name "*.go" | wc -l | tr -d ' ')
  if [ "$gofiles_count" -eq 0 ]; then
    continue
  fi

  # gather test files using nullglob behavior
  test_files=("$d"/*_test.go)
  if [ "${#test_files[@]}" -eq 0 ]; then
    echo "ERROR: package $d has Go files but no *_test.go files"
    FAIL=1
    continue
  fi

  # check for benchmark and example in test files quietly
  has_bench=0
  has_example=0
  for tf in "${test_files[@]}"; do
    if grep -E -q '^\s*func\s+Benchmark' "$tf"; then has_bench=1; fi
    if grep -E -q '^\s*func\s+Example' "$tf"; then has_example=1; fi
    # short-circuit
    if [ "$has_bench" -eq 1 ] && [ "$has_example" -eq 1 ]; then break; fi
  done

  if [ "$has_bench" -eq 0 ]; then
    echo "ERROR: package $d has no benchmarks (func Benchmark...) in tests"
    FAIL=1
  fi
  if [ "$has_example" -eq 0 ]; then
    echo "ERROR: package $d has no examples (func Example...) in tests"
    FAIL=1
  fi
done

if [ "$FAIL" -ne 0 ]; then
  echo "One or more packages are missing required tests/benchmarks/examples"
  exit 4
fi

# Run tests with coverage
echo "Running tests and generating coverage profiles"
# clean previous coverage files
rm -f coverage_root.out coverage_gohydra.out coverage.out coverage.tmp || true

# Run tests for root module packages
if go test ./... -coverprofile=coverage_root.out >/dev/null 2>&1; then
  echo "Root module tests completed"
else
  echo "Running root module tests (visible output)"
  go test ./... -coverprofile=coverage_root.out
fi

# If submodule exists, run its tests and collect coverage
if [ -d ./src/gohydra ]; then
  echo "Running tests for src/gohydra"
  if (cd ./src/gohydra && go test ./... -coverprofile=coverage_gohydra.out) >/dev/null 2>&1; then
    echo "gohydra tests completed"
  else
    (cd ./src/gohydra && go test ./... -coverprofile=coverage_gohydra.out)
  fi
fi

# Merge coverage profiles if needed
if [ -f coverage_root.out ] && [ -f coverage_gohydra.out ]; then
  # write mode line from first file
  head -n 1 coverage_root.out > coverage.out
  # append non-mode lines from both files
  tail -n +2 coverage_root.out >> coverage.out
  tail -n +2 coverage_gohydra.out >> coverage.out
elif [ -f coverage_root.out ]; then
  mv coverage_root.out coverage.out
elif [ -f coverage_gohydra.out ]; then
  mv coverage_gohydra.out coverage.out
else
  echo "No coverage files generated"
  # ensure we still create a coverage_current file to allow CI artifact upload
  printf "%s\n" "0.0" > .coverage_current
  exit 2
fi

# Extract total coverage percentage
COVERAGE_PERCENT_RAW=$(go tool cover -func=coverage.out | awk '/total:/ {print $3}')
# Normalize: remove trailing % and any whitespace
COVERAGE_PERCENT=$(printf "%s" "$COVERAGE_PERCENT_RAW" | tr -d '%\n\r' | sed 's/^\s*//;s/\s*$//')
if [ -z "$COVERAGE_PERCENT" ]; then
  echo "Failed to compute coverage percent"
  printf "%s\n" "0.0" > .coverage_current
  exit 2
fi
printf "%s\n" "$COVERAGE_PERCENT" > .coverage_current

# Compare against baseline (normalize baseline number too)
if [ ! -f .coverage_baseline ]; then
  echo "Baseline not found. Initializing .coverage_baseline with current coverage: $COVERAGE_PERCENT%"
  cp .coverage_current .coverage_baseline
  exit 0
fi

BASELINE_RAW=$(cat .coverage_baseline || true)
BASELINE=$(printf "%s" "$BASELINE_RAW" | tr -d '%\n\r' | sed 's/^\s*//;s/\s*$//')

# Use awk for float comparison
compare_result=$(awk -v a="$COVERAGE_PERCENT" -v b="$BASELINE" 'BEGIN {if (a=="" || b=="") {print 1; exit} print (a+0 < b+0) ? 1 : 0}')

if [ "$compare_result" -eq 1 ]; then
  echo "ERROR: Coverage decreased. Current: ${COVERAGE_PERCENT}%, Baseline: ${BASELINE}%"
  exit 3
fi

echo "Coverage OK. Current: ${COVERAGE_PERCENT}%, Baseline: ${BASELINE}%"
exit 0
