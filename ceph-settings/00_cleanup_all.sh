#!/bin/bash
set -e

echo "===== STOP RGW ====="
pkill -9 radosgw || true
systemctl stop ceph-radosgw@ceph1 || true
systemctl disable ceph-radosgw@ceph1 || true


echo "===== DELETE RGW USERS ====="
radosgw-admin user list 2>/dev/null | jq -r '.[]' | while IFS= read -r user; do
  radosgw-admin user rm --uid="$user" --purge-data || true
done


echo "===== DELETE POOLS ====="
ceph osd pool ls | while IFS= read -r p; do
  if [[ "$p" != ".mgr" ]]; then
    ceph osd pool delete "$p" "$p" --yes-i-really-really-mean-it || true
  fi
done


echo "===== DELETE CEPHFS ====="
ceph fs rm cephfs --yes-i-really-mean-it || true
ceph osd pool delete cephfs_metadata cephfs_metadata --yes-i-really-really-mean-it || true
ceph osd pool delete cephfs_data cephfs_data --yes-i-really-really-mean-it || true


echo "===== DELETE AUTH ====="
ceph auth del client.rgw.ceph1 || true


echo "===== DELETE CONFIG ====="
ceph config rm client.rgw.ceph1 rgw_frontends || true


echo "===== REMOVE SERVICE ====="
rm -f /etc/systemd/system/ceph-radosgw@.service
systemctl daemon-reload


echo "===== CLEAN FINISHED ====="
