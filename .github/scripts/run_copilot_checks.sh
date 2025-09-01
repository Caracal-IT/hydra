#!/usr/bin/env bash
set -euo pipefail

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
# find packages under root and src (portable and safe: use -print0 and xargs)
PKG_DIRS=$(find . -name "*.go" -not -path "./.git/*" -not -path "./vendor/*" -print0 | xargs -0 -n1 dirname | sort -u)
# iterate safely over lines
while IFS= read -r d; do
  # skip empty
  [ -z "$d" ] && continue
  # skip vendor and hidden .git
  case "$d" in
    ./.git*|./vendor*) continue ;;
  esac

  # count Go files in directory (numeric)
  gofiles=$(find "$d" -maxdepth 1 -type f -name "*.go" | wc -l | tr -d ' ')
  if [ "$gofiles" -eq 0 ]; then
    continue
  fi

  # count test files
  testfiles=$(find "$d" -maxdepth 1 -type f -name "*_test.go" | wc -l | tr -d ' ')
  if [ "$testfiles" -eq 0 ]; then
    echo "ERROR: package $d has Go files but no *_test.go files"
    FAIL=1
    continue
  fi

  # check for benchmark and example in test files — count matches
  has_bench=$(find "$d" -maxdepth 1 -type f -name "*_test.go" -exec grep -E "^\s*func\s+Benchmark" -H {} \; 2>/dev/null | wc -l | tr -d ' ')
  has_example=$(find "$d" -maxdepth 1 -type f -name "*_test.go" -exec grep -E "^\s*func\s+Example" -H {} \; 2>/dev/null | wc -l | tr -d ' ')

  if [ "$has_bench" -eq 0 ]; then
    echo "ERROR: package $d has no benchmarks (func Benchmark...) in tests"
    FAIL=1
  fi
  if [ "$has_example" -eq 0 ]; then
    echo "ERROR: package $d has no examples (func Example...) in tests"
    FAIL=1
  fi

done <<< "$PKG_DIRS"

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
