#!/usr/bin/env bats
# Type detection with `file` and the tool tables (D-001).
# Run all tests from the repo root:  bats 3-bash-extract/tests

# ShellCheck cannot see across files, so two warnings are false alarms here:
# SC2154: $status/$output/$stderr are set by bats "run", $EXTRACT by test_helper.
# SC2034: $verbose/$recursive are set here and read by the sourced script.
# shellcheck disable=SC2154,SC2034

load test_helper

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
