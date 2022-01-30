#!/bin/bash

GREEN="\033[0;32m"
BLUE="\033[0;34m"

BUILDFILE=$1
REPO=$(echo $BUILDFILE | rev | cut -d/ -f2 | rev)
NAME=$(basename $BUILDFILE .xibuild)

source $BUILDFILE

extract () {
    FILE=$1
    case "${FILE#*.}" in 
        "tar.gz" )
            tar -zxf $FILE
            ;;
        "tar.lz" )
            tar --lzip -xf "$FILE"
            ;;
        "zip" )
            unzip $FILE
            ;;
        * )
            tar -xf $FILE
            ;;
    esac
}

package_exists () {
    local exported="$XIB_EXPORT/repo/$REPO/$NAME"
    local exported_pkg="$exported.xipkg"
    local exported_pkg_info="$exported.xipkg.info"
    local exported_pkg_build="$exported.xibuild"

    if [ -f $exported_pkg ] && [ -f $exported_pkg_info ] && [ -f $exported_pkg_build ]; then
        local built_sum=$(md5sum $exported_pkg_build | cut -d" " -f1)
        local current_sum=$(md5sum $BUILDFILE | cut -d" " -f1)
        
        if [ "$built_sum" = "$current_sum" ]; then
            return 0
        fi
    fi

    return 1
}

fetch_source () {
    # download additional files
    local src_dir="$XIB_CHROOT/build/source"
    mkdir -p $src_dir

    cd $src_dir

    if [ ! -z ${SOURCE} ]; then

        if git ls-remote -q $SOURCE $BRANCH &> /dev/null; then
            # The source is a git repo
            git clone $SOURCE .
            git checkout $BRANCH
        else
            # The source is a file

            local downloaded_file=$(basename $SOURCE)
            curl -SsL $SOURCE > $downloaded_file
            extract $downloaded_file

            # if the extracted file only had one directory
            if [ "$(ls -l | wc -l)" = "3" ]; then
                for file in */* */.*; do 
                    echo $file | grep -q '\.$' || mv $file .
                done;
            fi
        fi
    fi

    # download additional files
    if [ ! -z ${ADDITIONAL} ]; then
        for url in ${ADDITIONAL[*]}; do
            local name=$(basename $url)
            curl -Ssl $url > $src_dir/$name 
        done
    fi
}


clean_chroot () {
    local export_dir="$XIB_CHROOT/export"
    local build_dir="$XIB_CHROOT/build"

    rm -rf $export_dir
    rm -rf $build_dir

    mkdir -p $export_dir
    mkdir -p $build_dir
    
    mkdir -p "$XIB_EXPORT/repo/$REPO/"
}

make_buildscript () {

    echo MAKEFLAGS="$MAKEFLAGS" >> "$XIB_CHROOT/build/profile"

    cat > "$XIB_CHROOT/build/build.sh" << "EOF"
#!/bin/bash
source /build/profile
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
source $PKG_NAME.xibuild
cd /build/source

echo "==========================PREPARE STAGE=========================="
prepare || exit 1
echo "==========================BUILD STAGE=========================="
build || exit 1
echo "==========================CHECK STAGE=========================="
check 
echo "==========================PACKAGE STAGE=========================="
package || exit 1

if command -v postinstall > /dev/null; then 
    POSTINSTALL=$(type postinstall | sed '1,3d,$d')
    if [${#POSTINSTALL} != 0]; then
        POST_DIR=$PKG_DEST/var/lib/xipkg/postinstall
        mkdir -p $POST_DIR
        echo "#!/bin/sh" > $POST_DIR/$PKG_NAME.sh
        echo $POSTINSTALL >> $POST_DIR/$PKG_NAME.sh
    fi
fi
EOF
    chmod 700 "$XIB_CHROOT/build/build.sh"
}

package () {
    local export_repo="$XIB_EXPORT/repo/$REPO"
    local export_pkg="$XIB_EXPORT/repo/$REPO/$NAME.xipkg"
    local pkg_dest="$XIB_CHROOT/export"

    cd "$pkg_dest"
    if [ "$(ls -1 | wc -l)" = "0" ]; then
        printf " package is empty;"
        [ -z "${SOURCE}"] || exit 1;
    fi
    tar -C $pkg_dest -czf $export_pkg ./
}

create_info () {
    local export_pkg="$XIB_EXPORT/repo/$REPO/$NAME.xipkg"
    local pkg_info="$export_pkg.info"

    echo "" > $pkg_info 
    echo "NAME=$NAME" >> $pkg_info
    echo "DESCRIPTION=$DESC" >> $pkg_info
    echo "PKG_FILE=$NAME.xipkg" >> $pkg_info
    echo "CHECKSUM=$(md5sum $export_pkg | awk '{ print $1 }')" >> $pkg_info
    echo "SOURCE=$SOURCE" >> $pkg_info
    echo "DATE=$(date)" >> $pkg_info
    echo "DEPS=(${DEPS[*]})" >> $pkg_info
}

sign () {
    local export_pkg="$XIB_EXPORT/repo/$REPO/$NAME.xipkg"
    local pkg_info="$export_pkg.info"

    echo "SIGNATURE=" >> $pkg_info
    openssl dgst -sign $PRIV_KEY $export_pkg >> $pkg_info

}

build () {
    printf "$BLUE\tCleaning chroot..." 
    clean_chroot && printf "$GREEN prepared\n" || return 1

    printf "$BLUE\tfetching source..." 
    fetch_source && printf "$GREEN fetched $(du -sh "$XIB_CHROOT/build/source" | awk '{ print $1 }')\n" || return 1

    printf "$BLUE\tgenerating buildscript..." 
    make_buildscript && printf "$GREEN generated\n" || return 1

    cp "$BUILDFILE" "$XIB_CHROOT/build/"
    printf $NAME > "$XIB_CHROOT/build/name"

    local log_file="$XIB_EXPORT/repo/$REPO/$NAME.log"

    printf "$BLUE\tBuilding package..." 
    xichroot $XIB_CHROOT /build/build.sh &> $log_file && printf "$GREEN built!\n" || return 1

    printf "$BLUE\tPackaging package..." 
    package && printf "$GREEN packaged!\n" || return 1

    printf "$BLUE\tCreating package info..."
    create_info && printf "$GREEN created info!\n" || return 1

    # TODO check if the key exists, if not, skip signing
    printf "$BLUE\tSigning package..."
    sign && printf "$GREEN signed!\n" || return 1

    cp "$BUILDFILE" "$XIB_EXPORT/repo/$REPO/"
}

[ -z "${XIB_CHROOT}" ] && echo "CRITICAL! No chroot env variable set!" && exit 1;

package_exists && printf "\tPackage exists!\n" || build

