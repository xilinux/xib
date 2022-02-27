#!/bin/sh

set_env () {
    CC="${TARGET}-gcc"
    CXX="${TARGET}-g++"
    AR="${TARGET}-ar"
    AS="${TARGET}-as"
    RANLIB="${TARGET}-ranlib"
    LD="${TARGET}-ld"
    STRIP="${TARGET}-strip"
    export CC CXX AR AS RANLIB LD STRIP
}

toolchain_musl () {
    src "https://musl.libc.org/releases/musl-$MUSL_VER.tar.gz"
    ./configure \
        CROSS_COMPILE=${TARGET}- \
        --prefix=/ \
        --target=${TARGET} &&

    make && make DESTDIR=$TOOLS install &&

    case $(uname -m) in
      x86_64)  rm -v  $TOOLS/lib/ld-musl-x86_64.so.1
               ln -sv libc.so $TOOLS/lib/ld-musl-x86_64.so.1
               export barch=$(uname -m)
               ;;
      i686)    rm -v  $TOOLS/lib/ld-musl-i386.so.1
               ln -sv libc.so $TOOLS/lib/ld-musl-i386.so.1
               export barch=i386
               ;;
      arm*)    rm -v  $TOOLS/lib/ld-musl-arm.so.1
               ln -sv libc.so $TOOLS/lib/ld-musl-arm.so.1
               export barch=arm
               ;;
      aarch64) rm -v $TOOLS/lib/ld-musl-aarch64.so.1
               ln -sv libc.so $TOOLS/lib/ld-musl-aarch64.so.1
               export barch=$(uname -m)
               ;;
    esac &&

    # Create dynamic linker config
    mkdir -pv $TOOLS/etc &&
    echo "$TOOLS/lib" > $TOOLS/etc/ld-musl-${barch}.path
    unset barch
}

toolchain_adjustments () {
    export SPECFILE=`dirname $(${TARGET}-gcc -print-libgcc-file-name)`/specs
    ${TARGET}-gcc -dumpspecs > specs

    case $(uname -m) in
      x86_64)  sed -i 's/\/lib\/ld-musl-x86_64.so.1/\/tools\/lib\/ld-musl-x86_64.so.1/g' specs
               # check with
               grep "/tools/lib/ld-musl-x86_64.so.1" specs  --color=auto
               ;;
      i686)    sed -i 's/\/lib\/ld-musl-i386.so.1/\/tools\/lib\/ld-musl-i386.so.1/g' specs
               # check with
               grep "/tools/lib/ld-musl-i386.so.1" specs  --color=auto
               ;;
      arm*)    sed -i 's/\/lib\/ld-musl-arm/\/tools\/lib\/ld-musl-arm/g' specs
               # check with
               grep "/tools/lib/ld-musl-arm" specs  --color=auto
               ;;
      aarch64) sed -i 's/\/lib\/ld-musl-aarch64/\/tools\/lib\/ld-musl-aarch64/g' specs
               # check with
               grep "/tools/lib/ld-musl-aarch64" specs  --color=auto
               ;;
    esac

    # Install modified specs to the cross toolchain
    mv -v specs $SPECFILE
    unset SPECFILE

    # Quick check the tool chain:
    echo 'int main(){}' > dummy.c
    ${TARGET}-gcc dummy.c
    ${TARGET}-readelf -l a.out | grep Requesting

    echo
    echo "Output should be:"
    echo "[Requesting program interpreter: /tools/lib/ld-musl-x86_64.so.1]"
    echo "or"
    echo "[Requesting program interpreter: /tools/lib/ld-musl-i386.so.1]"
    echo "or"
    echo "[Requesting program interpreter: /tools/lib/ld-musl-arm.so.1]"
    echo "or"
    echo "[Requesting program interpreter: /tools/lib/ld-musl-aarch64.so.1]"
    echo "Please confirm the above, and pres enter to continue:"
    read confirm

    rm -v a.out dummy.c 
}

toolchain_binutils () {
    src "https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILS_VER.tar.xz"

    # Link directories so libraries can be found in both lib & lib64
    case $(uname -m) in
            x86_64) ln -sv lib $TOOLS/lib64 ;;
    esac &&

    # Configure in dedicated build directory
    mkdir -v build && cd build &&
    ../configure --prefix=$TOOLS            \
                 --with-lib-path=$TOOLS/lib \
                 --build=${HOST}       \
                 --host=${TARGET}      \
                 --target=${TARGET}    \
                 --disable-nls              \
                 --disable-werror           \
                 --with-sysroot &&
                 
    make &&
    make install &&

    make -C ld clean &&
    make -C ld LIB_PATH=/usr/lib:/lib &&
    cp -v ld/ld-new $TOOLS/bin 
}

toolchain_gcc () {
    src "https://www.mpfr.org/mpfr-$MPFR_VER/mpfr-$MPFR_VER.tar.xz"
    src "https://ftp.gnu.org/gnu/gmp/gmp-$GMP_VER.tar.xz"
    src "https://ftp.gnu.org/gnu/mpc/mpc-$MPC_VER.tar.gz"
    src "https://ftp.gnu.org/gnu/gcc/gcc-$GCC_VER/gcc-$GCC_VER.tar.xz"

    mv -v ../mpfr-$MPFR_VER mpfr &&
    mv -v ../gmp-$GMP_VER gmp &&
    mv -v ../mpc-$MPC_VER mpc &&

    patch_gcc &&

    # Re-create internal header
    cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
      $(dirname $($TARGET-gcc -print-libgcc-file-name))/include-fixed/limits.h &&

    ## Change the location of GCC's default dynamic linker to use the one installed in /tools
    #
    # For i686/x86_64:
    for file in gcc/config/linux/linux.h gcc/config/linux/linux64.h gcc/config/i386/linux.h gcc/config/i386/linux64.h
    do
      cp -uv $file $file.orig
      sed -e "s,/lib\(64\)\?\(32\)\?/ld,$TOOLS&,g" \
          -e "s,/usr,$TOOLS,g" ${file}.orig > ${file}
      echo "
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 \"$TOOLS/lib/\"
#define STANDARD_STARTFILE_PREFIX_2 \"\"" >> ${file}
      touch ${file}.orig
    done &&

    # Configure in dedicated build directory
    mkdir -v build && cd build &&
    CFLAGS='-g0 -O0' \
    CXXFLAGS=$CFLAGS \
    ../configure                                       \
        --target=${TARGET}                             \
        --build=${HOST}                                \
        --host=${TARGET}                               \
        --prefix=$TOOLS                                \
        --with-local-prefix=$TOOLS                     \
        --with-native-system-header-dir=$TOOLS/include \
        --enable-languages=c,c++                       \
        --disable-libstdcxx-pch                        \
        --disable-multilib                             \
        --disable-bootstrap                            \
        --disable-libgomp                              \
        --disable-libquadmath                          \
        --disable-libssp                               \
        --disable-libvtv                               \
        --disable-symvers                              \
        --disable-libitm                               \
        --disable-libsanitizer                         &&

        PATH=/bin:/usr/bin:$CROSS_TOOLS/bin:$TOOLS/bin make &&
        make install &&
        ln -sv gcc $TOOLS/bin/cc
}

toolchain_kernel_headers () {
    src "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$LINUX_VER.tar.xz"

    make mrproper &&
    ARCH=${ARCH} make headers &&
    cp -rv usr/include/* $TOOLS/include

    find $TOOLS/include -name '.*.cmd' -exec rm -vf {} \;
    rm -v $TOOLS/include/Makefile
}

toolchain_libstdcxx () {
    rm -rf ${WD} ; mkdir ${WD}
    src "https://www.mpfr.org/mpfr-$MPFR_VER/mpfr-$MPFR_VER.tar.xz"
    src "https://ftp.gnu.org/gnu/gmp/gmp-$GMP_VER.tar.xz"
    src "https://ftp.gnu.org/gnu/mpc/mpc-$MPC_VER.tar.gz"
    src "https://ftp.gnu.org/gnu/gcc/gcc-$GCC_VER/gcc-$GCC_VER.tar.xz"

    mv -v ../mpfr-$MPFR_VER mpfr &&
    mv -v ../gmp-$GMP_VER gmp &&
    mv -v ../mpc-$MPC_VER mpc &&

    ptch "https://raw.githubusercontent.com/dslm4515/Musl-LFS/master/patches/gcc-mlfs-$GCC_VER/fix_fenv_header.patch" &&
    patch_gcc &&

    mkdir -v build && cd build &&
    ../libstdc++-v3/configure           \
        --target=${TARGET}              \
        --build=${HOST}                 \
        --host=${TARGET}                \
        --prefix=$TOOLS                 \
        --disable-multilib              \
        --disable-nls                   \
        --disable-libstdcxx-threads     \
        --disable-libstdcxx-pch         \
        --with-gxx-include-dir=$TOOLS/${TARGET}/include/c++/$GCC_VER &&

    make &&
    make install 
}

toolchain_tcl () {
    local source="https://downloads.sourceforge.net/tcl/tcl$TCL_VER-src.tar.gz"
    local filename=$(basename $source)
    printf "${LIGHT_BLUE}Fetching $filename...${RESET}\n"
    curl ${CURL_OPTS} $source > $filename
    extract $filename
    cd tcl$TCL_VER
    
    cd unix
    ac_cv_func_strtod=yes \
    tcl_cv_strtod_buggy=1 \
    ./configure --build=${HOST} \
                --host=${TARGET} \
                --prefix=${TOOLS} &&

    make && make install

    chmod -v u+w $TOOLS/lib/libtcl${TCL_VER%.*}.so
    make install-private-headers
    ln -sv tclsh${TCL_VER%.*} $TOOLS/bin/tclsh
}

toolchain_expect () {
    src "https://prdownloads.sourceforge.net/expect/expect$EXPECT_VER.tar.gz"

    PATCH_URL="https://raw.githubusercontent.com/dslm4515/Musl-LFS/master/patches/expect-5.45.3"
    ptch $PATCH_URL/dont-put-toolchain-in-libpath.patch
    ptch $PATCH_URL/dont-configure-testsuites.patch
    ptch $PATCH_URL/allow-cross-compile.patch

    curl ${CURL_OPTS} "https://raw.githubusercontent.com/dslm4515/Musl-LFS/master/files/config.guess-musl" > tclconfig/config.guess
    curl ${CURL_OPTS} "https://raw.githubusercontent.com/dslm4515/Musl-LFS/master/files/config.sub-musl" > tclconfig/config.sub
    cp -v configure configure.orig
    sed 's:/usr/local/bin:/bin:' configure.orig > configure

    ./configure --build=${HOST} \
                --host=${TARGET} \
                --prefix=$TOOLS \
                --with-tcl=$TOOLS/lib \
                --with-tclinclude=$TOOLS/include &&

    make && make SCRIPTS="" install
}

toolchain_dejagnu () {
    src "https://ftp.gnu.org/gnu/dejagnu/dejagnu-$DEJAGNU_VER.tar.gz"
    ./configure --build=${HOST} \
                --host=${TARGET} \
                --prefix=$TOOLS &&

    make && make install
}

toolchain_m4 () {
    src "https://ftp.gnu.org/gnu/m4/m4-$M4_VER.tar.xz"

    ./configure --prefix=$TOOLS \
                --build=${HOST} \
                --host=${TARGET} &&

    make && make install
}

toolchain_ncurses () {
    src "https://invisible-mirror.net/archives/ncurses/ncurses-$NCURSES_VER.tar.gz" 
    sed -i s/mawk// configure

   # Configure source
    ./configure --prefix=${TOOLS} \
       --build=${HOST}  \
       --host=${TARGET} \
       --with-shared    \
       --without-debug  \
       --without-ada    \
       --enable-widec   \
       --enable-overwrite     
    make && make install
    echo "INPUT(-lncursesw)" > ${TOOLS}/lib/libncurses.so
    ln -s libncurses.so ${TOOLS}/lib/libcurses.so
}

toolchain_bash () {
    src "https://ftp.gnu.org/gnu/bash/bash-$BASH_VER.tar.gz"

    cat > config.cache << "EOF"
ac_cv_func_mmap_fixed_mapped=yes
ac_cv_func_strcoll_works=yes
ac_cv_func_working_mktime=yes
bash_cv_func_sigsetjmp=present
bash_cv_getcwd_malloc=yes
bash_cv_job_control_missing=present
bash_cv_printf_a_format=yes
bash_cv_sys_named_pipes=present
bash_cv_ulimit_maxfds=yes
bash_cv_under_sys_siglist=yes
bash_cv_unusable_rtsigs=no
gt_cv_int_divbyzero_sigfpe=yes
EOF
    ./configure --prefix=${TOOLS} \
                --without-bash-malloc \
                --build=${HOST} \
                --host=${TARGET} \
                --cache-file=config.cache &&

    make && make install
}

toolchain_bison () {
    src "https://ftp.gnu.org/gnu/bison/bison-$BISON_VER.tar.xz"
    ./configure --prefix=${TOOLS} \
                --build=${HOST} \
                --host=${TARGET} &&
    make && make install
}

toolchain_coreutils () {
    git clone git://git.suckless.org/sbase sbase
    cd sbase
    make && make DESTDIR=$TOOLS install 
}

toolchain_diffutils () {
    src "https://ftp.gnu.org/gnu/diffutils/diffutils-$DIFFUTILS_VER.tar.xz"
    ./configure --prefix=${TOOLS} \
                --build=${HOST} \
                --host=${TARGET}

    make && make install
}

toolchain_file () {
    src "https://astron.com/pub/file/file-$FILE_VER.tar.gz"
    ./configure --prefix=${TOOLS} \
                --build=${HOST} \
                --host=${TARGET}
    make && make install
}

toolchain_findutils () {
    src "https://ftp.gnu.org/gnu/findutils/findutils-$FINDUTILS_VER.tar.xz"
    sed -i 's/IO_ftrylockfile/IO_EOF_SEEN/' gl/lib/*.c               &&
    sed -i '/unistd/a #include <sys/sysmacros.h>' gl/lib/mountlist.c &&
    echo "#define _IO_IN_BACKUP 0x100" >> gl/lib/stdio-impl.h

    ./configure --prefix=${TOOLS} \
                --build=${HOST} \
                --host=${TARGET}

    make && make install
}

toolchain_gawk () {
    src "https://ftp.gnu.org/gnu/gawk/gawk-$GAWK_VER.tar.xz"
    ./configure --prefix=${TOOLS} \
            --build=${HOST} \
            --host=${TARGET}
    make && make install
}

toolchain_gettext () {
    src "https://ftp.barfooze.de/pub/sabotage/tarballs/gettext-tiny-$GETTEXT_TINY_VER.tar.xz"
    make ${MJ} LIBINTL=MUSL prefix=$TOOLS
    cp -v msgfmt msgmerge xgettext $TOOLS/bin 
}

toolchain_grep () {
    src "https://ftp.gnu.org/gnu/grep/grep-$GREP_VER.tar.xz"

    ./configure --prefix=${TOOLS} \
            --build=${HOST} \
            --host=${TARGET} &&
    make && make install
}

toolchain_make () {
    src "https://ftp.gnu.org/gnu/make/make-$MAKE_VER.tar.gz"

    ./configure --prefix=${TOOLS} \
            --build=${HOST} \
            --host=${TARGET} \
            --without-guile &&
    make && make install
}

toolchain_patch () {
    src "https://ftp.gnu.org/gnu/patch/patch-$PATCH_VER.tar.xz"
    ./configure --prefix=${TOOLS} \
            --build=${HOST} \
            --host=${TARGET} &&
    make && make install
}

toolchain_sed () {
    src "https://ftp.gnu.org/gnu/sed/sed-$SED_VER.tar.xz"
    ./configure --prefix=${TOOLS} \
            --build=${HOST} \
            --host=${TARGET} &&
    make && make install
}

#toolchain_perl () {
#    src "https://github.com/arsv/perl-cross/releases/download/$PERL_CROSS_VER/perl-cross-$PERL_CROSS_VER.tar.gz"
#    src "https://www.cpan.org/src/5.0/perl-$PERL_VER.tar.xz"
#
#    cp -vrf ../perl-cross-$PERL_CROSS_VER/* ./
#
#    ./configure --prefix=${TOOLS} \
#                --target=${TARGET} &&
#    make &&
#    cp -v perl cpan/podlators/scripts/pod2man ${TOOLS}/bin &&
#    mkdir -pv ${TOOLS}/lib/perl5/$PERL_VER    &&
#    cp -Rv lib/* ${TOOLS}/lib/perl5/$PERL_VER
#}

toolchain_texinfo () {
    src "https://ftp.gnu.org/gnu/texinfo/texinfo-$TEXINFO_VER.tar.xz"
    ./configure --prefix=${TOOLS} \
            --build=${HOST} \
            --host=${TARGET} &&
    make && make install
}

toolchain_flex () {
    src "https://github.com/westes/flex/releases/download/v$FLEX_VER/flex-$FLEX_VER.tar.gz"

    ac_cv_func_malloc_0_nonnull=yes   \
    ac_cv_func_realloc_0_nonnull=yes  \
    HELP2MAN=${TOOLS}/bin/true          \
    ./configure --prefix=${TOOLS}       \
                --build=${HOST}  \
                --host=${TARGET}
    make && make install
}

toolchain_strip () {
    find ${TOOLS}/lib -type f -exec strip --strip-unneeded {} \;
    /usr/bin/strip --strip-unneeded ${TOOLS}/bin/* ${TOOLS}/sbin/*

    # Remove the documentation:
    rm -rf ${TOOLS}/share/info \
        ${TOOLS}/share/man \
        ${TOOLS}/share/doc \
        ${TOOLS}/info \
        ${TOOLS}/man \
        ${TOOLS}/doc 

    find ${TOOLS}/lib ${TOOLS}/libexec -name \*.la -exec rm -rvf {} \;
}

printf "${BLUE}building musl...\n${RESET}"
toolchain_musl || die "Failed building musl"
toolchain_adjustments
        #perl \
for p in \
        binutils \
        gcc \
        kernel_headers \
        libstdcxx \
        tcl \
        expect \
        dejagnu \
        m4 \
        ncurses \
        bash \
        bison \
        coreutils \
        diffutils \
        file \
        findutils \
        gawk \
        gettext \
        grep \
        make\
        patch \
        sed \
        texinfo \
        flex \
        ; do

    printf "${BLUE}building $p...\n${RESET}"
    set_env
    toolchain_$p || die "Failed building $p"
done

printf "${GREEN}finished building toolchain${RESET}\n"