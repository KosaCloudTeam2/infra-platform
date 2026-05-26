#!/bin/bash
set -e

IP=$(hostname -I | awk '{print $1}')

for TEAM in 1 2 3 4
 do

USER="team${TEAM}-admin"
BUCKET="team${TEAM}-bucket"


radosgw-admin user create \
--uid="${USER}" \
--display-name="Team${TEAM} Admin" || true


ACCESS=$(radosgw-admin user info --uid="${USER}" | jq -r '.keys[0].access_key')
SECRET=$(radosgw-admin user info --uid="${USER}" | jq -r '.keys[0].secret_key')


echo "====================================="
echo "TEAM${TEAM}"
echo "ACCESS_KEY=${ACCESS}"
echo "SECRET_KEY=${SECRET}"
echo "====================================="


AWS_ACCESS_KEY_ID="${ACCESS}" \
AWS_SECRET_ACCESS_KEY="${SECRET}" \
aws --endpoint-url="http://${IP}:7480" \
--region us-east-1 \
s3 mb "s3://${BUCKET}" || true


done
