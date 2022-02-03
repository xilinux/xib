#!/bin/bash
# A small script to generate the chroot environment where building will take place

export MAKEFLAGS="-j$(grep "processor" /proc/cpuinfo | wc -l)"
export WORKING_DIR="/var/lib/xib"
BUILDFILES_REPO_URL="https://xi.davidovski.xyz/git/buildfiles.git"
export SYSTEM_DIR="$WORKING_DIR/xib-chroot"

TOOL_DIR="$SYSTEM_DIR/tools"
SOURCES="$SYSTEM_DIR/sources"

TGT=$(uname -m)-xi-linux-gnu


export PATH=/usr/bin
if [ ! -L /bin ]; then export PATH=/bin:$PATH; fi
export PATH=$SYSTEM_DIR/tools/bin:$PATH
export CONFIG_SITE=$SYSTEM_DIR/usr/share/config.site
export LC_ALL=POSIX



packages=(binutils gcc linux glibc mpfr gmp mpc m4 ncurses bash coreutils diffutils file findutils gawk grep gzip make patch sed tar xz)

get_build_files() {
    mkdir -p $WORKING_DIR/buildfiles
    git clone "$BUILDFILES_REPO_URL" $WORKING_DIR/buildfiles
}

list_build_files() {
    ls -1 $WORKING_DIR/buildfiles/repo/*/*.xibuild
}

parse_package_versions() {
    for pkg_file in $(list_build_files); do
        local pkg_name=$(basename -s .xibuild $pkg_file)
        local pkg_ver=$(sed -n "s/^PKG_VER=\(.*\)$/\1/p" $pkg_file)

        [ -z "$pkg_ver" ] && pkg_ver=$(sed -n "s/^BRANCH=\(.*\)$/\1/p" $pkg_file)
        [ -z "$pkg_ver" ] && pkg_ver="latest"
        printf "%-16s %16s\n" $pkg_name $pkg_ver
    done
}

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


make_dir_struct() {
    local system=$1
    
    mkdir -pv $system/{etc,var,proc,sys,run,tmp} $system/usr/{bin,lib,sbin} $system/dev/{pts,shm}

    for i in bin lib sbin; do
      ln -sv usr/$i $system/$i
    done

    case $(uname -m) in
      x86_64) mkdir -pv $system/lib64 ;;
    esac
}

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

init_versions() {
    local versions_file="$SYSTEM_DIR/versions"

    [ -f $versions_file ] || exit 1

    for i in ${packages[@]}; do
        local name=${i^^}
        local version=$(sed -n "s/^$i \s*\(.*\)$/\1/p" $versions_file)
        eval "${i^^}_VERSION"="$version"
    done
}

get_source() {
    local buildfile="$1"
    local package_name=$(basename -s .xibuild $buildfile)

    echo "fetching $buildfile"

    if [ ! -d $package_name ]; then
        mkdir -p $package_name
        cd $package_name
        rm -rf *
        source $buildfile

        if git ls-remote -q $SOURCE $BRANCH &> /dev/null; then
            git clone $SOURCE .
            git checkout $BRANCH 

        elif hg identify $SOURCE &> /dev/null; then
            hg clone $SOURCE package_name .
        else
            local downloaded=$(basename $SOURCE)
            curl -Ls $SOURCE > $downloaded
            extract $downloaded 
            mv */* .
        fi
    fi
}

get_sources() {
    mkdir -p $SYSTEM_DIR/sources
    for pkg in $@; do
        local pkg_file="$WORKING_DIR/buildfiles/repo/*/$pkg.xibuild"
        cd $SYSTEM_DIR/sources
        get_source $pkg_file
    done
}

# builds binutils to toolchain
#
build_binutils1() {
    cd $SOURCES/binutils/

    mkdir -v build
    cd       build

    ../configure --prefix="$SYSTEM_DIR/tools"     \
             --with-sysroot="$SYSTEM_DIR" \
             --target=$TGT                \
             --disable-nls                \
             --disable-werror             &&
    make &&
    make install -j1
}


# builds gcc to toolchain
#
build_gcc1() {
    cd $SOURCES/gcc/
    
    #rm -rf mpfr gmp mpc

    autoreconf -i

    [ -d mpfr ] || cp -r $SOURCES/mpfr mpfr
    [ -d gmp ] || cp -r $SOURCES/gmp gmp
    [ -d mpc ] || cp -r $SOURCES/mpc mpc

    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64

    mkdir -v build
    cd       build

    ../configure                            \
        --target=$TGT                       \
        --prefix=$SYSTEM_DIR/tools          \
        --with-glibc-version=$GLIBC_VERSION \
        --with-sysroot=$SYSTEM_DIR          \
        --with-newlib                       \
        --without-headers                   \
        --without-zstd                      \
        --enable-initfini-array             \
        --disable-nls                       \
        --disable-shared                    \
        --disable-multilib                  \
        --disable-decimal-float             \
        --disable-threads                   \
        --disable-libatomic                 \
        --disable-libgomp                   \
        --disable-libquadmath               \
        --disable-libssp                    \
        --disable-libvtv                    \
        --disable-libstdcxx                 \
        --enable-languages=c,c++

    make &&
    make install || exit 1
    cd ..
    cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
        `dirname $($TGT-gcc -print-libgcc-file-name)`/install-tools/include/limits.h
}

build_linux_headers() {
    cd $SOURCES/linux/

    make mrproper

    make headers
    find usr/include -name '.*' -delete
    rm usr/include/Makefile
    cp -rv usr/include $SYSTEM_DIR/usr
}

build_glibc() {
    cd $SOURCES/glibc/

    case $(uname -m) in
        i?86)   ln -sfv ld-linux.so.2 $SYSTEM_DIR/lib/ld-lsb.so.3
        ;;
        x86_64) ln -sfv ../lib/ld-linux-x86-64.so.2 $SYSTEM_DIR/lib64
                ln -sfv ../lib/ld-linux-x86-64.so.2 $SYSTEM_DIR/lib64/ld-lsb-x86-64.so.3
        ;;
    esac

    mkdir -v build
    cd       build

    echo "rootsbindir=/usr/sbin" > configparms
    ../configure                             \
          --prefix=/usr                      \
          --host=$TGT                    \
          --build=$(../scripts/config.guess) \
          --enable-kernel=3.2                \
          --with-headers=$SYSTEM_DIR/usr/include    \
          libc_cv_slibdir=/usr/lib    

    make &&
    make DESTDIR=$SYSTEM_DIR install

    sed '/RTLDLIST=/s@/usr@@g' -i $SYSTEM_DIR/usr/bin/ldd

    $SYSTEM_DIR/tools/libexec/gcc/$TGT/$GCC_VERSION/install-tools/mkheaders
}

build_libstdcxx() {
    cd $SOURCES/gcc/

    rm -rf build
    mkdir build
    cd build

    ../libstdc++-v3/configure           \
        --host=$TGT                     \
        --build=$(../config.guess)      \
        --prefix=/usr                   \
        --disable-multilib              \
        --disable-nls                   \
        --disable-libstdcxx-pch         \
        --with-gxx-include-dir=/tools/$SYSTEM_DIR/include/c++/$GCC_VERSION

    make && 
    make DESTDIR=$SYSTEM_DIR install
}

build_m4() {
    cd $SOURCES/m4/
   ./configure --prefix=/usr   \
            --host=$TGT \
            --build=$(build-aux/config.guess)
 
   make
   make DESTDIR=$SYSTEM_DIR install
}

build_ncurses() {
    cd $SOURCES/ncurses/

    sed -i s/mawk// configure
    mkdir build

    pushd build
      ../configure
      make -C include
      make -C progs tic
    popd
    
    ./configure --prefix=/usr                \
            --host=$TGT              \
            --build=$(./config.guess)    \
            --mandir=/usr/share/man      \
            --with-manpage-format=normal \
            --with-shared                \
            --without-debug              \
            --without-ada                \
            --without-normal             \
            --disable-stripping          \
            --enable-widec

    make
    make DESTDIR=$SYSTEM_DIR TIC_PATH=$(pwd)/build/progs/tic install
    echo "INPUT(-lncursesw)" > $SYSTEM_DIR/usr/lib/libncurses.so
}

build_bash() {
    cd $SOURCES/bash/

    ./configure --prefix=/usr                   \
            --build=$(support/config.guess)     \
            --host=$TGT                         \
            --without-bash-malloc

    make
    make DESTDIR=$SYSTEM_DIR install
    ln -sv bash $SYSTEM_DIR/bin/sh
}

build_coreutils() {
    cd $SOURCES/coreutils/

    ./configure --prefix=/usr                     \
            --host=$TGT                           \
            --build=$(build-aux/config.guess)     \
            --enable-install-program=hostname     \
            --enable-no-install-program=kill,uptime

    make
    make DESTDIR=$SYSTEM_DIR install

    mv -v $SYSTEM_DIR/usr/bin/chroot              $SYSTEM_DIR/usr/sbin
    mkdir -pv $SYSTEM_DIR/usr/share/man/man8
    mv -v $SYSTEM_DIR/usr/share/man/man1/chroot.1 $SYSTEM_DIR/usr/share/man/man8/chroot.8
    sed -i 's/"1"/"8"/'                    $SYSTEM_DIR/usr/share/man/man8/chroot.8
}

build_diffutils() {
    cd $SOURCES/diffutils/

    ./configure --prefix=/usr --host=$TGT

    make
    make DESTDIR=$SYSTEM_DIR install
}

build_file() {
    cd $SOURCES/file/

    mkdir build
    pushd build
      ../configure --disable-bzlib      \
                   --disable-libseccomp \
                   --disable-xzlib      \
                   --disable-zlib
      make
    popd

    ./configure --prefix=/usr --host=$TGT --build=$(./config.guess)

    make FILE_COMPILE=$(pwd)/build/src/file
    make DESTDIR=$SYSTEM_DIR install
}

build_findutils() {
    cd $SOURCES/findutils/

    ./configure --prefix=/usr                   \
                --localstatedir=/var/lib/locate \
                --host=$TGT                 \
                --build=$(build-aux/config.guess)
    make
    make DESTDIR=$SYSTEM_DIR install
}

build_gawk() {
    cd $SOURCES/gawk/
    sed -i 's/extras//' Makefile.in
    ./configure --prefix=/usr   \
                --host=$TGT \
                --build=$(build-aux/config.guess)
    make
    make DESTDIR=$SYSTEM_DIR install
}

build_grep() {
    cd $SOURCES/grep

./configure --prefix=/usr   \
            --host=$TGT
make
make DESTDIR=$SYSTEM_DIR install
}

build_gzip() {
    cd $SOURCES/gzip/
    ./configure --prefix=/usr --host=$TGT
    make
    make DESTDIR=$SYSTEM_DIR install
}

build_make() {
    cd $SOURCES/make/
    ./configure --prefix=/usr   \
                --without-guile \
                --host=$TGT \
                --build=$(build-aux/config.guess)
    make
    make DESTDIR=$SYSTEM_DIR install
}

build_patch() {
    cd $SOURCES/patch/

    ./configure --prefix=/usr   \
            --host=$TGT \
            --build=$(build-aux/config.guess)
    make
    make DESTDIR=$SYSTEM_DIR install
}

build_sed() {
    cd $SOURCES/sed/

    ./configure --prefix=/usr --host=$TGT

    make
    make DESTDIR=$SYSTEM_DIR install
}

build_tar() {
    cd $SOURCES/tar/
    ./configure --prefix=/usr                     \
                --host=$TGT                   \
                --build=$(build-aux/config.guess)
    make
    make DESTDIR=$SYSTEM_DIR install
}

build_xz() {
    cd $SOURCES/xz/

    ./configure --prefix=/usr                     \
                --host=$TGT                   \
                --build=$(build-aux/config.guess) \
                --disable-static                  \
                --docdir=/usr/share/doc/xz-$XZ_VERSION
    make
    make DESTDIR=$SYSTEM_DIR install
}

build_binutils2() {
    cd $SOURCES/binutils/
    make clean 
    rm -rf build
    mkdir -v build
    cd       build
    ../configure                   \
        --prefix=/usr              \
        --build=$(../config.guess) \
        --host=$TGT            \
        --disable-nls              \
        --enable-shared            \
        --disable-werror           \
        --enable-64-bit-bfd
    make
    make DESTDIR=$SYSTEM_DIR install -j1
    install -vm755 libctf/.libs/libctf.so.0.0.0 $SYSTEM_DIR/usr/lib
}

build_gcc2() {
    cd $SOURCES/gcc/

    rm -rf build
    mkdir -v build
    cd       build

    mkdir -pv $TGT/libgcc
    ln -s ../../../libgcc/gthr-posix.h $TGT/libgcc/gthr-default.h
    ../configure                                       \
        --build=$(../config.guess)                     \
        --host=$TGT                                \
        --prefix=/usr                                  \
        CC_FOR_TARGET=$TGT-gcc                     \
        --with-build-sysroot=$SYSTEM_DIR                      \
        --enable-initfini-array                        \
        --disable-nls                                  \
        --disable-multilib                             \
        --disable-decimal-float                        \
        --disable-libatomic                            \
        --disable-libgomp                              \
        --disable-libquadmath                          \
        --disable-libssp                               \
        --disable-libvtv                               \
        --disable-libstdcxx                            \
        --enable-languages=c,c++
    make
    make DESTDIR=$SYSTEM_DIR install
    ln -sv gcc $SYSTEM_DIR/usr/bin/cc
}

if [ -e $SYSTEM_DIR ]; then
    printf "Remove existing system? [Y/n] "
    read response

    if [ "$response" != "n" ]; then
        rm -rf $SYSTEM_DIR
        echo "removed $SYSTEM_DIR"
    fi
fi


mkdir -p "$SYSTEM_DIR"
get_build_files
parse_package_versions > "$SYSTEM_DIR/versions"

get_sources ${packages[@]}

make_dir_struct $SYSTEM_DIR
init_versions

reset_before_build () {
    cd $SYSTEM_DIR; printf "\033[0;34mbuilding $1...\033[0m"
}

for package in ${packages[@]}; do
    cd $SYSTEM_DIR
    touch $package.build.log
done

reset_before_build "binutils1"
build_binutils1 &> binutils.build.log && printf "passed\n" || exit 1 

reset_before_build "gcc1"
build_gcc1 &> gcc1.build.log && printf "passed\n" || exit 1 

reset_before_build "linux_headers"
build_linux_headers &> linux-headers.build.log && printf "\033[0;32mpassed\n" || exit 1 

reset_before_build "glibc"
build_glibc &> glibc.build.log && printf "\033[0;32mpassed\n" || exit 1 

reset_before_build "libstdcxx"
build_libstdcxx &> libstdcxx.build.log && printf "\033[0;32mpassed\n" || exit 1 

reset_before_build "m4"
build_m4 &> m4.build.log && printf "\033[0;32mpassed\n" || exit 1 

reset_before_build "ncurses"
build_ncurses &> ncurses.build.log && printf "\033[0;32mpassed\n" || exit 1 

reset_before_build "bash"
build_bash &> bash.build.log && printf "\033[0;32mpassed\n" || exit 1 

reset_before_build "coreutils"
build_coreutils &> coreutils.build.log && printf "\033[0;32mpassed\n" || exit 1 

reset_before_build "diffutils"
build_diffutils &> diffutils.build.log && printf "\033[0;32mpassed\n" || exit 1

reset_before_build "file"
build_file &> file.build.log && printf "\033[0;32mpassed\n" || exit 1 

reset_before_build "findutils"
build_findutils &> findutils.build.log && printf "\033[0;32mpassed\n" || exit 1

reset_before_build "gawk"
build_gawk &> gawk.build.log && printf "\033[0;32mpassed\n" || exit 1 

reset_before_build "grep"
build_grep &> grep.build.log && printf "\033[0;32mpassed\n" || exit 1

reset_before_build "gzip"
build_gzip &> gzip.build.log && printf "\033[0;32mpassed\n" || exit 1

reset_before_build "make"
build_make &> make.build.log && printf "\033[0;32mpassed\n" || exit 1

reset_before_build "patch"
build_patch &> patch.build.log && printf "\033[0;32mpassed\n" || exit 1

reset_before_build "sed"
build_sed &> sed.build.log && printf "\033[0;32mpassed\n" || exit 1

reset_before_build "tar"
build_tar &> tar.build.log && printf "\033[0;32mpassed\n" || exit 1

reset_before_build "xz"
build_xz &> xz.build.log && printf "\033[0;32mpassed\n" || exit 1

reset_before_build "binutils2"
build_binutils2 &> bintuils2.build.log && printf "\033[0;32mpassed\n" || exit 1

reset_before_build "gcc2"
build_gcc2 &> gcc2.build.log && printf "\033[0;32mpassed\n" || exit 1


echo "DONE"

printf "Clean sources and logs? [Y/n]"
read response

if [ "$response" != "n" ]; then
    rm -rf $SYSTEM_DIR/*.log
    rm -rf $SYSTEM_DIR/sources
    echo "removed $SYSTEM_DIR/sources"
fi


