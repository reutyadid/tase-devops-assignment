# Troubleshooting

Real problems I hit while building this, and how I solved them.

---

## T-001: bats test fails with `mktemp: command not found`

- **Symptom:** The test for a missing `file` command failed:
  ```
  `PATH="/nonexistent" run --separate-stderr "$BASH" "$EXTRACT" a.gz' failed with status 127
  /usr/lib/bats-core/test_functions.bash: line 362: mktemp: command not found
  ```
- **Root cause:** `VAR=value command` sets the variable for that command. Here the command
  was bats' own `run` function, so bats itself lost its PATH and could not find `mktemp`.
- **Fix:** Change PATH only for the script under test:
  `run --separate-stderr env PATH="/nonexistent" "$BASH" "$EXTRACT" a.gz`
  (`env` is found with the normal PATH, then starts bash with the new PATH).
- **How to verify:** `bats 3-bash-extract/tests` → all tests `ok`.
- **Lesson:** When overriding PATH in a test, make sure it applies only to the program
  under test, not to the test framework.

---

## T-002: ShellCheck warnings that are false alarms (SC2034, SC2154, SC1091)

- **Symptom:**
  ```
  SC2034 (warning): verbose appears unused.
  SC2154 (warning): stderr is referenced but not assigned.
  SC1091 (info): Not following: ../extract: openBinaryFile: does not exist
  ```
- **Root cause:**
  - SC2034: `verbose` / `recursive` are set by getopts but only used in later chunks.
  - SC2154: `$stderr` is set by bats (`run --separate-stderr`); `$verbose` / `$recursive`
    come from the sourced script. ShellCheck cannot see either.
  - SC1091: a `# shellcheck source=` path is resolved from the current directory by default.
  - A `# shellcheck disable=` directive placed above one command applies only to that
    command; to apply it to the whole file it must come before the first command.
- **Fix:**
  - `extract`: `# shellcheck disable=SC2034` only above the `getopts` loop (not file-wide,
    so typos in other variables are still caught), marked TEMPORARY (remove in chunk 6).
  - `extract.bats`: file-wide `disable=SC2154` with a comment explaining why, and
    `# shellcheck source-path=SCRIPTDIR` so `source=../extract` is resolved from the test file.
- **How to verify:** `shellcheck -x 3-bash-extract/extract 3-bash-extract/tests/extract.bats`
  → no output, exit 0 (also when run from inside `3-bash-extract/`).
- **Lesson:** Disable a ShellCheck rule only with a comment that says why, and as narrowly
  as possible.

---

## T-003: `compress` fails in the test fixtures with exit code 2

- **Symptom:** All tests that create fixtures failed:
  ```
  `make_fixtures' failed with status 2
  ```
- **Root cause:** `compress` returns 2 when the output is larger than the input
  ("if the last file is larger after (attempted) compression, the status is 2").
  A 6-byte "hello" file grows to 10 bytes. bats treats any non-zero status as a failure.
- **Fix:** `compress -f` (force) in `make_fixtures`. The output is a valid
  `application/x-compress` file either way.
- **How to verify:** `printf 'hello\n' | compress -f > /dev/null; echo $?` → `0`.
- **Lesson:** Read the EXIT STATUS section of a tool's man page before relying on `$?`.

---

## T-004: Associative arrays disappear when the script is sourced from a function

- **Symptom (found before it broke a test):** loading the script through a helper
  function (`load_extract`) would leave `STREAM_TOOLS` / `ARCHIVE_TOOLS` empty:
  ```
  $ bash -c 'f() { declare -A T=([a]=1); }; f; echo "${T[a]:-<gone>}"'
  <gone>
  ```
- **Root cause:** `declare` inside a function creates a **local** variable. `source`
  runs the file's top-level code inside the calling function, so the tables became
  local to `load_extract` and were removed when it returned.
- **Fix:** `declare -gA` (`-g` = global) for both tables.
- **How to verify:** `bats 3-bash-extract/tests` → the `tables:` tests pass.
- **Lesson:** Code that may be sourced should declare its globals with `-g`.

---

## T-005: Extracting a zip changed the permissions of the user's folder to 700

- **Symptom (found in a test before it was released):**
  ```
  $ stat -c %a dst      # before: 755
  700
  ```
- **Root cause:** the first plan copied with `cp -af "$tmpdir/." "$dir/"`. The trailing
  `/.` means "the folder itself", and `-a` keeps its attributes. `mktemp -d` creates
  folders with mode 700, so that mode was copied onto the user's folder.
- **Fix:** copy only the items inside the temp folder, and without `-a` (it would still
  copy a zip folder's mode onto an existing subfolder, one level down):
  `find "$tmpdir" -mindepth 1 -maxdepth 1 -exec cp -Rf --remove-destination --preserve=timestamps -t "$dir" -- {} +`
- **How to verify:** `bats 3-bash-extract/tests` → the test
  `unpack_archive: the permissions of the target folder do not change` passes
  (it fails with the old `cp` line).
- **Lesson:** `cp -a src/. dst/` copies the attributes of `src` itself, not only its contents.

---

## T-006: `ls -A` in a test shows a file I did not create

- **Symptom:**
  ```
  LS: broken.zip separate-stderr-51mano
  ```
- **Root cause:** `run --separate-stderr` stores stderr in a temp file inside
  `$BATS_TEST_TMPDIR`, the same folder the test works in.
- **Fix:** check for the specific files the test cares about (`[ ! -e a.txt ]`), not for
  the exact folder listing.
- **How to verify:** `bats 3-bash-extract/tests` → all tests `ok`.
- **Lesson:** do not assume a test framework's temp folder is empty.
