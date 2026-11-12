#!/usr/bin/env bats
# The whole script: counting, folders, -r, nested archives, exit code (D-007 - D-009).
# Run all tests from the repo root:  bats 3-bash-extract/tests

# ShellCheck cannot see across files, so two warnings are false alarms here:
# SC2154: $status/$output/$stderr are set by bats "run", $EXTRACT by test_helper.
# SC2034: $verbose/$recursive are set here and read by the sourced script.
# shellcheck disable=SC2154,SC2034

load test_helper

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
