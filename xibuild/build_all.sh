#!/bin/sh

ERROR="\033[0;31m"
INFO="\033[0;34m"
PASS="\033[0;32m"
NEUTRAL="\033[0;33m"
EXTRA="\033[0;30m"
RESET="\033[0m"

XIPKG_INSTALL=/usr/lib/xipkg/install.sh
[ -f $XIPKG_INSTALL ] && . $XIPKG_INSTALL

# scan and run all postinstall scripts
#
run_postinstall () {
    postinstall="$XIB_CHROOT/var/lib/xipkg/postinstall"
    if [ -d $postinstall ]; then
        printf "${EXTRA}(postinstall " 
        for file in $(ls $postinstall); do
            file=$postinstall/$file
            f=$(basename $file)

            # run the postinstall file
            #
            chmod 755 $file
            xichroot "$XIB_CHROOT" "/var/lib/xipkg/postinstall/$f"
            echo $?
            if [ "$?" == "0" ]; then
                rm $file
                printf "${PASS}${CHECKMARK}"
            else
                printf "${EXTRA}x"
            fi
        done
        printf ")\n"

        [ "$(ls $postinstall | wc -w)" == 0 ] &&
            rmdir $postinstall
    fi
}

# build a package by its name
# 
build_package () {

    local name=$(echo $1 | cut -d"+" -f1)
    local install=$(echo $line | grep -q '+' && echo "true" || echo "false")
    local buildfile=$(find $XIB_BUILDFILES -wholename "*/$name.xibuild" | head -1)
    
    if [ -f "$buildfile" ]; then
        printf "${INFO}%s\n${RESET}" $name 
        ./build_package.sh $buildfile || return 1

        # install the package it exists
        local exported_pkg=$(find $XIB_EXPORT -wholename "*/$name.xipkg" | head -1 | xargs realpath)
        if $install && [ -f $exported_pkg ] ; then
            printf "${INFO}${TABCHAR}install " 
            INSTALLED_DIR="$XIB_CHROOT/var/lib/xipkg/installed/"
            SYSROOT=$XIB_CHROOT
            VERBOSE=false
            install_package $exported_pkg $name && printf "${PASS}${CHECKMARK}\n" || printf "${NEUTRAL}${CHECKMARK}\n"
            run_postinstall
        fi

        return 0
    fi

    printf "${ERROR}${CROSSMARK} ${name}\n"
}

# build all of the packages
#
build_all () {
    all="$(perl build_order.pm)"
    echo "Building $(echo "$all" | wc -l )"
    for line in $all; do
        build_package $line || return 1
    done
}

while true; do
    if build_all; then 
        printf "\n${PASS}Built all packages!\n${RESET}"
        exit 0
    else
        printf "${ERROR} Something went wrong!${NEUTRAL} Press enter to view recent log"
        read out;

        less $(ls -1 --sort time $XIB_EXPORT/repo/*/*.log | head -1 | xargs realpath)

        read -p "Retry build? [Y/n]" response
        if [ "$response" = "n" ]; then
            exit 1
        fi
    fi
done
