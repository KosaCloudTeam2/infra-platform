#!/bin/bash
set -e

ceph osd pool create cephfs_metadata 32
ceph osd pool create cephfs_data 64

ceph fs new cephfs cephfs_metadata cephfs_data

ceph fs ls
