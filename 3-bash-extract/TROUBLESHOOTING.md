# Troubleshooting

Real problems I hit while building this, and how I solved them.

---

## T-001: `sudo apt-get install` fails when run from inside Claude Code

- **Symptom:**
  ```
  sudo: a terminal is required to read the password; either use the -S option to read from standard input or configure an askpass helper
  sudo: a password is required
  ```
- **Root cause:** The command ran without a real terminal, so `sudo` had nowhere to ask
  for the password.
- **Fix:** Ran the install command in a normal WSL terminal window. Did not use `sudo -S`
  (it would expose the password in shell history / logs).
- **How to verify:** `command -v file gunzip uncompress bunzip2 unzip zip compress shellcheck bats`
  prints nine paths (runtime tools, test-only tools and the linter).
- **Lesson:** Commands that need a password go in a real terminal.

---

## T-002: bats test fails with `mktemp: command not found`

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

## T-003: ShellCheck warnings that are false alarms (SC2034, SC2154, SC1091)

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
