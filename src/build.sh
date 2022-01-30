#!/bin/bash

ERROR="\033[0;31m"
INFO="\033[0;34m"
PASS="\033[0;32m"
NEUTRAL="\033[0;33m"
RESET="\033[0m"

source prepare_environment.sh

build_all () {
    for line in $(perl build_order.pm); do
        name=$(echo $line | cut -d"+" -f1)
        buildfile=$(find $XIB_BUILDFILES -wholename "*/$name.xibuild" | head -1 | xargs realpath)

        printf $INFO
        printf "Building %s...$RESET" $name 
        ./build_package.sh $buildfile && printf "$PASS passed\n" || return 1

        # Install the package if it is needed for other builds
        if echo $line | grep -q '+'; then
            exported_pkg=$(find $XIB_EXPORT -wholename "*/$name.xipkg" | head -1 | xargs realpath)
            if [ -f $exported_pkg ]; then
                cd $XIB_CHROOT
                tar -xf $exported_pkg
                cd $OLDPWD
                printf "$INFO\tInstalled %s$RESET\n" $name 
            fi
        fi
    done;

}

if build_all; then 
    printf "$PASSBuilt all packages!"
else
    printf "$ERROR Something went wrong!$NEUTRAL Press enter to view recent log"
    read;

    f=$(ls -1 --sort time $XIB_EXPORT/repo/*/*.log | head -1 | xargs realpath)
    less $f
fi
