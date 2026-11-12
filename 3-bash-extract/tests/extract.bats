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
    printf 'hello\n' | compress -f > notes.doc   # -f: see T-003
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

# --- Chunk 3: output file name for stream tools (D-003) ---

@test "output_name: removes .gz / .bz2 / .Z" {
    load_extract
    [ "$(output_name data.gz)" = "data" ]
    [ "$(output_name backup.bz2)" = "backup" ]
    [ "$(output_name old.Z)" = "old" ]
}

@test "output_name: adds .out when there is no known suffix" {
    load_extract
    [ "$(output_name report.txt)" = "report.txt.out" ]
    [ "$(output_name noext)" = "noext.out" ]
}

@test "output_name: suffix is case-sensitive (.GZ is not .gz)" {
    load_extract
    [ "$(output_name data.GZ)" = "data.GZ.out" ]
}

@test "output_name: keeps the folder part of the path" {
    load_extract
    [ "$(output_name dir/sub/a.gz)" = "dir/sub/a" ]
}

@test "output_name: removes only the last suffix" {
    load_extract
    [ "$(output_name a.tar.gz)" = "a.tar" ]
}

@test "output_name: a name that is only the suffix gets .out" {
    load_extract
    [ "$(output_name .gz)" = ".gz.out" ]
    [ "$(output_name dir/.bz2)" = "dir/.bz2.out" ]
}

@test "output_name: a name that would become '.' or '..' gets .out" {
    load_extract
    [ "$(output_name ..gz)" = "..gz.out" ]
    [ "$(output_name ...bz2)" = "...bz2.out" ]
    [ "$(output_name dir/..Z)" = "dir/..Z.out" ]
}

@test "output_name: a name that starts with '-' is printed as is" {
    load_extract
    [ "$(output_name -n.gz)" = "-n" ]
}

# --- Chunk 4: unpacking with a stream tool (D-002, D-003, D-005) ---

# Print the temp files left in the current folder (nothing = clean).
leftover_temp_files() {
    find . -name '.extract.*'
}

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
