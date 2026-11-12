# shellcheck shell=bash
# Shared setup and helpers for all the .bats files (loaded with "load test_helper").
# Resolve "source" paths relative to this file, not the current directory.
# shellcheck source-path=SCRIPTDIR

bats_require_minimum_version 1.5.0   # needed for "run --separate-stderr"

# Runs before every test.
setup() {
    EXTRACT="$BATS_TEST_DIRNAME/../extract"
}

# Load the script's functions and tables into the test (main does not run).
load_extract() {
    # shellcheck source=../extract
    source "$EXTRACT"
}

# Create one file of each type, with misleading names, in the test's temp dir.
make_fixtures() {
    cd "$BATS_TEST_TMPDIR" || return 1
    printf 'hello\n' > src.txt
    printf 'hello\n' | gzip > report.txt
    printf 'hello\n' | bzip2 > photo.png
    printf 'hello\n' | compress -f > notes.doc   # -f: see T-003
    zip -q - src.txt > backup.tar
}

# Print the temp files left in the current folder (nothing = clean).
leftover_temp_files() {
    find . -name '.extract.*'
}

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

# Create in the test's temp dir: a gzip, a zip and a plain file, misleading names.
make_mix() {
    cd "$BATS_TEST_TMPDIR" || return 1
    printf 'hello\n' | gzip > one.txt
    printf 'zipped\n' > z.txt
    zip -q two.dat z.txt
    rm z.txt
    printf 'plain\n' > plain.txt
}

# outer.zip contains inner.gz (a gzip file).
make_nested() {
    cd "$BATS_TEST_TMPDIR" || return 1
    printf 'inner\n' | gzip > inner.gz
    zip -q outer.zip inner.gz
    rm inner.gz
}
