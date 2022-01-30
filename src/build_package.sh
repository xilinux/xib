#!/bin/bash

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
    local src_dir="$XIB_CHROOT/build/source"
    mkdir -pv $src_dir

    pushd $src_dir
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
                for file in */*; do 
                    mv $file .
                done;
            fi
        fi
    popd
}

clean_chroot () {
    local export_dir="$XIB_CHROOT/export"
    local build_dir="$XIB_CHROOT/build"

    rm -rf $export_dir
    rm -rf $build_dir

    mkdir -pv $export_dir
    mkdir -pv $build_dir
    
    mkdir -pv "$XIB_EXPORT/repo/$REPO/"
}

make_buildscript () {
    cat > "$XIB_CHROOT/build/build.sh" << "EOF"
#!/bin/bash

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

prepare || exit 1
build || exit 1
check 
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

    pushd "$pkg_dest"
        if [ "$(ls -1 | wc -l)" = "0" ]; then
            echo "package is empty"
            exit 1;
        fi
        tar -C $pkg_dest -cvzf $export_pkg ./
    popd
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
    clean_chroot
    fetch_source
    make_buildscript

    cp "$BUILDFILE" "$XIB_CHROOT/build/"
    printf $NAME > "$XIB_CHROOT/build/name"

    local log_file="$XIB_EXPORT/repo/$REPO/$NAME.log"
    xichroot $XIB_CHROOT /build/build.sh > $log_file

    package
    create_info

    # TODO check if the key exists, if not, skip signing
    sign

    cp "$BUILDFILE" "$XIB_EXPORT/repo/$REPO/"

}

[ -z "${XIB_CHROOT}" ] && echo "CRITICAL! No chroot env variable set!" && exit 1;

package_exists || build
