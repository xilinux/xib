#!/bin/bash

GREEN="\033[0;32m"
BLUE="\033[0;34m"

BUILDFILE=$1
REPO=$(echo $BUILDFILE | rev | cut -d/ -f2 | rev)
NAME=$(basename $BUILDFILE .xibuild)


# extract an archive using its appropriate tool
#
extract () {
    FILE=$1
    case "${FILE##*.}" in 
        "gz" )
            tar -zxf $FILE
            ;;
        "lz" )
            tar --lzip -xf "$FILE"
            ;;
        "zip" )
            unzip -qq -o $FILE 
            ;;
        * )
            tar -xf $FILE
            ;;
    esac
}

# check if the package we want to build already exists, comparing hashes of the build file
#
package_exists () {
    local exported="$XIB_EXPORT/repo/$REPO/$NAME"
    local exported_pkg="$exported.xipkg"
    local exported_pkg_info="$exported.xipkg.info"
    local exported_pkg_build="$exported.xibuild"

    if [ -f $exported_pkg ] && [ -f $exported_pkg_build ]; then
        local built_sum=$(md5sum $exported_pkg_build | cut -d" " -f1)
        local current_sum=$(md5sum $BUILDFILE | cut -d" " -f1)
        
        if [ "$built_sum" = "$current_sum" ]; then
            return 0
        fi
    fi

    return 1
}

# downloads the source and any additional files
#
fetch_source () {
    local src_dir="$XIB_CHROOT/build/source"
    mkdir -p $src_dir

    cd $src_dir

    if [ ! -z ${SOURCE} ]; then

        if git ls-remote -q $SOURCE $BRANCH > /dev/null 2>&1; then
            # the source is a git repo
            git clone $SOURCE . > /dev/null 2>&1
            git checkout $BRANCH > /dev/null 2>&1
        else
            # otherwise the source is a file

            local downloaded_file=$(basename $SOURCE)
            curl -SsL $SOURCE > $downloaded_file
            extract $downloaded_file

            # if the extracted file only had one directory
            if [ "$(ls -1 | wc -l)" = "2" ]; then
                for file in */* */.*; do 
                    echo $file | grep -q '\.$' || mv $file .
                done;
            fi
        fi
    fi

    set -- ${ADDITIONAL}
    # download additional files
    if [ "$#" != 0 ]; then
        for url in $@; do
            case $url in 
                http*)
                    ;;
                *)
                    url="file://${XIB_BUILDFILES}/extra/$NAME/$url"
                    ;;
            esac

            local name=$(basename $url)
            curl -SsL $url > $src_dir/$name 
        done
    fi
}

# removes any unecessary files from the chroot, from previous builds
#
clean_chroot () {
    local export_dir="$XIB_CHROOT/export"
    local build_dir="$XIB_CHROOT/build"

    rm -rf $export_dir
    rm -rf $build_dir

    mkdir -p $export_dir
    mkdir -p $build_dir
    
    mkdir -p "$XIB_EXPORT/repo/$REPO/"
}

prepare_build_env () {
    clean_chroot

    cp "$BUILDFILE" "$XIB_CHROOT/build/"
    printf $NAME > "$XIB_CHROOT/build/name"
}

# generate the script that will be used to build the xibuild
#
make_buildscript () {

    cat $BUILD_PROFILE > "$XIB_CHROOT/build/profile"
    cat > "$XIB_CHROOT/build/build.sh" << "EOF"
#!/bin/sh
. /build/profile
export PKG_NAME=$(cat /build/name)
export PKG_DEST=/export

prepare () {
    echo "passing prepare"
}

build () {
    echo "passing build"
}

check () {
    echo "passing check"
}

package () {
    echo "passing package"
}

cd /build
ls
. ./$PKG_NAME.xibuild
cd /build/source

echo "==========================PREPARE STAGE=========================="
prepare || exit 1
echo "==========================BUILD STAGE=========================="
build || exit 1
echo "==========================CHECK STAGE=========================="
check || exit 1
echo "==========================PACKAGE STAGE=========================="
package || exit 1

printf "checking for postinstall... "
if command -v postinstall > /dev/null; then 
    echo "adding postinstall"
    POST_DIR=$PKG_DEST/var/lib/xipkg/postinstall
    mkdir -p $POST_DIR
    cat /build/$PKG_NAME.xibuild > $POST_DIR/$PKG_NAME.sh
    echo "" >> $POST_DIR/$PKG_NAME.sh
    echo "postinstall" >> $POST_DIR/$PKG_NAME.sh
else
    echo "no postinstall"
fi
EOF
    chmod 700 "$XIB_CHROOT/build/build.sh"
}

# package the dest files into a xipkg
#
package_dest () {
    local export_repo="$XIB_EXPORT/repo/$REPO"
    local export_pkg="$XIB_EXPORT/repo/$REPO/$NAME.xipkg"
    local pkg_dest="$XIB_CHROOT/export"

    cd "$pkg_dest"

    # ensure that the package actually exists
    if [ "$(ls -1 | wc -l)" = "0" ]; then
        printf " package is empty;"
        [ -z "${SOURCE}" ] || exit 1;
    fi

    tar -C $pkg_dest -czf $export_pkg ./

    # export the buildfile
    cp "$BUILDFILE" "$XIB_EXPORT/repo/$REPO/"
}

# strip debug symbols
#
strip_dest () {
   local pkg_dest="$XIB_CHROOT/export"
   for file in \
       $(find $pkg_dest/ -type f -name \*.so* ! -name \*dbg) \
       $(find $pkg_dest/ -type f -name \*.a) \
       $(find $pkg_dest/ -type f -executable ); do
       strip --strip-unneeded $file
   done

   find $pkg_dest -name \*.la -delete
}

# build the package
#
build_pkg () {
    local log_file="$XIB_EXPORT/repo/$REPO/$NAME.log"

    printf "${BLUE}${TABCHAR}prepare " 
       prepare_build_env || return 1
    printf "${GREEN}${CHECKMARK}\n"

    printf "${BLUE}${TABCHAR}fetch " 
       fetch_source || return 1
    printf "${GREEN}${CHECKMARK}${RESET}${INFOCHAR}$(du -sh "$XIB_CHROOT/build/source" | awk '{ print $1 }')\n"

    printf "${BLUE}${TABCHAR}generate "
        make_buildscript || return 1
    printf "${GREEN}${CHECKMARK}\n"

    printf "${BLUE}${TABCHAR}build " 
        xichroot $XIB_CHROOT /build/build.sh > $log_file 2>&1 || return 1
    printf "${GREEN}${CHECKMARK}\n"

    printf "${BLUE}${TABCHAR}clean " 
        strip_dest > $log_file 2>&1 || return 1
    printf "${GREEN}${CHECKMARK}\n"

    printf "${BLUE}${TABCHAR}package "
        package_dest || return 1
    printf "${GREEN}${CHECKMARK}${RESET}${INFOCHAR}$(du -sh "$XIB_EXPORT/repo/$REPO/$NAME.xipkg" | awk '{ print $1 }')!\n" 

    # export the buildfile
}

#
# IMPORTANT
#
# this script will attempt to build the package in a suitable chroot environment
# if one is not specified then unwanted consequences can occur
# using XIB_CHROOT=/ could be a possbility but be aware of the risks
#
[ -z "${XIB_CHROOT}" ] && echo "${RED}CRITICAL! ${RESET}No chroot env variable set!" && exit 1;

# import all of the functions and constants in the build file, so we know what to do
. $BUILDFILE
package_exists || build_pkg

