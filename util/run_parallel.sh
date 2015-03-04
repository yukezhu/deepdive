#!/usr/bin/env bash
# run_parallel.sh -- Runs command to process the input lines in parallel
# Usage:
# > run_parallel.sh INPUT_FILE OUTPUT_PREFIX OUTPUT_SUFFIX NUM_PROCS COMMAND [ARG...]
# 
# Example:
# > run_parallel.sh input.tsv out- .tsv 20 python3 /path/to/udf.py
# Launches 20 python3 processes running /path/to/udf.py to handle the lines of
# input.tsv in parallel, where each process writes output to its own out-*.tsv.
# Unless input.tsv exists, a named pipe of the same name is created, so the
# input lines can be supplied later by another process, such as gpfdist.
#
# Author: Jaeho Shin <netj@cs.stanford.edu>
# Created: 2015-02-25
set -eu

# Parse input arguments.
input=$1; shift
output_prefix=$1; shift
output_suffix=$1; shift
numprocs=$1; shift
# And some constants.
worker_suffix=-p.

# Unless the input already exists, create it as a named pipe.
[[ -e "$input" ]] || mkfifo "$input"

# Create named pipes for individual workers.
rm -f "$input$worker_suffix"*
seq $numprocs | split -n r/$numprocs - "$input$worker_suffix"
for p in "$input$worker_suffix"*; do rm -f "$p"; mkfifo "$p"; done

# Spawn worker processes waiting input from the named pipes.
for p in "$input$worker_suffix"*; do
    o="${output_prefix}${p##*$worker_suffix}${output_suffix}"
    exec "$@" <"$p" >"$o" &
    echo "$o"
done

# Use mkmimo to spread the input lines to workers' named pipes.
# See: https://www.npmjs.com/package/mkmimo
mkmimo "$input" \> "$input$worker_suffix"* &
# Note that split(1) cannot be used with named pipe as its round-robin writes
# will block on the first straggler it encounters, and the other workers will
# become idle, so there won't be any parallelism.

# Wait until all processes finish.
wait

# Clean up the named pipes created by this script.
rm -f "$input$worker_suffix"*
! [[ -p "$input" ]] || rm -f "$input"
