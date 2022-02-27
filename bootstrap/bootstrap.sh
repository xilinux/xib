#!/bin/sh


## VERSIONS ##
# TODO move to a different package

LINUX_VER=5.16.11
BINUTILS_VER=2.38
MPFR_VER=4.1.0
MPC_VER=1.2.1
GMP_VER=6.2.1
GCC_VER=11.2.0
MUSL_VER=1.2.2
FILE_VER=5.41
TCL_VER=8.6.12
M4_VER=1.4.19
EXPECT_VER=5.45.4
DEJAGNU_VER=1.6.3
NCURSES_VER=6.3
BASH_VER=5.1.16
BISON_VER=3.8.2
BZIP2_VER=1.0.8
COREUTILS_VER=9.0
DIFFUTILS_VER=3.8
GAWK_VER=5.1.1
GETTEXT_VER=0.21
GREP_VER=3.7
GZIP_VER=1.11
MAKE_VER=4.3
PATCH_VER=2.7.6
SED_VER=4.8
PERL_VER=5.34.0
TEXINFO_VER=6.8
FLEX_VER=2.6.4
PERL_CROSS_VER=1.3.6
GETTEXT_TINY_VER=0.3.2
FINDUTILS_VER=4.9.0

####

CURL_OPTS="-SsL"

WD=$(pwd)/working

TARGET=x86_64-linux-musl
ARCH=x86
CPU=x86-64

CROSS_TOOLS=/cross-tools
TOOLS=/tools

PATH=${TOOLS}/bin:${CROSS_TOOLS}/bin:/usr/bin

MAKEFLAGS="-j$(nproc)"

export CHROOT TARGET PATH WD CURL_OPTS CROSS_TOOLS TOOLS MAKEFLAGS

unset CFLAGS CXXFLAGS

die () {
    printf "${RED}$@${RESET}\n"
    exit 1
}

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
            unzip $FILE
            ;;
        * )
            tar -xf $FILE
            ;;
    esac
}

src () {
    cd ${WD}
    local source=$1
    local filename=$(basename $source)
    printf "${LIGHT_BLUE}Fetching $filename...${RESET}\n"

    curl ${CURL_OPTS} $source > $filename
    extract $filename
    cd ${filename%.t*}
}

ptch () {
    local source=$1
    local filename=$(basename $source)

    printf "${LIGHT_BLUE}Patching $filename...${RESET}\n"
    curl ${CURL_OPTS} $source > $filename
    patch -Np1 -i $filename
}

clean () {
    rm -rf $WD $CROSS_TOOLS $TOOLS
    mkdir -pv $WD $CROSS_TOOLS $TOOL
}

patch_gcc () {
    local PATCH_SRC="https://raw.githubusercontent.com/dslm4515/Musl-LFS/master/patches/gcc-alpine"

    ptch $PATCH_SRC/0001-posix_memalign.patch &&
    ptch $PATCH_SRC/0003-Turn-on-Wl-z-relro-z-now-by-default.patch &&
    ptch $PATCH_SRC/0004-Turn-on-D_FORTIFY_SOURCE-2-by-default-for-C-C-ObjC-O.patch &&
    ptch $PATCH_SRC/0006-Enable-Wformat-and-Wformat-security-by-default.patch &&
    ptch $PATCH_SRC/0007-Enable-Wtrampolines-by-default.patch &&
    ptch $PATCH_SRC/0009-Ensure-that-msgfmt-doesn-t-encounter-problems-during.patch &&
    ptch $PATCH_SRC/0010-Don-t-declare-asprintf-if-defined-as-a-macro.patch &&
    ptch $PATCH_SRC/0011-libiberty-copy-PIC-objects-during-build-process.patch &&
    ptch $PATCH_SRC/0012-libitm-disable-FORTIFY.patch &&
    ptch $PATCH_SRC/0013-libgcc_s.patch &&
    ptch $PATCH_SRC/0014-nopie.patch &&
    ptch $PATCH_SRC/0015-libffi-use-__linux__-instead-of-__gnu_linux__-for-mu.patch &&
    ptch $PATCH_SRC/0016-dlang-update-zlib-binding.patch &&
    ptch $PATCH_SRC/0017-dlang-fix-fcntl-on-mips-add-libucontext-dep.patch &&
    ptch $PATCH_SRC/0018-ada-fix-shared-linking.patch &&
    ptch $PATCH_SRC/0019-build-fix-CXXFLAGS_FOR_BUILD-passing.patch &&
    ptch $PATCH_SRC/0020-add-fortify-headers-paths.patch &&
    ptch $PATCH_SRC/0023-Pure-64-bit-MIPS.patch &&
    ptch $PATCH_SRC/0024-use-pure-64-bit-configuration-where-appropriate.patch &&
    ptch $PATCH_SRC/0025-always-build-libgcc_eh.a.patch &&
    ptch $PATCH_SRC/0027-ada-musl-support-fixes.patch &&
    ptch $PATCH_SRC/0028-gcc-go-Use-_off_t-type-instead-of-_loff_t.patch &&
    ptch $PATCH_SRC/0029-gcc-go-Don-t-include-sys-user.h.patch &&
    ptch $PATCH_SRC/0030-gcc-go-Fix-ucontext_t-on-PPC64.patch &&
    ptch $PATCH_SRC/0031-gcc-go-Fix-handling-of-signal-34-on-musl.patch &&
    ptch $PATCH_SRC/0032-gcc-go-Use-int64-type-as-offset-argument-for-mmap.patch &&
    #ptch $PATCH_SRC/0034-gcc-go-signal-34-is-special-on-musl-libc  &&
    ptch $PATCH_SRC/0035-gcc-go-Prefer-_off_t-over-_off64_t.patch &&
    ptch $PATCH_SRC/0036-gcc-go-undef-SETCONTEXT_CLOBBERS_TLS-in-proc.c.patch &&
    ptch $PATCH_SRC/0037-gcc-go-link-to-libucontext.patch &&
    ptch $PATCH_SRC/0038-gcc-go-Disable-printing-of-unaccessible-ppc64-struct.patch &&
    ptch $PATCH_SRC/0041-Use-generic-errstr.go-implementation-on-musl.patch &&
    ptch $PATCH_SRC/0042-Disable-ssp-on-nostdlib-nodefaultlibs-and-ffreestand.patch &&
    ptch $PATCH_SRC/0043-configure-Add-enable-autolink-libatomic-use-in-LINK_.patch 
    #ptch $PATCH_SRC/0022-DP-Use-push-state-pop-state-for-gold-as-well-when-li.patch &&
}

package_chroot () {
    PATH=/usr/bin:/bin
    local chroot=$(pwd)/chroot
    mkdir chroot
    xi -r ${chroot} bootstrap
    cp -r ${TOOLS} ${chroot}/tools
    ln -s /tools/bin/bash ${chroot}/bin/sh
    tar -C ${chroot} -czf chroot-tools.tar.gz ./
}

[ -f /usr/lib/colors.sh ] && . /usr/lib/colors.sh

rm -rf $WD ; mkdir $WD

# TODO bad impl
if [ "$#" = "0" ]; then
    clean
    $0 stage1
    $0 stage2
else
    case "$1" in
        stage1|cross|cross_tools)
            . ./cross_tools.sh
            ;;
        stage2|tools|toolchain)
            . ./toolchain.sh
            ;;
        package)
                package_chroot
            ;;
        *)
            clean
            $0 stage1
            $0 stage2
            ;;
    esac
fi

