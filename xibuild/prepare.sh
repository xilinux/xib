#!/bin/sh

mkdir -p $XIB_DIR $XIB_BUILDFILES $XIB_CHROOT $XIB_EXPORT

if [ -d $DEVELOPMENT_BUILDFILES ]; then
    export XIB_BUILDFILES=$DEVELOPMENT_BUILDFILES
    echo $XIB_BUILDFILES
else
    if [ -d $XIB_BUILDFILES/.git ]; then
        cd $XIB_BUILDFILES
        git pull
        cd $OLDPWD
    else
        git clone $BUILDFILES_GIT_REPO $XIB_BUILDFILES
    fi
fi

[ -f $XIB_CHROOT/etc/resolv.conf ] || cp /etc/resolv.conf $XIB_CHROOT/etc/resolv.conf

cp build_profile $BUILD_PROFILE
