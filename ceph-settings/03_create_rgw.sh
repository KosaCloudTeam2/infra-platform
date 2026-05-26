#!/bin/bash
set -e

HOST=$(hostname -s)
IP=$(hostname -I | awk '{print $1}')


ceph auth get-or-create "client.rgw.${HOST}" \
mon 'allow rw' \
osd 'allow rwx' \
mgr 'allow rw' \
-o "/etc/ceph/ceph.client.rgw.${HOST}.keyring"


radosgw-admin realm create \
--rgw-realm=default \
--default || true


radosgw-admin zonegroup create \
--rgw-zonegroup=default \
--master \
--default || true


radosgw-admin zone create \
--rgw-zonegroup=default \
--rgw-zone=default \
--master \
--default || true


radosgw-admin zonegroup modify \
--rgw-zonegroup=default \
--endpoints="http://${IP}:7480"


radosgw-admin zone modify \
--rgw-zone=default \
--endpoints="http://${IP}:7480"


radosgw-admin period update --commit


cat <<EOF > /etc/systemd/system/ceph-radosgw@.service
[Unit]
Description=Ceph RGW
After=network.target

[Service]
Type=simple

ExecStart=/usr/bin/radosgw \
 -n client.rgw.%i \
 -k /etc/ceph/ceph.client.rgw.%i.keyring \
 --rgw-frontends=\"beast endpoint=0.0.0.0:7480\"

Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF


systemctl daemon-reload

systemctl enable "ceph-radosgw@${HOST}"

systemctl restart "ceph-radosgw@${HOST}"

sleep 5

ss -tulnp | grep 7480
