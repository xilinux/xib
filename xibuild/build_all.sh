#!/bin/bash

ERROR="\033[0;31m"
INFO="\033[0;34m"
PASS="\033[0;32m"
NEUTRAL="\033[0;33m"
RESET="\033[0m"

build_package () {
    name=$(echo $line | cut -d"+" -f1)
    buildfile=$(find $XIB_BUILDFILES -wholename "*/$name.xibuild" | head -1)
    
    if [ -f "$buildfile" ]; then
        printf $INFO
        printf "Building$NEUTRAL %s$INFO:\n$RESET" $name 
        ./build_package.sh $buildfile || return 1

        # Install the package if it is needed for other builds
        if echo $line | grep -q '+'; then
            printf "$INFO\tInstalling..." 
            exported_pkg=$(find $XIB_EXPORT -wholename "*/$name.xipkg" | head -1 | xargs realpath)
            if [ -f $exported_pkg ]; then
                tar -h --no-overwrite-dir -xf $exported_pkg -C $XIB_CHROOT

                postinstall="$XIB_CHROOT/var/lib/xipkg/postinstall"
                if [ -d $postinstall ]; then
                    for file in "$postinstall/*.sh"; do
                        f=$(basename $file)
                        chmod 755 $file
                        xichroot "$XIB_CHROOT" "/var/lib/xipkg/postinstall/$f"
                        rm $file
                        printf "$PASS run postinstall for $f!\n"
                    done
                    rmdir $postinstall
                fi
            fi

            printf "$PASS installed to chroot!\n"
        fi

        printf $RESET
        printf "Finished building %s!\n" $name
    else
        printf "$ERROR$name does not exist\n"
    fi

    # configure shadow here
    if [ "$name" = "shadow" ]; then
        xichroot "$XIB_CHROOT" "/usr/sbin/pwconv"
        xichroot "$XIB_CHROOT" "/usr/sbin/grpconv"
        xichroot "$XIB_CHROOT" "mkdir -p /etc/default"
        xichroot "$XIB_CHROOT" "/usr/sbin/useradd -D --gid 999"
    fi
}

build_all () {
    for line in $(perl build_order.pm); do
        build_package $line || return 1
    done

}

if build_all; then 
    printf "\n${PASS}Built all packages!"
    exit 0
else
    printf "$ERROR Something went wrong!$NEUTRAL Press enter to view recent log"
    read;

    f=$(ls -1 --sort time $XIB_EXPORT/repo/*/*.log | head -1 | xargs realpath)
    less $f
    exit 1
fi
