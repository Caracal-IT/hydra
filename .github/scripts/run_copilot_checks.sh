#!/usr/bin/env bash
set -euo pipefail

# Run repository checks used by Copilot instruction enforcement and CI.
# - Ensures go.sum is present
# - Runs tests/benchmarks/examples and generates coverage
# - Compares coverage to baseline and fails if coverage decreased

# Determine repository root (two levels up from this script: .github/scripts -> repo root)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

echo "Running go mod tidy to ensure go.sum"
go mod tidy

# Ensure coverage output paths are at repository root
COVERAGE_FILE="${ROOT_DIR}/.coverage_current"
COVERPROFILE="${ROOT_DIR}/src/coverage.out"

# Run tests including benchmarks and examples, collect coverage
echo "Running tests (including benchmarks and examples) and generating coverage at ${COVERPROFILE}"
# Run all tests and benchmarks in src/
# -covermode=set to match previous coverage output format
go test ./src/... -bench=. -covermode=set -coverprofile="${COVERPROFILE}"

# Compute total coverage percentage
TOTAL_LINE=$(go tool cover -func="${COVERPROFILE}" | tail -n1 || true)
if [ -z "$TOTAL_LINE" ]; then
  echo "No coverage data produced"
  echo "0.0%" > "$COVERAGE_FILE"
else
  PERCENT=$(echo "$TOTAL_LINE" | awk '{print $3}')
  echo "$PERCENT" > "$COVERAGE_FILE"
  echo "Coverage: $PERCENT"
fi

# Compare with baseline if present
BASELINE_FILE="${ROOT_DIR}/.coverage_baseline"
if [ ! -f "$BASELINE_FILE" ]; then
  echo "No baseline found; creating baseline from current coverage"
  cp "$COVERAGE_FILE" "$BASELINE_FILE"
  exit 0
fi

# Normalize percentages to numbers (strip %)
curr=$(cat "$COVERAGE_FILE" | tr -d '%')
base=$(cat "$BASELINE_FILE" | tr -d '%')

# Use awk for numeric comparison
decreased=$(awk -v c="$curr" -v b="$base" 'BEGIN{if ((c+0) < (b+0)) print 1; else print 0}')
if [ "$decreased" -eq 1 ]; then
  echo "Coverage decreased: baseline=$base% current=$curr%"
  echo "CI will fail to prevent regression."
  exit 2
fi

echo "Coverage OK: baseline=$base% current=$curr%"
exit 0
