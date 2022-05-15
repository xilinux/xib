#!/bin/sh

toolchaindest="$xib_dir/chroot-toolchain"

toolchainpackages="
musl
linux-headers
llvm
clang
clang-tools-extra
libcxx
libcxxabi
libunwind
lld
libexecinfo
ncurses
tcl
expect
dejagnu
m4
dash
bison
bzip2
sbase
sort
ubase
findutils
diffutils
gettext
gzip
grep
make
patch
perl
sed
tar
texinfo
xz
flex
toolchain-cmake
ninja
"

bootstrap () {
    mkdir -p $toolchaindest
    rm -rf $stage
    mkdir -p $stage
    xi -nyl -r $toolchaindest bootstrap

    for pkg in $toolchainpackages; do 
        pkg_build=$(get_package_build $pkg)
        parent=$(basename $pkg_build)
        [ ! -d "$stage/$parent" ] && mkdir -p $stage/$parent
        [ ! -f $stage/$parent/$pkg.xipkg ] && {
            xibuild -v -k $keychain/$priv_key -c $pkg_build -d $stage/$parent -r $chroot || return 1
        }
        echo "Installing $pkg"
        xi -r $toolchaindest install $stage/$parent/$pkg.xipkg
    done

    printf "creating tarball...\n"
    output="xib-chroot-tools-$(date +%y%m%d).tar.xz"
    tar -C $toolchaindest -cJf $output ./ 
}

