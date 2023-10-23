#!/bin/bash

set -o pipefail
set -e

source .env

if [ $# -ne 1 ]; then
    echo "Usage: $0 <build template>"
    exit 1
fi

if [ ! -d "$1" ]; then
    echo -e "\e[91mError: $1 is not a valid directory.\e[0m"
    exit 1
fi

start_time=$(date +%s)

cd $1
if [ ! -f "customize.cfg" ] || [ ! -f "config.cfg" ]; then
    echo -e "\e[91mError: $1 is not a good build template.\e[0m"
fi

source config.cfg

loginResponse=$(curl $ZSTACK_URL/zstack/v1/accounts/login \
    -s -X PUT \
    -d "{ "logInByAccount": { "accountName": \"$ZSTACK_ACCOUNT_NAME\", "password": \"$ZSTACK_PASSWORD\" } }")
session=$(echo $loginResponse | jq -r .inventory.uuid)
echo -e "\e[93mLogin Successful.\e[0m"

python3 -m http.server -b 0.0.0.0 -d .build/&
file_server_pid=$!

uploadRequest=$(cat <<EOF
{
  "params": {
    "name": null,
    "description": null,
    "url": null,
    "mediaType": "RootVolumeTemplate",
    "architecture": "x86_64",
    "guestOsType": null,
    "system": false,
    "format": "qcow2",
    "platform": "Linux",
    "backupStorageUuids": [],
    "virtio": true
  }
}
EOF
)

uploadRequest=$(echo $uploadRequest | jq ".params.name=\"${1%/}-$(date +%Y%m%d)\" \
    | .params.url=\"$(echo $UPLOAD_HOST/$RESULT_NAME)\" \
    | .params.guestOsType=\"$GUEST_OS_TYPE\" \
    | .params.backupStorageUuids+=[\"$BACKUP_STORAGE_UUID\"]\
    | .params.description=\"Built by systemimage-cfg.\nUpload date: $(date)\""
    )

uploadTaskResponse=$(curl $ZSTACK_URL/zstack/v1/images \
    -s -X POST \
    -H "Authorization: OAuth $session" \
    -d "$uploadRequest"
)

uploadTaskQueryLocation=$(echo $uploadTaskResponse | jq -r ".location")

echo -e "\e[93mWaiting for upload task to complete...\e[0m"
echo -e "\e[93mQueryURL: $uploadTaskQueryLocation\e[0m"

while true
do
    retval=$(curl -s -o /dev/null -w "%{http_code}" $uploadTaskQueryLocation)
    if [[ "$retval" == '200' ]]; then
        break
    fi

    if [[ "$retval" != '202' ]]; then
        pkill -P $$
        echo -e "\e[91mImage upload error.\e[0m"
        exit 1
    fi
    echo -ne "\e[93m.\e[0m"
    sleep 5
done

echo
pkill -P $$
echo -e "\e[93mImage uploaded.\e[0m"