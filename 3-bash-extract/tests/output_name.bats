#!/usr/bin/env bats
# Output file name for stream tools (D-003).
# Run all tests from the repo root:  bats 3-bash-extract/tests

# ShellCheck cannot see across files, so two warnings are false alarms here:
# SC2154: $status/$output/$stderr are set by bats "run", $EXTRACT by test_helper.
# SC2034: $verbose/$recursive are set here and read by the sourced script.
# shellcheck disable=SC2154,SC2034

load test_helper

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
