#!/bin/sh
set -ue

find . '(' -name configure.ac -o -name configure.in ')' -type f -print0 | sort -z | xargs -0 autoreconf -fvi "$@"
