#!/usr/bin/env bats
# Options, help and usage errors (D-010).
# Run all tests from the repo root:  bats 3-bash-extract/tests

# ShellCheck cannot see across files, so two warnings are false alarms here:
# SC2154: $status/$output/$stderr are set by bats "run", $EXTRACT by test_helper.
# SC2034: $verbose/$recursive are set here and read by the sourced script.
# shellcheck disable=SC2154,SC2034

load test_helper

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
    load_extract
    parse_args -rv a.gz
    [ "$recursive" -eq 1 ]
    [ "$verbose" -eq 1 ]
}

@test "parse_args reads options again when called a second time" {
    load_extract
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
