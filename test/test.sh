#!/bin/bash

# Run this from the parent directory
# with `make test`.

set -e

tb=/tmp/rucksack.test
to=/tmp/rucksack.test.stdout
te=/tmp/rucksack.test.stderr

err() {
  echo
  echo "-- stdout --"
  cat $to
  echo "-- stderr --"
  cat $te
  echo "-- stderr --"
  echo "ERROR: ${0}:${1} ${ERR}"
  exit 1
}

.() {
  echo -n "."
}

trap 'err $LINENO' ERR

### crystal run

unset RUCKSACK_MODE

crystal run test/test.cr >$to 2>$te
.
RUCKSACK_MODE=0 crystal run test/test.cr >$to 2>$te
.
! RUCKSACK_MODE=1 crystal run test/test.cr >$to 2>$te
.
! RUCKSACK_MODE=2 crystal run test/test.cr >$to 2>$te
.

### crystal build w/o rucksack attached

crystal build test/test.cr -o ${tb}
.
RUCKSACK_MODE=0 $tb >$to 2>$te
.
! RUCKSACK_MODE=1 $tb >$to 2>$te
.
! RUCKSACK_MODE=2 $tb >$to 2>$te
.

### crystal build with rucksack attached

cat .rucksack >>$tb
RUCKSACK_MODE=0 $tb >$to 2>$te
.
RUCKSACK_MODE=1 $tb >$to 2>$te
.
RUCKSACK_MODE=2 $tb >$to 2>$te
.

echo

