#!/bin/sh

cross_tools_kernel_headers () {
    src "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$LINUX_VER.tar.xz"

    make mrproper

    make ARCH=${ARCH} headers
    mkdir -p $CROSS_TOOLS/$TARGET/include

    cp -r usr/include/* $CROSS_TOOLS/$TARGET/include
    find $CROSS_TOOLS/$TARGET/include -name '.*.cmd' -exec rm -f {} \;
    rm $CROSS_TOOLS/$TARGET/include/Makefile
}

cross_tools_binutils () {
    src "https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILS_VER.tar.xz"

    mkdir build &&
        cd build &&

    ../configure \
       --prefix=${CROSS_TOOLS} \
       --target=${TARGET} \
       --host=${HOST}
       --with-sysroot=${CROSS_TOOLS}/${TARGET} \
       --disable-nls \
       --disable-multilib \
       --disable-werror \
       --enable-deterministic-archives \
       --disable-compressed-debug-sections &&

    make configure-host &&
    make && make install
}

cross_tools_gcc_static () {
    cd ${WD}
    src "https://ftp.gnu.org/gnu/mpfr/mpfr-$MPFR_VER.tar.xz"
    src "https://ftp.gnu.org/gnu/gmp/gmp-$GMP_VER.tar.xz"
    src "https://ftp.gnu.org/gnu/mpc/mpc-$MPC_VER.tar.gz"
    src "https://ftp.gnu.org/gnu/gcc/gcc-$GCC_VER/gcc-$GCC_VER.tar.xz"

    mv ../mpfr-$MPFR_VER mpfr &&
    mv ../gmp-$GMP_VER gmp &&
    mv ../mpc-$MPC_VER mpc &&

    mkdir build && cd  build &&

    CFLAGS='-g0 -O0' \
    CXXFLAGS=$CFLAGS \
    ../configure \
              --prefix=${CROSS_TOOLS} --build=${HOST} \
              --host=${HOST}   --target=${TARGET} \
              --with-sysroot=${CROSS_TOOLS}/${TARGET} \
              --disable-nls         --with-newlib  \
              --disable-libitm     --disable-libvtv \
              --disable-libssp     --disable-shared \
              --disable-libgomp    --without-headers \
              --disable-threads    --disable-multilib \
              --disable-libatomic  --disable-libstdcxx \
              --enable-languages=c --disable-libquadmath \
              --disable-libsanitizer --with-arch=${CPU} \
              --disable-decimal-float --enable-clocale=generic  &&

    make all-gcc all-target-libgcc &&
    make install-gcc install-target-libgcc 
}

cross_tools_musl () {
    src https://musl.libc.org/releases/musl-$MUSL_VER.tar.gz

    ./configure \
      CROSS_COMPILE=${TARGET}- \
      --prefix=/ \
      --target=${TARGET}  &&

    make && DESTDIR=${CROSS_TOOLS} make install &&

    # Add missing directory and link
    mkdir ${CROSS_TOOLS}/usr &&
    ln -s ../include  ${CROSS_TOOLS}/usr/include &&

    case $(uname -m) in
      x86_64) export ARCH="x86_64"
              ;;
      i686)   export ARCH="i386"
              ;;
      arm*)   export ARCH="arm"
              ;;
      aarch64) export ARCH="aarch64"
              ;;
    esac

    # Fix link
    rm -f ${CROSS_TOOLS}/lib/ld-musl-${ARCH}.so.1 &&
    ln -s libc.so ${CROSS_TOOLS}/lib/ld-musl-${ARCH}.so.1

    # Create link for ldd:
    ln -s ../lib/ld-musl-$ARCH.so.1 ${CROSS_TOOLS}/bin/ldd

    # Create config for dynamic library loading:
    mkdir ${CROSS_TOOLS}/etc

    echo $CROSS_TOOLS/lib >> ${CROSS_TOOLS}/etc/ld-musl-$ARCH.path 
    echo $TOOLS/lib >> ${CROSS_TOOLS}/etc/ld-musl-$ARCH.path 

    unset ARCH ARCH2
}

cross_tools_gcc_final () {
    cd ${WD}
    rm -rf *

    src "https://www.mpfr.org/mpfr-$MPFR_VER/mpfr-$MPFR_VER.tar.xz"
    src "https://ftp.gnu.org/gnu/gmp/gmp-$GMP_VER.tar.xz"
    src "https://ftp.gnu.org/gnu/mpc/mpc-$MPC_VER.tar.gz"
    src "https://ftp.gnu.org/gnu/gcc/gcc-$GCC_VER/gcc-$GCC_VER.tar.xz"

    mv ../mpfr-$MPFR_VER mpfr
    mv ../gmp-$GMP_VER gmp
    mv ../mpc-$MPC_VER mpc

    patch_gcc

# Configure in a dedicated build directory
mkdir build && cd  build &&
AR=ar LDFLAGS="-Wl,-rpath,${CROSS_TOOLS}/lib" \
../configure \
    --prefix=${CROSS_TOOLS} \
    --build=${HOST} \
    --host=${HOST} \
    --target=${TARGET} \
    --disable-multilib \
    --with-sysroot=${CROSS_TOOLS} \
    --disable-nls \
    --enable-shared \
    --enable-languages=c,c++ \
    --enable-threads=posix \
    --enable-clocale=generic \
    --enable-libstdcxx-time \
    --enable-fully-dynamic-string \
    --disable-symvers \
    --disable-libsanitizer \
    --disable-lto-plugin \
    --disable-libssp 

    # Build
    make AS_FOR_TARGET="${TARGET}-as" \
        LD_FOR_TARGET="${TARGET}-ld" &&

    # Install
    make install
}

cross_tools_file () {
    src "https://astron.com/pub/file/file-$FILE_VER.tar.gz"
    ./configure --prefix=${CROSS_TOOLS} --disable-libseccomp
    make && make install
}

for p in kernel_headers binutils gcc_static musl gcc_final file; do
    printf "${BLUE}building $p...\n${RESET}"
    cross_tools_$p || die "Failed building $p"
done
printf "${GREEN}finished building cross-tools${RESET}\n"
