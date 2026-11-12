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

# Load the script's functions and tables into the test (main does not run).
load_extract() {
    # shellcheck source=../extract
    source "$EXTRACT"
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

# --- Chunk 2: type detection and tool tables ---

# Create one file of each type, with misleading names, in the test's temp dir.
make_fixtures() {
    cd "$BATS_TEST_TMPDIR" || return 1
    printf 'hello\n' > src.txt
    printf 'hello\n' | gzip > report.txt
    printf 'hello\n' | bzip2 > photo.png
    printf 'hello\n' | compress -f > notes.doc   # -f: see T-004
    zip -q - src.txt > backup.tar
}

@test "detect_type: gzip named report.txt" {
    load_extract
    make_fixtures
    run detect_type report.txt
    [ "$output" = "application/gzip" ]
}

@test "detect_type: bzip2 named photo.png" {
    load_extract
    make_fixtures
    run detect_type photo.png
    [ "$output" = "application/x-bzip2" ]
}

@test "detect_type: zip named backup.tar" {
    load_extract
    make_fixtures
    run detect_type backup.tar
    [ "$output" = "application/zip" ]
}

@test "detect_type: compress named notes.doc" {
    load_extract
    make_fixtures
    run detect_type notes.doc
    [ "$output" = "application/x-compress" ]
}

@test "detect_type: follows a symlink to a gzip file" {
    load_extract
    make_fixtures
    ln -s report.txt link.txt
    run detect_type link.txt
    [ "$output" = "application/gzip" ]
}

@test "detect_type: plain text file" {
    load_extract
    make_fixtures
    run detect_type src.txt
    [ "$output" = "text/plain" ]
}

@test "tables: every stream tool is installed" {
    load_extract
    local tool
    for tool in "${STREAM_TOOLS[@]}"; do
        command -v "$tool" >/dev/null
    done
}

@test "tables: text/plain is in neither table" {
    load_extract
    [ -z "${STREAM_TOOLS[text/plain]:-}" ]
    [ -z "${ARCHIVE_TOOLS[text/plain]:-}" ]
}

@test "tables: every archive tool is a defined function" {
    load_extract
    local fn
    for fn in "${ARCHIVE_TOOLS[@]}"; do
        declare -F "$fn" >/dev/null
    done
}
