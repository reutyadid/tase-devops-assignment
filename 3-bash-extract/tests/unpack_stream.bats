#!/usr/bin/env bats
# Unpacking with a stream tool: gunzip, bunzip2, uncompress (D-002, D-005).
# Run all tests from the repo root:  bats 3-bash-extract/tests

# ShellCheck cannot see across files, so two warnings are false alarms here:
# SC2154: $status/$output/$stderr are set by bats "run", $EXTRACT by test_helper.
# SC2034: $verbose/$recursive are set here and read by the sourced script.
# shellcheck disable=SC2154,SC2034

load test_helper

@test "unpack_stream: gzip with a misleading name" {
    load_extract
    make_fixtures
    unpack_stream report.txt gunzip
    [ "$(cat report.txt.out)" = "hello" ]
    [ -f report.txt ]                      # the archive is kept (D-004)
    [ -z "$(leftover_temp_files)" ]
}

@test "unpack_stream: bzip2 with a misleading name" {
    load_extract
    make_fixtures
    unpack_stream photo.png bunzip2
    [ "$(cat photo.png.out)" = "hello" ]
}

@test "unpack_stream: compress with a misleading name" {
    load_extract
    make_fixtures
    unpack_stream notes.doc uncompress
    [ "$(cat notes.doc.out)" = "hello" ]
}

@test "unpack_stream: a known suffix is removed from the output name" {
    load_extract
    cd "$BATS_TEST_TMPDIR"
    printf 'hello\n' | gzip > data.gz
    unpack_stream data.gz gunzip
    [ "$(cat data)" = "hello" ]
}

@test "unpack_stream: an existing file with the same name is overwritten" {
    load_extract
    cd "$BATS_TEST_TMPDIR"
    printf 'old\n' > data
    printf 'hello\n' | gzip > data.gz
    unpack_stream data.gz gunzip
    [ "$(cat data)" = "hello" ]
}

@test "unpack_stream: the output gets the permissions of the archive" {
    load_extract
    cd "$BATS_TEST_TMPDIR"
    printf 'hello\n' | gzip > data.gz
    chmod 640 data.gz
    unpack_stream data.gz gunzip
    [ "$(stat -c %a data)" = "640" ]
}

@test "unpack_stream: a corrupt archive fails and keeps the existing file" {
    load_extract
    cd "$BATS_TEST_TMPDIR"
    printf 'keep\n' > bad
    printf 'not really gzip' > bad.gz
    run unpack_stream bad.gz gunzip
    [ "$status" -eq 1 ]
    [ "$(cat bad)" = "keep" ]
    [ -z "$(leftover_temp_files)" ]
}

@test "unpack_stream: output name is an existing folder -> fails, folder untouched" {
    load_extract
    cd "$BATS_TEST_TMPDIR"
    mkdir logs
    printf 'hello\n' | gzip > logs.gz
    verbose=1
    run --separate-stderr unpack_stream logs.gz gunzip
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"'logs' is a folder"* ]]
    [ -z "$(ls -A logs)" ]
    [ -z "$(leftover_temp_files)" ]
}

@test "unpack_stream: a missing tool fails with a warning" {
    load_extract
    make_fixtures
    verbose=1
    run --separate-stderr unpack_stream report.txt no-such-tool
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"'no-such-tool' is not installed"* ]]
}

@test "unpack_stream: a symlink is unpacked next to the link, named after the link" {
    load_extract
    cd "$BATS_TEST_TMPDIR"
    mkdir real
    printf 'hello\n' | gzip > real/data.gz
    ln -s real/data.gz link.gz
    unpack_stream link.gz gunzip
    [ "$(cat link)" = "hello" ]
    [ ! -e real/data ]
}

@test "unpack_stream: no output at all without -v" {
    load_extract
    cd "$BATS_TEST_TMPDIR"
    printf 'not really gzip' > bad.gz
    run --separate-stderr unpack_stream bad.gz gunzip
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    [ -z "$stderr" ]
}

@test "warn: prints to stderr only with -v" {
    load_extract
    verbose=0
    run --separate-stderr warn "something"
    [ -z "$stderr" ]
    verbose=1
    run --separate-stderr warn "something"
    [ "$stderr" = "extract: warning: something" ]
}

@test "cleanup: removes the temp file that was being written" {
    load_extract
    cd "$BATS_TEST_TMPDIR"
    local tmp
    tmp=$(mktemp .extract.XXXXXX)
    TMP_PATH="$tmp"
    cleanup
    [ ! -e "$tmp" ]
    [ -z "$TMP_PATH" ]
}

@test "unpack_stream: a missing input file fails with no output without -v" {
    load_extract
    cd "$BATS_TEST_TMPDIR"
    run --separate-stderr unpack_stream missing.gz gunzip
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    [ -z "$stderr" ]
    [ -z "$(leftover_temp_files)" ]
}

@test "unpack_stream: a folder that is not writable fails, quiet without -v" {
    [ "$(id -u)" -ne 0 ] || skip "root can write to any folder"
    load_extract
    cd "$BATS_TEST_TMPDIR"
    mkdir ro
    printf 'hello\n' | gzip > ro/data.gz
    chmod 555 ro
    run --separate-stderr unpack_stream ro/data.gz gunzip
    [ "$status" -eq 1 ]
    [ -z "$stderr" ]
    verbose=1
    run --separate-stderr unpack_stream ro/data.gz gunzip
    [[ "$stderr" == *"cannot create a temp file in 'ro'"* ]]
    chmod 755 ro                           # let bats delete the temp dir
}
