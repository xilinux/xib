#!/bin/sh

[ -f /usr/lib/colors.sh ] && . /usr/lib/colors.sh
[ -f /usr/lib/glyphs.sh ] && . /usr/lib/glyphs.sh
[ -f /usr/lib/xilib.sh ] && . /usr/lib/xilib.sh

XIPKG_INSTALL=/usr/lib/xipkg/install.sh
[ -f $XIPKG_INSTALL ] && . $XIPKG_INSTALL

xib_dir="/var/lib/xib"
build_profile="/etc/xib_profile.conf"

priv_key="xi.pem"

buildfiles="/home/david/docs/proj/xilinux/buildfiles"
#buildfiles="$xib_dir/buildfiles"
seen="$xib_dir/seen"
logs="$xib_dir/logs"
chroot="$xib_dir/chroot"
stage="$xib_dir/stage"
logs="$xib_dir/logs"
local_repo="$xib_dir/repo"
keychain="$xib_dir/keychain"

quickfail=true

usage () {
    cat << EOF
${LIGHT_RED}Usage: ${RED}xib [option] [package]
${BLUE}Avaiable Options:
    ${BLUE}-d
        ${LIGHT_CYAN}daemon; run as a daemon, automatically rebuilding all packages
    ${BLUE}-p
        ${LIGHT_CYAN}publish; publish packages in the stage to the repo
${RESET}
EOF
}

# publish any packages in the stage directory to the repo
#
publish_package () {
    local xipkgs=$(ls $stage/*.xipkg)
    local packageslist="$local_repo/packages.list"
    local depsgraph="$local_repo/deps.graph"
    [ ! -d "$local_repo" ] && mkdir -p "$local_repo"
    [ ! -f "$packageslist" ] && touch $packageslist
    [ ! -f "$depsgraph" ] && touch $depsgraph

    for xipkg in $xipkgs; do
        local name=$(basename $xipkg ".xipkg")
        local filecount=$(tar -tvvf $xipkg | grep -cv ^d)
        local checksum=$(sha512sum $xipkg | awk '{ print $1 }')
        local size=$(stat -t $xipkg | cut -d" " -f2)
        local deps=$(grep "^DEPS=" $xipkg.info | sed -rn 's/DEPS=(.*)/\1/p' | tr '\n' ' ')

        sed -i "s/^$name.xipkg .*$//" $packageslist
        echo $name.xipkg $checksum $size $filecount  >> $packageslist

        sed -i "s/^$name: .*$//" $depsgraph
        echo "$name: $deps" >> $depsgraph

        [ -f $stage/$name.xipkg ] && mv $stage/$name.xipkg $local_repo/$name.xipkg
        [ -f $stage/$name.xipkg.info ] && mv $stage/$name.xipkg.info $local_repo/$name.xipkg.info
        [ -f $stage/$name.xibuild ] && mv $stage/$name.xibuild $local_repo/$name.xibuild
        [ -f $logs/$name.log ] && cp $logs/$name.log $local_repo/$name.log
    done

    [ ! -d "$seen" ] && mkdir -p $seen
    for s in $stage/*.xibsum; do
        s=$(basename $s)
        mv $stage/$s $seen/$s
    done
}

# get root package from package name
#
#   get_package_build [name]
#
get_package_build () {
    local buildfile=$(find $buildfiles/repo -name "$1.xibuild" | head -1)
    echo ${buildfile%/*}
}

# list all packages available
#
list_all () {
    ls -1 $buildfiles/repo/
}

# get package file from package name
#
get_package_file () {
    find $local_repo/ -name "$1.xipkg" | head -1
}

# build a single package using xibuild
#
# build_package [build directory]
#
build_package () {
    local name=$(basename $1)

    rm -rf $stage
    mkdir -p $stage

    [ ! -d "$logs" ] && mkdir -p $logs
    rm -f $logs/$name.log
    touch $logs/$name.log

    xibuild -v \
        -C $1 \
        -o $stage \
        -r $chroot \
        -l $logs/$name.log \
        -k $keychain/$priv_key \
        -p $build_profile \
        || return 1

    get_buildfiles_hash $1 > $stage/$name.xibsum
}

# installs a package
#  
#   package_install [name] [xipkg file]
#
package_install () {
    local name=$1
    local xipkg=$2
    [ -f $xipkg ] &&
        xipkg -qlny -r $3 install $xipkg && printf "${PASS}${CHECKMARK}\n" || printf "${NEUTRAL}${CHECKMARK}\n"
}

# get the direct make dependencies of a single package
#
#   get_deps [name]
#
get_deps () {
    local package=$(get_package_build $1)
    [ -d $package ] && 
             sed -rn "s/^.*DEPS=\"(.*)\"/\1/p" $package/$1.xibuild
}

# list dependencies of a list of packages
# 
#   list_deps [dependencies]
#
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

# check if a package build dir actually requires any building
#
#   is_meta [xibuild dir]
#
is_meta () {
    local package=$1
    local name=${package#${package%/*}/}
    local src=$(sed -rn "s/^SOURCE=\"(.*)\"/\1/p" $package/$name.xibuild | head -1)
    [ -z "$src" ]
}

# get the checksum of a whole package's buildfiles
#
#   get_buildfiles_hash [xibuild dir]
#
get_buildfiles_hash () {
    cat $1/*.xibuild | sha512sum | cut -d' ' -f1
}

# build a single package
#
#   xib_single [name]
#
xib_single () {
    local name=$1
    local package=$(get_package_build $name)
    local deps=$(get_deps $name)
    local missing=""

    is_meta $package || {
        for dep in $deps; do
            [ -e "$chroot/var/lib/xipkg/installed/$dep" ] || {
                pkgfile=$(get_package_file $dep)
                        [ "${#pkgfile}" = "0" ] && missing="$missing $dep"
                printf "${LIGHT_GREEN}+${LIGHT_CYAN}install $dep"
                package_install $dep $(get_package_file $dep) $chroot
            }
        done
    }

    [ "${#missing}" != "0" ] && {
        printf "${RED}$name depends on these packages to be build before: ${LIGHT_RED}$missing\n"
        return 1
    }

    build_package $package \
        && publish_package \
        && {
            [ -e "$chroot/var/lib/xipkg/installed/$name" ] && {
                xi -r $chroot -nqyl remove $name
        } || true
    }
}

# build all packages
#
xib_all () {
    for name in $(build_order $(list_all)); do

        package=$(get_package_build $name)
        [ "${#package}" != 0 ] && [ -d "$package" ] && {
            local package_name="$(basename ${package#/*})"
            xibsum=$(get_buildfiles_hash $package)
            [ -f "$seen/$package_name.xibsum" ] && \
                [ "$(cat "$seen/$package_name.xibsum")" = "$xibsum" ] && {
                printf "${BLUE}$package_name${LIGHT_BLUE}...already built!\n"
            } || {
                xib_single $name || {
                    $quickfail && return 0
                }
            }
            true

        } || {
            printf "${RED} could not find package for $name in $package $RESET\n"
        }
    done
}

# return the order that packages should be built
# sorted topologically from dependencies
#
#   build_order [packages...]
#
build_order () {
    for pkg in $@; do 
        for dep in $(get_deps $pkg); do
            echo $pkg $dep
        done
    done | tsort | reverse_lines
}

# main loop of the xib daemon
#
xibd () {
    quickfail=false
    while true; do
        cd $buildfiles
        git pull
        cd $xib_dir
        xib_all
        sleep 5
    done
}

[ "$#" = 0 ] && {
    xib_all
} || {
    case "$1" in 
        "-d")
            xibd;;
        "-p")
            publish_package
            ;;
        "-h")
            usage
            ;;
        *)
        for x in $@; do
            xib_single $x
        done
        ;;
    esac
}

