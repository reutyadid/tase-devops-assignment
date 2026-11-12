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

# --- Chunk 5: unpacking with an archive tool (D-002, D-005) ---

# Create test.zip (misleading name: pics.iso) with a file, a subfolder and a hidden
# file, in the test's temp dir.
make_zip() {
    cd "$BATS_TEST_TMPDIR" || return 1
    mkdir src
    printf 'hello\n' > src/a.txt
    mkdir src/sub
    printf 'deep\n' > src/sub/b.txt
    printf 'secret\n' > src/.hidden
    (cd src && zip -qr ../pics.iso a.txt sub .hidden)
    rm -rf src
}

@test "unpack_archive: zip with a misleading name, subfolders and hidden files" {
    load_extract
    make_zip
    unpack_archive pics.iso unpack_zip
    [ "$(cat a.txt)" = "hello" ]
    [ "$(cat sub/b.txt)" = "deep" ]
    [ "$(cat .hidden)" = "secret" ]
    [ -f pics.iso ]                        # the archive is kept (D-004)
    [ -z "$(leftover_temp_files)" ]
}

@test "unpack_archive: the permissions of the target folder do not change" {
    load_extract
    make_zip
    mkdir out
    mv pics.iso out/
    chmod 755 out
    unpack_archive out/pics.iso unpack_zip
    [ "$(stat -c %a out)" = "755" ]
}

@test "unpack_archive: an existing file with the same name is overwritten" {
    load_extract
    make_zip
    printf 'old\n' > a.txt
    unpack_archive pics.iso unpack_zip
    [ "$(cat a.txt)" = "hello" ]
}

@test "unpack_archive: a file vs. folder conflict fails with a warning" {
    load_extract
    make_zip
    mkdir a.txt                            # the zip has a FILE called a.txt
    verbose=1
    run --separate-stderr unpack_archive pics.iso unpack_zip
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"could not write all files"* ]]
    [ -d a.txt ]
    # The copy is not all-or-nothing (D-002): the other items were written.
    [ -f sub/b.txt ]
    [ -z "$(leftover_temp_files)" ]
}

@test "unpack_archive: a name that starts with '-' works" {
    load_extract
    make_zip
    mv pics.iso ./-o.zip
    unpack_archive -o.zip unpack_zip
    [ "$(cat a.txt)" = "hello" ]
}

@test "unpack_archive: a corrupt zip fails, writes nothing" {
    load_extract
    make_zip
    head -c 100 pics.iso > broken.zip      # cut the zip in the middle
    rm pics.iso
    run --separate-stderr unpack_archive broken.zip unpack_zip
    [ "$status" -eq 1 ]
    [ -z "$stderr" ]                       # quiet without -v
    [ ! -e a.txt ]                         # nothing was written
    [ -z "$(leftover_temp_files)" ]
}

@test "unpack_archive: an encrypted zip fails at once (no password prompt)" {
    load_extract
    cd "$BATS_TEST_TMPDIR"
    printf 'hello\n' > a.txt
    zip -q -P secret enc.zip a.txt
    rm a.txt
    # A new bash under "timeout", so a hang ends the test instead of blocking it.
    # Single quotes on purpose: $1 is expanded by the inner bash (= $EXTRACT).
    # shellcheck disable=SC2016
    run timeout 10 bash -c 'source "$1"; unpack_archive enc.zip unpack_zip' _ "$EXTRACT"
    [ "$status" -eq 1 ]                    # 124 would mean timeout = it waited
    [ ! -e a.txt ]
    [ -z "$(leftover_temp_files)" ]
}

@test "unpack_archive: an empty zip counts as a failure" {
    load_extract
    cd "$BATS_TEST_TMPDIR"
    printf 'x' > tmp.txt
    zip -q empty.zip tmp.txt
    zip -q -d empty.zip tmp.txt            # delete the only entry -> empty zip
    rm tmp.txt
    run unpack_archive empty.zip unpack_zip
    [ "$status" -eq 1 ]
    [ -z "$(leftover_temp_files)" ]
}

@test "unpack_archive: a '../' path in the zip stays inside the folder" {
    load_extract
    cd "$BATS_TEST_TMPDIR"
    mkdir -p work/inner
    printf 'bad\n' > work/escaped.txt
    (cd work/inner && zip -q ../../slip.zip ../escaped.txt)
    rm work/escaped.txt
    mv slip.zip work/inner/
    unpack_archive work/inner/slip.zip unpack_zip
    [ -f work/inner/escaped.txt ]          # unzip removed the "../"
    [ ! -e work/escaped.txt ]
}

@test "unpack_archive: a symlink in the zip cannot be used to write outside" {
    load_extract
    cd "$BATS_TEST_TMPDIR"
    mkdir outside build
    # Entry 1: lnk -> outside folder. Entry 2: lnk/evil.txt (written through the link?)
    ln -s "$BATS_TEST_TMPDIR/outside" build/lnk
    (cd build && zip -qy ../evil.zip lnk)
    rm build/lnk
    mkdir build/lnk
    printf 'bad\n' > build/lnk/evil.txt
    (cd build && zip -q ../evil.zip lnk/evil.txt)
    rm -rf build
    run unpack_archive evil.zip unpack_zip
    [ "$status" -eq 1 ]
    [ -z "$(ls -A outside)" ]
    [ -z "$(leftover_temp_files)" ]
}

@test "unpack_archive: an existing symlink is replaced, not written through" {
    load_extract
    make_zip
    mkdir outside
    printf 'mine\n' > outside/target.txt
    ln -s outside/target.txt a.txt
    unpack_archive pics.iso unpack_zip
    [ ! -L a.txt ]
    [ "$(cat a.txt)" = "hello" ]
    [ "$(cat outside/target.txt)" = "mine" ]
}

@test "unpack_archive: an existing subfolder keeps its permissions" {
    load_extract
    make_zip
    mkdir sub
    chmod 755 sub
    unpack_archive pics.iso unpack_zip
    [ "$(stat -c %a sub)" = "755" ]
}

@test "unpack_archive: an entry with the archive's own name is refused (D-004)" {
    load_extract
    cd "$BATS_TEST_TMPDIR"
    mkdir src
    printf 'hi\n' > src/self.zip
    (cd src && zip -q ../self.zip self.zip)
    rm -rf src
    cp self.zip original.copy
    run unpack_archive self.zip unpack_zip
    [ "$status" -eq 1 ]
    cmp -s self.zip original.copy
}

# --- Chunks 6-8: the whole script (counting, folders, -r, nested archives) ---

# Create in the test's temp dir: a gzip, a zip and a plain file, misleading names.
make_mix() {
    cd "$BATS_TEST_TMPDIR" || return 1
    printf 'hello\n' | gzip > one.txt
    printf 'zipped\n' > z.txt
    zip -q two.dat z.txt
    rm z.txt
    printf 'plain\n' > plain.txt
}

@test "main: prints the number decompressed, returns the number NOT decompressed" {
    make_mix
    run --separate-stderr "$EXTRACT" one.txt two.dat plain.txt
    [ "$status" -eq 1 ]                    # plain.txt
    [ "$output" = "2" ]
    [ -z "$stderr" ]                       # quiet without -v
    [ "$(cat one.txt.out)" = "hello" ]
    [ "$(cat z.txt)" = "zipped" ]
}

@test "main: -v prints each decompressed file and warns for the others" {
    make_mix
    run --separate-stderr "$EXTRACT" -v one.txt plain.txt missing
    [ "$status" -eq 2 ]
    [[ "$output" == *"decompressed: one.txt"* ]]
    [ "${lines[-1]}" = "1" ]
    [[ "$stderr" == *"plain.txt: not compressed"* ]]
    [[ "$stderr" == *"missing: no such file"* ]]
}

@test "main: an empty file and an unreadable file are NOT decompressed" {
    cd "$BATS_TEST_TMPDIR"
    : > empty
    printf 'hello\n' | gzip > locked
    chmod 000 locked
    run "$EXTRACT" empty locked
    chmod 644 locked
    if [ "$(id -u)" -eq 0 ]; then skip "root can read any file"; fi
    [ "$status" -eq 2 ]
    [ "$output" = "0" ]
}

@test "main: a folder without -r: only its direct children" {
    make_mix
    mkdir -p dir/sub
    mv one.txt plain.txt dir/
    printf 'deep\n' | gzip > dir/sub/deep.gz
    run --separate-stderr "$EXTRACT" -v dir
    [ "$status" -eq 1 ]                    # dir/plain.txt
    [ "${lines[-1]}" = "1" ]
    [ ! -e dir/sub/deep ]
    [[ "$stderr" == *"subfolder skipped (use -r)"* ]]
}

@test "main: a folder with -r: the whole tree" {
    make_mix
    mkdir -p dir/sub
    mv one.txt dir/
    printf 'deep\n' | gzip > dir/sub/deep.gz
    run "$EXTRACT" -r dir
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
    [ "$(cat dir/sub/deep)" = "deep" ]
}

@test "main: a symlink inside a folder is not followed and is counted" {
    make_mix
    mkdir dir
    ln -s ../one.txt dir/link
    run "$EXTRACT" dir
    [ "$status" -eq 1 ]
    [ "$output" = "0" ]
    [ ! -e dir/link.out ]
}

@test "main: a symlink given on the command line is followed" {
    make_mix
    ln -s one.txt link.gz
    run "$EXTRACT" link.gz
    [ "$status" -eq 0 ]
    [ "$(cat link)" = "hello" ]
}

# outer.zip contains inner.gz (a gzip file).
make_nested() {
    cd "$BATS_TEST_TMPDIR" || return 1
    printf 'inner\n' | gzip > inner.gz
    zip -q outer.zip inner.gz
    rm inner.gz
}

@test "main: an archive inside an archive without -r: counted, not unpacked" {
    make_nested
    run --separate-stderr "$EXTRACT" -v outer.zip
    [ "$status" -eq 1 ]
    [ "${lines[-1]}" = "1" ]
    [ -f inner.gz ]
    [ ! -e inner ]
    [[ "$stderr" == *"archive inside an archive"* ]]
}

@test "main: an archive inside an archive with -r: unpacked too" {
    make_nested
    run "$EXTRACT" -r outer.zip
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
    [ "$(cat inner)" = "inner" ]
}

@test "main: -r stops at MAX_DEPTH=3 levels of nesting" {
    cd "$BATS_TEST_TMPDIR"
    # l4.gz inside l3.zip inside l2.zip inside l1.zip (4 levels)
    printf 'x\n' | gzip > l4.gz
    zip -qm l3.zip l4.gz
    zip -qm l2.zip l3.zip
    zip -qm l1.zip l2.zip
    run --separate-stderr "$EXTRACT" -rv l1.zip
    [ "$status" -eq 1 ]                    # l4.gz is too deep
    [ "${lines[-1]}" = "3" ]
    [ ! -e l4 ]
    [[ "$stderr" == *"deeper than 3 levels"* ]]
}

@test "main: more than 255 failures -> exit 255 and a warning even without -v" {
    cd "$BATS_TEST_TMPDIR"
    run --separate-stderr "$EXTRACT" $(seq -f 'missing%g' 1 300)
    [ "$status" -eq 255 ]
    [[ "$stderr" == *"300 files were not decompressed"* ]]
}

@test "main: a leftover temp file is removed when the script is stopped" {
    cd "$BATS_TEST_TMPDIR"
    # A fake gunzip that never finishes, so we can stop extract in the middle.
    mkdir bin
    printf '#!/bin/sh\nexec sleep 5\n' > bin/gunzip
    chmod +x bin/gunzip
    printf 'hello\n' | gzip > data.gz
    # 3>&-: close bats' FD 3 in the background job, or bats waits for it to end.
    PATH="$PWD/bin:$PATH" "$EXTRACT" data.gz 3>&- &
    local pid=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do      # wait up to 2 s for the temp file
        [ -n "$(leftover_temp_files)" ] && break
        sleep 0.2
    done
    [ -n "$(leftover_temp_files)" ]        # the temp file exists while it runs
    kill -TERM "$pid"
    wait "$pid" || true
    [ -z "$(leftover_temp_files)" ]
}

@test "main: an existing file in a folder the zip merges into is not 'created'" {
    cd "$BATS_TEST_TMPDIR"
    mkdir -p src/sub
    printf 'x\n' > src/sub/x.txt
    (cd src && zip -qr ../outer.zip sub)
    rm -rf src
    mkdir sub
    printf 'old\n' | gzip > sub/old.gz        # already there before the run
    run "$EXTRACT" outer.zip
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    [ ! -e sub/old ]
}

@test "main: -v paths have no repeated ./ prefix" {
    make_nested
    run --separate-stderr "$EXTRACT" -rv outer.zip
    [[ "$output" != *"././"* ]]
}

@test "main: -r counts a folder it cannot read, quiet without -v" {
    [ "$(id -u)" -ne 0 ] || skip "root can read any folder"
    cd "$BATS_TEST_TMPDIR"
    mkdir -p d/locked
    chmod 000 d/locked
    run --separate-stderr "$EXTRACT" -r d
    chmod 755 d/locked
    [ "$status" -eq 1 ]
    [ -z "$stderr" ]
}
