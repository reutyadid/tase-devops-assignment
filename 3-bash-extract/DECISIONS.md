# Decisions

Each significant decision gets one entry. Newest at the bottom.

---

## D-001: Detect the archive type with `file --mime-type`

- **Date:** 2026-11-12
- **Context:** The type must be detected only through the `file` command; names and
  extensions have no meaning (R3, R4, R7).
- **Options considered:**
  1. `file -b --mime-type` — one fixed token (e.g. `application/gzip`) that can be an
     exact key in a lookup table / output changed once historically (`application/x-gzip`).
  2. `file -b` + pattern matching (`*gzip*`) — readable / free text meant for humans,
     can change between versions, partial matches can be wrong.
  3. Read the magic bytes ourselves (`head`, `xxd`) — rejected: the assignment requires
     parsing the output of `file`.
- **Decision:** `file -b --mime-type -- "$path"`. The old name `application/x-gzip` is an
  extra table entry pointing to the same tool. `--` protects names that start with `-`.
- **Why:** The mime type is an exact table key, so adding a method stays one line (R8).
- **Trade-offs:** Zip-based formats with their own mime type (e.g. `.docx`) are not
  unzipped. We consider this the expected behavior.
- **Verified on Ubuntu 24.04 (`file` 5.45):** gzip → `application/gzip`,
  bzip2 → `application/x-bzip2`, zip → `application/zip`,
  compress → `application/x-compress`, directory → `inode/directory`.
- **Sources:** [file(1)](https://manpages.ubuntu.com/manpages/noble/man1/file.1.html),
  [libmagic Magdir/compress](https://cgit.freebsd.org/src/tree/contrib/file/magic/Magdir/compress)

---

## D-002: Invoke tools independently of the file name (temp file / temp dir)

- **Date:** 2026-11-12
- **Context:** Some tools depend on the suffix: `gunzip report.txt` fails with
  `unknown suffix -- ignored`. The script must work for any name (R3, R4, R5).
- **Options considered:**
  1. Stream tools write to stdout (`-c`) and we save the output ourselves; zip extracts
     into a folder — works for any name, keeps the original, we control the output name.
  2. Copy the file to a name with the "right" suffix, then run the tool normally —
     extra copies, cleanup, possible name clashes.
  3. `gunzip -S ''` — a documented bug in some versions, and bunzip2 has no such flag.
- **Decision:** Option 1, with two kinds of tools in two tables:
  - `STREAM_TOOLS` (one file in → one file out): gunzip, bunzip2, uncompress — run with
    `-c` into a temp file (`mktemp`) in the **same folder**, then `mv -f` to the final name.
  - `ARCHIVE_TOOLS` (one file in → many files out): unzip — extract into a temp dir
    (`mktemp -d`) in the same folder, then `cp -af "$tmpdir/." "$dir/"` only on success.
  - A `trap ... EXIT` removes leftover temp files/dirs if the script stops (e.g. Ctrl+C).
    The temp variable is reset after each successful `mv`.
  - Temp dirs are removed with `rm -rf -- "${tmpdir:?}"` (fails if the variable is empty).
- **Why:** `>` empties the target before the tool runs, so a corrupt archive would destroy
  an existing good file. Writing to a temp file and renaming only on success prevents this.
  `mv` inside the same folder is a rename, so it is atomic.
- **Trade-offs:** For zip, `cp` is not atomic and the temp dir needs extra disk space
  for a moment. `cp` is used instead of `mv` because `mv` cannot merge into an existing
  folder. A few more lines of code.
- **Sources:** [gzip(1) -c](https://manpages.ubuntu.com/manpages/noble/man1/gzip.1.html),
  [Red Hat bug 572100](https://bugzilla.redhat.com/show_bug.cgi?id=572100),
  [Steam `rm -rf` incident](https://github.com/valvesoftware/steam-for-linux/issues/3671)

---

## D-003: Output file name for stream tools

- **Date:** 2026-11-12
- **Context:** With `-c` the tool no longer chooses the output name, so we must (R5, R6).
  The name must be deterministic, otherwise "files with the same name are overwritten"
  (R6) would never happen.
- **Options considered:**
  1. Strip a known compression suffix (`.gz`, `.bz2`, `.Z`); if there is none, add `.out`
     — consistent for all tools; same convention as bunzip2.
  2. Use the original name stored in the gzip header — only gzip stores it.
  3. Replace the archive in place under the same name — destroys the original.
  4. Always add `.out` — simplest, but `data.gz` → `data.gz.out` is surprising.
- **Decision:** Option 1. `data.gz` → `data`, `report.txt` → `report.txt.out`.
  An existing file with that name is overwritten (e.g. on a second run).
- **Why:** Predictable, matches what the tools themselves do, never overwrites the archive.
- **Trade-offs:** The `.out` suffix is a bit ugly. Zip is not affected (names come from
  inside the archive).
- **Sources:** [bzip2(1) — `.out` convention](https://manpages.ubuntu.com/manpages/noble/man1/bzip2.1.html)

---

## D-004: Keep the original archive in place

- **Date:** 2026-11-12
- **Context:** The assignment does not say what happens to the archive after extraction.
  gunzip/bunzip2 delete it by default, unzip keeps it.
- **Options considered:**
  1. Keep it in place — safe, consistent, no extra code (comes free with `-c`).
  2. Delete it after success — like plain gunzip; risky together with `-r`.
  3. Move it to another folder — not requested; name clashes with `-r`; standard tools
     never do this.
- **Decision:** Keep the original archive exactly where it is.
- **Why:** Least surprise and safest. R9 suggests touching nothing beyond what is needed.
- **Trade-offs:** The folder holds both the archive and the extracted files.

---

## D-005: Overwrite behavior and permissions

- **Date:** 2026-11-12
- **Context:** Existing files must be overwritten (R6) and the script must never stop to
  ask a question.
- **Decision:**
  - The tools always write into a new, empty place (D-002). Overwriting is done by
    `mv -f` (stream tools) and `cp -af` (zip).
  - `unzip -o`: an archive can contain the same name twice; without `-o` unzip stops and
    asks `replace a.txt?` and the script hangs.
  - The extracted file gets the permissions of the original archive:
    `chmod --reference="$file" "$tmp"` (`mktemp` creates `rw-------` files). This is what
    gunzip itself does.
  - If overwriting is impossible (e.g. the archive has a file `logs` but a folder `logs`
    already exists), the archive counts as NOT decompressed and a specific warning is
    printed (only with `-v`, like all other warnings).
- **Sources:** [unzip(1) -o](https://manpages.ubuntu.com/manpages/noble/man1/unzip.1.html),
  [chmod --reference](https://www.gnu.org/software/coreutils/manual/html_node/chmod-invocation.html),
  [cp](https://www.gnu.org/software/coreutils/manual/html_node/cp-invocation.html)

---

## D-006: Walk folders with `find` + `mapfile`; symlink policy

- **Date:** 2026-11-12
- **Context:** Directories must be processed (R10); with `-r` the whole tree (R14).
  Names can contain spaces or newlines, start with a dot, folders can be empty, and
  symlinks can create loops.
- **Options considered:**
  1. `find` + `mapfile -d '' -t paths < <(find ... -print0)` — standard tool, handles hidden
     files, empty folders and symlinks by itself; `-maxdepth 1` switches off recursion.
  2. Glob (`"$dir"/*`) with `shopt -s nullglob dotglob` in a recursive function — fewer
     constructs, but symlink handling must be written by hand.
- **Decision:** Option 1. The list is read into an array first, then processed.
  - No `find | while read` pipe: each side of a pipe runs in a subshell, so counter
    updates inside the loop are lost (verified: `count=0` after 5 files).
  - Building the full list first means files created during extraction are not picked up
    by the folder walk.
  - Symlinks: not followed inside folders. A symlink given on the command line **is**
    followed (`find -H`). For a symlink to a file, the output goes to the symlink's folder
    and the name is derived from the symlink's name.
- **Why:** `find` is the standard tool for this and worth knowing well.
- **Trade-offs:** `mapfile`, `-print0`, `-d ''` and `< <(...)` must be understood and
  explained.
- **Sources:** [BashFAQ/020](https://mywiki.wooledge.org/BashFAQ/020),
  [BashFAQ/024](https://mywiki.wooledge.org/BashFAQ/024),
  [find: symbolic links](https://www.gnu.org/software/findutils/manual/html_node/find_html/Symbolic-Links.html),
  [mapfile](https://www.gnu.org/software/bash/manual/html_node/Bash-Builtins.html#index-mapfile)

---

## D-007: What counts as decompressed / NOT decompressed

- **Date:** 2026-11-12
- **Context:** R11 asks for the number of archives decompressed; R12 for the number of
  files NOT decompressed. The assignment does not define edge cases.
- **Decision:** One rule: every item the user asked for (directly or through a folder)
  that was not fully decompressed is counted. Folders are containers and are not counted.
  Plain files that came out of an archive are a result, not a failure.

  | Case                                                        | Counted as          |
  |-------------------------------------------------------------|---------------------|
  | Archive extracted successfully (including nested ones)      | decompressed        |
  | Plain file given, or inside a given folder                  | NOT decompressed    |
  | Missing file                                                | NOT decompressed    |
  | Unsupported archive type (xz, tar, 7z, ...)                 | NOT decompressed    |
  | Symlink found inside a folder                               | NOT decompressed    |
  | Empty file (`inode/x-empty`)                                | NOT decompressed    |
  | Unreadable file (no permission)                             | NOT decompressed    |
  | Archive that failed (corrupt, missing tool, cp conflict)    | NOT decompressed    |
  | Nested archive without `-r`                                 | NOT decompressed    |
  | Archive deeper than `MAX_DEPTH`                             | NOT decompressed    |
  | Plain file that came out of an archive                      | not counted         |
  | The folder itself                                           | not counted         |
  | Subfolder without `-r`                                      | not counted (`-v` note) |

- **Why:** Exit code 0 means "everything you asked for was fully decompressed"; a non-zero
  code points exactly at things that need attention.
- **Trade-offs:** One extra rule to explain ("files from an archive are a result").

---

## D-008: Exit code above 255

- **Date:** 2026-11-12
- **Context:** R12 returns a count, but exit codes are 0–255 and wrap around
  (verified: `exit 256` → 0, `exit 300` → 44). 256 failures would look like success.
- **Options considered:**
  1. Cap at 255 — 0 always means full success / exact count lost above 255.
  2. Plain `exit $n` — wraps; rejected.
  3. Exit 1 on any failure — contradicts R12; rejected.
- **Decision:** Cap at 255. When the cap is applied, print a warning to stderr even
  without `-v` (e.g. `Warning: 300 files were not decompressed (exit code capped at 255)`),
  because it is about the exit code itself, not about a single file. Documented in README.
- **Known ambiguity (README):** some codes also have a conventional meaning in bash —
  2 (usage error, D-010), 126 (not executable), 127 (command not found),
  130 (Ctrl+C = 128 + 2). The assignment uses every number for the count, so this cannot
  be fully avoided.
- **Sources:** [Bash: Exit Status](https://www.gnu.org/software/bash/manual/html_node/Exit-Status.html),
  [TLDP: Exit codes with special meanings](https://tldp.org/LDP/abs/html/exitcodes.html)

---

## D-009: Nested archives and folders (only with `-r`) + depth limit

- **Date:** 2026-11-12
- **Context:** An archive can contain other archives and folders. The assignment
  ("unpack all archives in them", "-r - recursive") is ambiguous about this.
- **Options considered:**
  1. Never re-extract newly created archives — simplest.
  2. Always re-extract, with a depth limit.
  3. Re-extract only with `-r`, with a depth limit.
- **Decision:** Option 3.
  - **Without `-r`:** the given files and the direct children of given folders. After an
    archive is extracted, its output is checked one level: a nested archive is **not**
    extracted and counts as NOT decompressed (`-v` warning: use `-r`). Subfolders are not
    entered.
  - **With `-r`:** folders in folders, archives in archives, archives in folders and
    folders in archives — all the way down, up to `MAX_DEPTH=3` levels of archive nesting
    (depth 1 = an archive given by the user or found in a folder). A deeper archive is not
    extracted, counts as NOT decompressed, and gets a `-v` warning.
  - Only what was **just created** is checked (the temp file / temp dir from D-002); the
    folder is never re-scanned.
- **Why:** The original archive stays in place (D-004), so re-scanning the folder would
  find it again and loop forever. Archives that contain themselves ("quine" zips) and zip
  bombs make a depth limit necessary.
- **Trade-offs:** About 10–15 more lines of code; more test cases.

---

## D-010: Argument parsing and error handling

- **Date:** 2026-11-12
- **Context:** Synopsis `extract [-h] [-r] [-v] file [file...]` (R2, R15); one failing file
  must not stop the whole run.
- **Options considered (parsing):**
  1. `getopts` builtin — standard, short options, handles `-rv`.
  2. External `getopt` — long options, not needed; extra dependency.
  3. Manual `while`/`case` loop — more code, no `-rv` combining.
- **Options considered (strict mode):**
  1. `set -euo pipefail` — common advice, but `-e` has many non-obvious exceptions;
     verified: `((c++))` with `c=0` kills the script silently.
  2. `set -uo pipefail` without `-e`, with explicit `if` checks.
  3. No `set` at all — loses cheap protection.
- **Decision:**
  - `getopts ":hrv"`; options must come before file names (getopts stops at the first
    non-option — documented in README).
  - `-h` → help to stdout, exit 0. No files, or an unknown option → message + usage to
    stderr, exit 2 (the usual "incorrect usage" code).
  - `set -uo pipefail`, no `-e`. Every tool call is checked with `if`, because each
    result must be counted anyway. Table lookups use `${TABLE[$key]:-}` so a missing key
    does not trigger `-u`.
- **Why:** The script's job is to continue after failures and count them; `-e` works
  against that.
- **Trade-offs:** Must explain in the interview why there is no `-e`.
- **Sources:** [getopts](https://www.gnu.org/software/bash/manual/html_node/Bourne-Shell-Builtins.html#index-getopts),
  [The Set Builtin](https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html),
  [BashFAQ/105](https://mywiki.wooledge.org/BashFAQ/105)

---

## D-011: Dependencies

- **Date:** 2026-11-12
- **Context:** The script calls external tools (R7); some are missing on a clean
  Ubuntu 24.04.
- **Findings:** On Debian/Ubuntu, `uncompress` is part of the `gzip` package (a wrapper
  around `gzip -d`). The `ncompress` package provides `compress` and installs its own
  decompressor as `uncompress.real` to avoid the clash.
- **Decision:**
  - Runtime: `file`, `gzip` (gunzip, uncompress), `bzip2` (bunzip2), `unzip`.
  - Tests only: `zip`, `ncompress` (to create `.Z` fixtures), `bats`.
  - Lint: `shellcheck`.
  - Install: `sudo apt-get install -y bzip2 unzip zip ncompress shellcheck bats`.
  - Only `file` is checked at startup (exit 2 if missing). A missing decompressor makes
    that archive count as NOT decompressed (bash prints `command not found`); other types
    still work.
  - Tested versions are listed in README instead of pinning apt packages.
- **Sources:** [ncompress (noble)](https://packages.ubuntu.com/noble/ncompress),
  [compress / uncompress.real](https://manpages.ubuntu.com/manpages/noble/man1/compress.1.html),
  [debian-devel: gzip provides uncompress](https://lists.debian.org/debian-devel/1997/01/msg00005.html)

---

## D-012: Testing with bats-core

- **Date:** 2026-11-12
- **Context:** The reviewer must be able to verify everything quickly, with one command.
- **Options considered:**
  1. Plain Bash test script — no dependencies, own assert helpers.
  2. bats-core — the standard Bash testing framework, TAP output, `run` captures
     `$status` / `$output`.
  3. Manual commands in README only — no automation; rejected.
- **Decision:** bats-core, installed from apt (`bats` 1.10.0 on Ubuntu 24.04), without the
  helper libraries (`bats-assert`, `bats-support`). Fixtures are generated at test time
  with misleading names (nothing binary is committed). `shellcheck` runs on the script and
  the tests.
- **Why:** Industry standard for testing shell scripts; readable tests.
- **Trade-offs:** One more dependency; must understand how `run` works.
- **Open:** GitHub Actions (shellcheck + bats on push) — to be decided at the end.
- **Sources:** [bats-core](https://github.com/bats-core/bats-core),
  [bats-core docs](https://bats-core.readthedocs.io/en/stable/),
  [bats (noble)](https://packages.ubuntu.com/noble/bats)
