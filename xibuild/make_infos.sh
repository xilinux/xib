#!/bin/bash


# TODO remember to update this if there are ever changes
XIPKG_INFO_VERSION='02'

get_info() {
        local name=$(basename -s ".xipkg" $1)

        local pkg_ver=$PKG_VER
        [ -z "$pkg_ver" ] && pkg_ver=$BRANCH
        [ -z "$pkg_ver" ] && pkg_ver="latest"
        
        echo "# XiPKG info file version $XIPKG_INFO_VERSION"
        echo "# automatically generated from the built packages"
        echo "NAME=$name"
        echo "DESCRIPTION=$DESC"
        echo "PKG_FILE=$name.xipkg"
        echo "CHECKSUM=$(md5sum $1 | awk '{ print $1 }')"
        echo "VERSION=$pkg_ver"
        echo "SOURCE=$SOURCE"
        echo "DATE=$(date -r $1)"
        echo "DEPS=(${DEPS[*]})"
        echo "MAKE_DEPS=(${MAKE_DEPS[*]})"
}

sign () {
    echo "SIGNATURE="
    openssl dgst -sign $PRIV_KEY $1
}

list_line() {
    local pkg_file=$1
    
    local name=$(basename -s ".xipkg" $pkg_file)
    local filecount=$(gzip -cd $pkg_file | tar -tvv | grep -c ^-)
    local checksum=$(md5sum $pkg_file | awk '{ print $1 }')
    local size=$(du -s $pkg_file | awk '{print $1}')

    echo $name.xipkg $checksum $size $filecount
}


for repo in $(ls -d "$XIB_EXPORT"/repo/*); do
    file="$repo/packages.list"
    [ -e $file ] && rm $file
    touch $file
    echo "Removed old package lists in $repo"
done

for pkg in $(ls "$XIB_EXPORT"/repo/*/*.xipkg); do
        name=$(basename -s ".xipkg" $pkg)
        repo=$(echo $pkg | rev | cut -d/ -f2 | rev)
        info_file="$XIB_EXPORT/repo/$repo/$name.xipkg.info"
        build_file="$XIB_EXPORT/repo/$repo/$name.xibuild"

        source $build_file

        get_info $pkg > $info_file
        sign $pkg >> $info_file
        list_line $pkg >> "$XIB_EXPORT"/repo/$repo/packages.list
        echo "Enlisted $name to $info_file"
done
