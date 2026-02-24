#!/bin/bash
# Script to measure code coverage of the go-fdo-server project.
# Combines coverage from unit tests and integration tests into a single report.

# Exit immediately on any error
set -e

# --- Cleanup from previous run ---
# Kill any leftover go-fdo-server process and remove the test working directory
pkill -f "go-fdo-server" || true
rm -rf test/workdir

# --- Phase 1: Unit tests ---
# Run all unit tests with coverage profiling.
# "atomic" mode is safe for parallel/concurrent tests.
go test -coverprofile=coverage-unit.out -covermode=atomic ./...

# --- Phase 2: Integration tests ---
# GOCOVERDIR tells the Go runtime where to store binary coverage data
# when running a compiled binary (the server).
GOCOVERDIR="$(pwd)/coverage-integration"
export GOCOVERDIR
rm -rf "$GOCOVERDIR"
mkdir -p "$GOCOVERDIR"

# Source the helper script and build the server with coverage instrumentation
# (utils.sh builds with -covermode=atomic when GOCOVERDIR is set)
source test/ci/utils.sh
install_server

# Iterate over all integration test scripts.
# On failure, continue to the next test and print a summary at the end.
passed=0
failed=0
for t in test/ci/test-*.sh; do
    echo "=== Running: $t ==="
    if bash "$t"; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        echo "WARN: $t failed, continuing"
    fi
done
echo "=== Integration tests: $passed passed, $failed failed ==="

# Convert binary coverage data from integration tests into text format
# compatible with the unit test coverage profile
go tool covdata textfmt -i="$GOCOVERDIR" -o=coverage-integration.out

# --- Merge coverage profiles ---
# Install gocovmerge and merge both profiles (unit + integration) into one file
go install github.com/wadey/gocovmerge@latest
gocovmerge coverage-unit.out coverage-integration.out > coverage.out

# --- Evaluate ---
# Check that coverage meets the thresholds defined in .testcoverage.yml
go-test-coverage --config .testcoverage.yml
# Generate an HTML report for visual inspection of coverage
go tool cover -html=coverage.out -o coverage.html
