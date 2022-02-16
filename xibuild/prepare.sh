#!/bin/sh

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

[ -f $INSTALLED_PACKAGES ] || touch $INSTALLED_PACKAGES

[ -f $XIB_CHROOT/etc/resolv.conf ] || cp /etc/resolv.conf $XIB_CHROOT/etc/resolv.conf
