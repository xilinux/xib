#!/bin/sh

ERROR="\033[0;31m"
INFO="\033[0;34m"
PASS="\033[0;32m"
NEUTRAL="\033[0;33m"
RESET="\033[0m"

# scan and run all postinstall scripts
#
run_postinstall () {
    postinstall="$XIB_CHROOT/var/lib/xipkg/postinstall"
    if [ -d $postinstall ]; then
        for file in "$postinstall/*.sh"; do
            f=$(basename $file)

            # run the postinstall file
            #
            chmod 755 $file
            xichroot "$XIB_CHROOT" "/var/lib/xipkg/postinstall/$f"
            rm $file

            printf "$PASS run postinstall for $f!\n"
        done
        rmdir $postinstall
    fi
}

# install a single package if it is present
# 
# arg: the exported .xipkg file
#
install_package () {
    printf "${INFO}${TABCHAR}install " 
    xi -nyulq -r ${XIB_CHROOT} install $1 >> printf "${PASS}${CHECKMARK}\n"
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
            install_package $exported_pkg
        fi

        return 0
    fi

    printf "${ERROR}${CROSSMARK} ${name}\n"
}

# build all of the packages
#
build_all () {
    for line in $(perl build_order.pm); do
        build_package $line || return 1
    done
}


if build_all; then 
    printf "\n${PASS}Built all packages!\n${RESET}"
    exit 0
else
    printf "${ERROR} Something went wrong!${NEUTRAL} Press enter to view recent log"
    read;

    less $(ls -1 --sort time $XIB_EXPORT/repo/*/*.log | head -1 | xargs realpath)
    exit 1
fi
