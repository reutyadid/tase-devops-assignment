#!/usr/bin/env bats
# Tests for the extract script.
# Run from the repo root:  bats 3-bash-extract/tests

# $stderr is set by "run --separate-stderr"; $verbose/$recursive come from the
# sourced script. ShellCheck cannot see either, so SC2154 is disabled for this file.
# shellcheck disable=SC2154
# Resolve "source" paths relative to this test file, not the current directory.
# shellcheck source-path=SCRIPTDIR

bats_require_minimum_version 1.5.0   # needed for "run --separate-stderr"

setup() {
    EXTRACT="$BATS_TEST_DIRNAME/../extract"
}

# --- Chunk 1: options and usage errors ---

@test "-h prints the help to stdout and exits 0" {
    run --separate-stderr "$EXTRACT" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: extract"* ]]
    [ -z "$stderr" ]
}

@test "no files: error on stderr, exit 2" {
    run --separate-stderr "$EXTRACT"
    [ "$status" -eq 2 ]
    [ -z "$output" ]
    [[ "$stderr" == *"no files given"* ]]
}

@test "unknown option: error on stderr, exit 2" {
    run --separate-stderr "$EXTRACT" -x a.gz
    [ "$status" -eq 2 ]
    [ -z "$output" ]
    [[ "$stderr" == *"unknown option: -x"* ]]
}

@test "combined flags -rv set both options" {
    # shellcheck source=../extract
    source "$EXTRACT"
    parse_args -rv a.gz
    [ "$recursive" -eq 1 ]
    [ "$verbose" -eq 1 ]
}

@test "parse_args reads options again when called a second time" {
    # shellcheck source=../extract
    source "$EXTRACT"
    parse_args -r a.gz
    verbose=0
    parse_args -v b.gz
    [ "$verbose" -eq 1 ]
}

@test "missing 'file' command: error on stderr, exit 2" {
    # Run bash directly with a PATH where 'file' cannot be found.
    # env changes PATH only for the script, not for bats itself.
    run --separate-stderr env PATH="/nonexistent" "$BASH" "$EXTRACT" a.gz
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"'file' command is required"* ]]
}
