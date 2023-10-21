#!/bin/bash

set -o pipefail
set -e

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
mkdir -p .build
if [ ! -f "customize.cfg" ] || [ ! -f "config.cfg" ]; then
    echo -e "\e[91mError: $1 is not a good build template.\e[0m"
fi

source config.cfg

wget_exit_code=0
wget -nc "$BASE_IMAGE_URL" -O ".build/$FILE_NAME" || wget_exit_code=$?
if [ "$wget_exit_code" -gt 1 ]; then
    exit $wget_exit_code
fi

wget "$BASE_IMAGE_SHASUM_URL" -O ".build/SHA512SUMS"

expected_checksum=$(cat ".build/SHA512SUMS" | grep "$FILE_NAME" | awk '{print $1}')
actual_checksum=$(sha512sum .build/$FILE_NAME | awk '{print $1}')

if ! [ "$actual_checksum" = "$expected_checksum" ]; then
    echo -e "\e[91mImage file is corrupted. Please redownload the file.\e[0m"
    exit 1
fi

truncate -r .build/$FILE_NAME .build/$RESULT_NAME
truncate -s $TRUNCATE_SIZE .build/$RESULT_NAME
virt-resize --expand /dev/sda1 .build/$FILE_NAME .build/$RESULT_NAME

genisoimage -o .build/extra.iso -R -J -V EXTRA extra/
virt-customize \
    -a .build/$RESULT_NAME\
    --network \
    --attach .build/extra.iso \
    --commands-from-file customize.cfg

end_time=$(date +%s)
echo -e "\033[0;33mSaved the build artifact as $1/.build/$RESULT_NAME. Used time: $(($end_time - $start_time))s\033[0m"