# Requirements — Task 3: Bash `extract`

## Assignment text (verbatim — do not edit)

```text
BASH
Write a bash script called extract which can unpack multiple packed files,
and even traverse folders recursively and unpack all archives in them - regardless of the
specific algorithm that was used when packing them. Following is the exact synopsis:
extract [-h] [-r] [-v] file [file...]
Given a list of filenames as input, this script queries each target file (parsing the output of the
file command) for the type of compression used on it. Then the script automatically invokes
the appropriate decompression command, putting files in the same folder. If files with the
same name already exist, they are overwritten.
Unpack should support 4 unpacking options - gunzip, bunzip2, unzip, uncompress.
Adding more options should be VERY simple.
Note that file names and extensions have no meaning - the only way to know what method
to use is through the file command!
If a target file is not compressed, the script takes no other action on that particular file.
If the target is a directory then it decompresses all files in it using same method.
Command echos number of archives decompressed
Command returns number of files it did NOT decompress
Additional switches:
-v - verbose - echo each file decompressed & warn for each file that was NOT
decompressed
-r - recursive - will traverse contents of folders recursively, performing unpack on each.
-h - Should receive a HELP notice
```

## Requirements matrix

Status values: `Planned` → `In progress` → `Done`.

| ID  | Requirement (from the assignment)                       | Implementation (planned)                         | Decision     | Test (bats)                              | Status  |
|-----|---------------------------------------------------------|--------------------------------------------------|--------------|------------------------------------------|---------|
| R1  | Script named `extract`                                  | `3-bash-extract/extract`                         | —            | all tests run `tests/../extract`         | Done    |
| R2  | Synopsis: `extract [-h] [-r] [-v] file [file...]`       | `parse_args` (`getopts ":hrv"`), `usage()`       | D-010        | usage / flag tests                       | In progress |
| R3  | Detect the type only via `file` (names have no meaning) | `file -L -b --mime-type --`                      | D-001        | fixtures with misleading names           | In progress |
| R4  | Invoke the right decompression command automatically   | `STREAM_TOOLS` / `ARCHIVE_TOOLS` lookup          | D-001, D-002 | one test per method                      | Planned |
| R5  | Put extracted files in the same folder                  | `output_name` (same folder); temp file / temp dir in the target's own folder | D-002, D-003 | `output_name` tests; output location tests | In progress |
| R6  | Overwrite files with the same name                      | `mv -f` / `cp -af`                               | D-005        | run twice, existing file is replaced     | Planned |
| R7  | Support gunzip, bunzip2, unzip, uncompress              | 4 table entries (+ `application/x-gzip` alias)   | D-001, D-011 | gz / bz2 / zip / Z fixtures              | In progress |
| R8  | Adding a method must be VERY simple                     | one line in a table + the `Supported:` help line (+ optional suffix in `output_name`) | D-002        | README shows how                         | In progress |
| R9  | Not compressed → no other action on that file           | not in a table → count only, file untouched      | D-007        | plain file is unchanged                  | Planned |
| R10 | Directory → decompress all files in it                  | `process_dir` (`find -maxdepth 1`)               | D-006        | folder without `-r`                      | Planned |
| R11 | Echo the number of archives decompressed                | `decompressed` counter + final echo              | D-007        | stdout checked in tests                  | Planned |
| R12 | Return the number of files NOT decompressed             | `not_decompressed` counter, capped at 255        | D-007, D-008 | exit code checked; cap test              | Planned |
| R13 | `-v`: echo each decompressed, warn each NOT decompressed | `verbose` flag, warnings to stderr              | D-007        | `-v` output tests                        | Planned |
| R14 | `-r`: traverse folders recursively                      | `find` without `-maxdepth` + nested archives     | D-006, D-009 | nested folders / archives, depth limit   | Planned |
| R15 | `-h`: help notice                                       | `usage()`, exit 0                                | D-010        | `-h` test                                | Done    |

## Interpretations of ambiguous points

The assignment leaves some behavior open. Each interpretation is recorded in
[DECISIONS.md](DECISIONS.md):

- Output file name for stream tools (gzip / bzip2 / compress) → D-003
- What happens to the original archive → D-004
- What counts as "NOT decompressed" → D-007
- Exit codes above 255 → D-008
- Archives inside archives → D-009
- Usage errors and their exit code → D-010
