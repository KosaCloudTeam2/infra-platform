#!/bin/bash
set -e

for TEAM in 1 2 3 4
 do
  POOL="rbd-team${TEAM}"

  ceph osd pool create "${POOL}" 32

  rbd pool init "${POOL}"

  ceph osd pool application enable "${POOL}" rbd

done

ceph osd pool ls detail
