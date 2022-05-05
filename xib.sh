#!/bin/sh

[ -f /usr/lib/colors.sh ] && . /usr/lib/colors.sh
[ -f /usr/lib/glyphs.sh ] && . /usr/lib/glyphs.sh

XIPKG_INSTALL=/usr/lib/xipkg/install.sh
[ -f $XIPKG_INSTALL ] && . $XIPKG_INSTALL


xib_dir="/var/lib/xib"
priv_key="xi.pem"

buildfiles="$xib_dir/buildfiles"
chroot="$xib_dir/chroot"
stage="$xib_dir/stage"
local_repo="$xib_dir/repo"
keychain="$xib_dir/keychain"

# add a package to the repo's packages.list
#
publish_package () {
    local repo=$1
    xipkgs=$(ls $stage/*.xipkg)

    mv $stage/build.log $stage/$name.log

    packageslist="$local_repo/$repo/packages.list"
    depsgraph="$local_repo/deps.graph"

    for xipkg in $xipkgs; do
        local name=$(basename $xipkg ".xipkg")
        local filecount=$(gzip -cd $xipkg | tar -tvv | grep -cv ^d)
        local checksum=$(md5sum $xipkg | awk '{ print $1 }')
        local size=$(stat -t $xipkg | cut -d" " -f2)
        local deps=$(grep "^DEPS=" $xipkg.info | sed -rn 's/DEPS=(.*)/\1/p')

        sed -i "s/^$name.xipkg//" $packageslist
        echo $name.xipkg $checksum $size $filecount  >> $packageslist

        sed -i "s/^$name: //" $depsgraph
        echo "$name: $deps" >> $depsgraph

        mv $stage/$xipkg $local_repo/$repo/$name.xipkg
        mv $stage/$xipkg.info $local_repo/$repo/$name.xipkg.info
        mv $stage/$name.xibuild $local_repo/$repo/$name.xibuild
        cp $stage/build.log $local_repo/$repo/$name.log
    done
}

# get root package from package name
#
get_package_build () {
    local name=$1
    local buildfile=$(find $buildfiles/repo -name "$name.xibuild" | head -1)
    local name="$(realpath $buildfile | rev | cut -d'/' -f2 | rev)"
    local repo="$(realpath $buildfile | rev | cut -d'/' -f3 | rev)"

    echo $buildfiles/repo/$repo/$name
}

# get package file from package name
#
get_package_file () {
    local name=$1
    local pkgfile=$(find $local_repo/ -name "$name.xipkg" | head -1)
    echo $pkgfile
}

# Use xibuild to build a singular package
#
build_package () {
    local package=$(get_package_build $1)
    rm -rf $stage
    mkdir -p $stage
    xibuild -k $keychain/$priv_key -c $package -d $stage -r $chroot
}
package_install () {
    local name=$1
    local xipkg=$(get_package_file $1)
    INSTALLED_DIR="$chroot/var/lib/xipkg/installed/"
    SYSROOT=$chroot
    VERBOSE=false

    install_package $xipkg $name && printf "${PASS}${CHECKMARK}\n" || printf "${NEUTRAL}${CHECKMARK}\n"
    run_postinstall
}

# get the direct dependencies of a single package
#
get_deps () {
    package=$(get_package_build $1)
    [ -d $package ] && {
        for buildfile in $package/*.xibuild; do
             sed -rn "s/^.*DEPS=\"(.*)\"/\1/p" $buildfile
        done
    }
}

list_deps () {
    local deps=""
    while [ "$#" != "0" ]; do
        # pop a value from the args
        local package=$1

        #only add if not already added
        echo ${deps} | grep -q "\b$package\b" || deps="$deps $package"

        for dep in $(get_deps $package); do
            # if not already checked
            echo $@ | grep -qv "\b$dep\b" && set -- $@ $dep
        done
        shift
    done
    echo "$deps" 
}

xib_single () {
    local name=$1
    local deps=$(list_deps $name)
    for dep in $deps; do
        [ -e "$chroot/var/lib/xipkg/installed/$name" ] || {
            install_package $(get_package_file $name) $name
        }
    done
}

