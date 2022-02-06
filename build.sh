#!/bin/bash

source xib_env

cd xibuild
./build_all.sh || exit 1
./make_infos.sh

keychain="$XIB_EXPORT"/keychain
mkdir -p $keychain
cp $PUB_KEY $keychain/


