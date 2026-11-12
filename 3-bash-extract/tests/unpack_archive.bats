#!/usr/bin/env bats
# Unpacking with an archive tool: unzip (D-002, D-005).
# Run all tests from the repo root:  bats 3-bash-extract/tests

# ShellCheck cannot see across files, so two warnings are false alarms here:
# SC2154: $status/$output/$stderr are set by bats "run", $EXTRACT by test_helper.
# SC2034: $verbose/$recursive are set here and read by the sourced script.
# shellcheck disable=SC2154,SC2034

load test_helper

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
