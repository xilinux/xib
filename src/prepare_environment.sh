#!/bin/sh

export XIB_DIR="/var/lib/xib"
export XIB_BUILDFILES="$XIB_DIR/buildfiles"
export XIB_CHROOT="$XIB_DIR/chroot"
export XIB_EXPORT="$XIB_DIR/export"

export PRIV_KEY="$HOME/.ssh/xi.pem"

export BUILDFILES_GIT_REPO="https://xi.davidovski.xyz/git/buildfiles.git"

mkdir -pv $XIB_DIR $XIB_BUILDFILES $XIB_CHROOT $XIB_EXPORT

if [ -d $XIB_BUILDFILES/.git ]; then
    cd $XIB_BUILDFILES
    git pull
else
    git clone $BUILDFILES_GIT_REPO $XIB_BUILDFILES
fi
