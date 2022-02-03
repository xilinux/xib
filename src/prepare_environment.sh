#!/bin/sh

export MAKEFLAGS="-j$(grep "processor" /proc/cpuinfo | wc -l)"
export LDFLAGS="-liconv"
#export LDFLAGS=""

export XIB_DIR="/var/lib/xib"
export XIB_BUILDFILES="$XIB_DIR/buildfiles"
export XIB_CHROOT="$XIB_DIR/chroot"
export XIB_EXPORT="$XIB_DIR/export"

export PRIV_KEY="/home/david/.ssh/xi.pem"
export DEVELOPMENT_BUILDFILES="/home/david/docs/proj/xilinux/buildfiles"

export BUILDFILES_GIT_REPO="https://xi.davidovski.xyz/git/buildfiles.git"

mkdir -p $XIB_DIR $XIB_BUILDFILES $XIB_CHROOT $XIB_EXPORT

if [ -d $DEVELOPMENT_BUILDFILES ]; then
    cp -r $DEVELOPMENT_BUILDFILES/* $XIB_BUILDFILES/
else
    if [ -d $XIB_BUILDFILES/.git ]; then
        cd $XIB_BUILDFILES
        git pull
        cd $OLDPWD
    else
        git clone $BUILDFILES_GIT_REPO $XIB_BUILDFILES
    fi
fi


cp /etc/resolv.conf $XIB_CHROOT/etc/resolv.conf
