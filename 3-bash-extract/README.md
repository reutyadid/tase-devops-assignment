# Task 3: `extract` (Bash)

A Bash script that unpacks gzip, bzip2, zip and compress files. It chooses the tool from
the **content** of each file (the `file` command), never from its name or extension. It
can walk folders, recursively with `-r`, and unpack archives inside archives.

## Usage

```
extract [-h] [-r] [-v] file [file...]
```

| Option | Meaning |
|--------|---------|
| `-h`   | Show the help and exit 0 |
| `-r`   | Recursive: go into subfolders, and unpack archives found inside archives (up to 3 levels) |
| `-v`   | Verbose: print each file decompressed (stdout), warn for each file NOT decompressed (stderr) |

- **Output (stdout):** the number of archives decompressed (last line).
- **Exit code:** the number of files NOT decompressed, capped at 255. `2` is also used for
  a usage error (unknown option, no files), with a message on stderr.
- Options must come **before** the file names (`getopts` stops at the first file name).

Supported types:

| `file --mime-type`        | Tool         | Output |
|---------------------------|--------------|--------|
| `application/gzip`        | `gunzip`     | `name.gz` → `name`, otherwise `name.out` |
| `application/x-bzip2`     | `bunzip2`    | `name.bz2` → `name`, otherwise `name.out` |
| `application/x-compress`  | `uncompress` | `name.Z` → `name`, otherwise `name.out` |
| `application/zip`         | `unzip`      | the files inside the zip |

The output is written next to the archive; existing files with the same name are
overwritten. The original archive is always kept.

## Prerequisites

Tested on Ubuntu 24.04 (WSL2), Bash 5.2.

| Tool | Version | Package | Needed for |
|------|---------|---------|------------|
| `file` | 5.45 | file | runtime (required) |
| `gunzip`, `uncompress` | 1.12 | gzip | runtime |
| `bunzip2` | 1.0.8 | bzip2 | runtime |
| `unzip` | 6.00 | unzip | runtime |
| `zip`, `compress` | 3.0, 5.0 | zip, ncompress | tests only (to create fixtures) |
| `bats` | 1.10.0 | bats | tests |
| `shellcheck` | 0.9.0 | shellcheck | lint |

```bash
sudo apt-get update
sudo apt-get install -y file gzip bzip2 unzip zip ncompress bats shellcheck
```

Requires Bash 4.4 or newer (associative arrays, `mapfile -d`).

## Quick start

```bash
cd 3-bash-extract
printf 'hello\n' | gzip > /tmp/report.txt      # a gzip file with a misleading name
./extract -v /tmp/report.txt
# extract: decompressed: /tmp/report.txt
# 1
cat /tmp/report.txt.out                         # hello
```

## How to verify

```bash
cd 3-bash-extract
bats tests                                      # expected: 1..66, all "ok"
shellcheck -x extract tests/extract.bats        # expected: no output, exit 0
```

## How to add a new method (R8)

1. Add one line to a table in `extract`:
   - one file in → one file out (the tool supports `-c`):
     `[application/x-xz]="unxz"` in `STREAM_TOOLS`
   - one file in → many files out: `[application/x-7z-compressed]="unpack_7z"` in
     `ARCHIVE_TOOLS`, plus a one-line function `unpack_7z() { 7z x -y "-o$2" "$1"; }`
2. Add the type to the `Supported:` line in `usage()`.
3. Optional: add the suffix (`*.xz)`) to `output_name`; otherwise the output is `name.out`.

## Project structure

```
3-bash-extract/
├── extract              # the script
├── tests/extract.bats   # bats tests (fixtures are created at test time)
├── REQUIREMENTS.md      # assignment text + requirements matrix
├── DECISIONS.md         # design decisions (D-001 ... D-012)
├── TROUBLESHOOTING.md   # real problems and fixes (T-001 ... T-006)
└── README.md
```

## Requirements coverage

See [REQUIREMENTS.md](REQUIREMENTS.md): every requirement, where it is implemented, and
its test.

## Design decisions

See [DECISIONS.md](DECISIONS.md). Key points:

- The type comes from `file -L -b --mime-type` and is an exact key in a table (D-001).
- Stream tools read the file from stdin into a temp file, then `mv` renames it: a corrupt
  archive never destroys an existing file (D-002).
- What counts as decompressed / NOT decompressed is listed in D-007. Plain files that
  came out of an archive are a result, not a failure.
- `set -uo pipefail` without `-e`, because the script must continue after a failure and
  count it (D-010).

## Security notes

- All variables are quoted; names with spaces, newlines, or a leading `-` are handled.
- Zip: `../` and absolute paths inside a zip stay inside the folder (unzip strips them);
  an existing symlink is replaced, not written through; an encrypted zip fails at once
  instead of waiting for a password.
- Symlinks inside folders are not followed; a nesting limit (3) stops nested zip bombs
  and self-containing archives. It does not stop a one-level zip bomb (one small zip that
  expands to many GB); see Known limitations.
- Temp files are created with `mktemp` and removed by a `trap` on exit (also on Ctrl+C).

## Known limitations

- Exit code: above 255 failures the code is capped at 255 (warning on stderr). The codes
  2, 126, 127 and 130 also have usual shell meanings (usage error, not executable,
  command not found, Ctrl+C); with this assignment they can also be a count.
- A zip that has a conflict (a file vs. a folder with the same name) is partly copied
  and counts as NOT decompressed.
- A zip is written twice (temp folder, then copy): it needs twice its size in free space.
  There is no size limit, so a one-level zip bomb can fill the disk.
- Inside one folder, an output can overwrite another file that is still waiting in the
  list (e.g. `b.gz` → `b` when `b` is also an archive). The result then depends on the
  order of `find` (D-006). The assignment asks for overwriting, so this is accepted.
- A name with a newline right before the suffix gets a wrong output name (D-003).
- Archive types other than the four (xz, tar, 7z, ...) count as NOT decompressed.
