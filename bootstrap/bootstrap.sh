#!/bin/bash


## VERSIONS ##
# TODO move to a different package
 
WD=$(pwd)/working
BUILDFILES=$WD/buildfiles

getbuildfiles () {
    [ -d $BUILDFILES ] &&  { 
        cd $BUILDFILES
        git pull
        cd $OLDPWD
    } || {
        mkdir $BUILDFILES
        git clone https://xi.davidovski.xyz/git/buildfiles.git $BUILDFILES
    }
}

getversion() {
    find $BUILDFILES/ -name "$1.xibuild" | head -1 | xargs grep "PKG_VER=" | cut -d"=" -f2
}

getbuildfiles

LINUX_VER=$(getversion linux)
BINUTILS_VER=$(getversion binutils)
MPFR_VER=$(getversion mpfr)
MPC_VER=$(getversion mpc)
GMP_VER=$(getversion gmp)
GCC_VER=$(getversion gcc)
MUSL_VER=$(getversion musl)
FILE_VER=$(getversion file)
TCL_VER=$(getversion tcl)
M4_VER=$(getversion m4)
EXPECT_VER=$(getversion expect)
DEJAGNU_VER=$(getversion dejagnu)
NCURSES_VER=$(getversion ncurses)
BASH_VER=$(getversion bash)
BISON_VER=$(getversion bison)
BZIP2_VER=$(getversion bzip2)
COREUTILS_VER=$(getversion sbase)
DIFFUTILS_VER=$(getversion diffutils)
GAWK_VER=$(getversion gawk)
GETTEXT_VER=$(getversion gettext)
GREP_VER=$(getversion grep)
GZIP_VER=$(getversion gzip)
MAKE_VER=$(getversion make)
PATCH_VER=$(getversion patch)
SED_VER=$(getversion sed)
PERL_VER=$(getversion perl)
TEXINFO_VER=$(getversion texinfo)
FLEX_VER=$(getversion fle)
PERL_CROSS_VER=1.3.6
GETTEXT_TINY_VER=$(getversion gettext)
FINDUTILS_VER=$(getversion findutils)

####

CURL_OPTS="-SsL"


HOST=x86_64-linux-musl
TARGET=x86_64-linux-musl
ARCH=x86
CPU=x86-64

CROSS_TOOLS=/xilinux/bootstrap/cross-tools
TOOLS=/xilinux/bootstrap/tools
chroot=$(pwd)/chroot

PATH=${TOOLS}/bin:${CROSS_TOOLS}/bin:/usr/bin

MAKEFLAGS="-j$(grep "processor" /proc/cpuinfo | wc -l)"

export chroot TARGET PATH WD CURL_OPTS CROSS_TOOLS TOOLS MAKEFLAGS

unset CFLAGS CXXFLAGS

die () {
    printf "${RED}$@${RESET}\n"
    exit 1
}

extract () {
    echo "extracting $1"
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
        "xz" )
            tar -xf $FILE
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
    file $filename
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
    mkdir -p $WD $CROSS_TOOLS $TOOL
}

mount_chroot () {
    mkdir -p $chroot/{dev,proc,sys,run}
    mknod -m 600 $chroot/dev/console c 5 1
    mknod -m 666 $chroot/dev/null c 1 3

    mount --bind /dev $chroot/dev
    mount -t devpts devpts $chroot/dev/pts -o gid=5,mode=620
    mount -t proc proc $chroot/proc
    mount -t sysfs sysfs $chroot/sys
    mount -t tmpfs tmpfs $chroot/run
    if [ -h $chroot/dev/shm ]; then
      mkdir -p $chroot/$(readlink $chroot/dev/shm)
    fi
}

umount_chroot () {
    umount $chroot/dev/pts
    umount $chroot/dev
    umount $chroot/run
    umount $chroot/proc
    umount $chroot/sys
}

tchroot () {
    chroot "$chroot" /tools/bin/env -i \
    HOME=/root                  \
    TERM="$TERM"                \
    PS1='(chroot) \u:\w\$ ' \
    PATH=/bin:/usr/bin:/sbin:/usr/sbin:/tools/bin \
    $@
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

create_chroot () {
    PATH=/usr/bin:/bin
    mkdir chroot
    xi -l -r ${chroot} bootstrap
    echo "copying tools..."
    mkdir ${chroot}/tools
    cp -r ${TOOLS} ${chroot}/

    echo "making essential links"

    ln -s /tools/bin/bash ${chroot}/bin
    ln -s /tools/bin/cat ${chroot}/bin
    ln -s /tools/bin/dd ${chroot}/bin
    ln -s /tools/bin/echo ${chroot}/bin
    ln -s /tools/bin/ln ${chroot}/bin
    ln -s /tools/bin/pwd ${chroot}/bin
    ln -s /tools/bin/rm ${chroot}/bin
    ln -s /tools/bin/stty ${chroot}/bin
    ln -s /tools/bin/install ${chroot}/bin
    ln -s /tools/bin/env ${chroot}/bin
    #ln -s /tools/bin/perl ${chroot}/bin

    ln -s /tools/lib/libgcc_s.so.1 ${chroot}/usr/lib
    ln -s /tools/lib/libgcc_s.so ${chroot}/usr/lib

    ln -s /tools/lib/libstdc++.a ${chroot}/usr/lib
    ln -s /tools/lib/libstdc++.so ${chroot}/usr/lib
    ln -s /tools/lib/libstdc++.so.6 ${chroot}/usr/lib
    ln -s bash ${chroot}/bin/sh 

    mkdir -p ${chroot}/etc
    ln -s /proc/self/mounts ${chroot}/etc/mtab

    cat > ${chroot}/etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
daemon:x:6:6:Daemon User:/dev/null:/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/var/run/dbus:/bin/false
nobody:x:99:99:Unprivileged User:/dev/null:/bin/false
EOF

    cat > ${chroot}/etc/group << "EOF"
root:x:0:
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
usb:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
mail:x:34:
nogroup:x:99:
users:x:999:
EOF

    echo "Created chroot"
}

package_chroot () {
    PATH=/usr/bin:/bin
    echo "compressing..."
    echo ${chroot}
    tar -C ${chroot} -czf chroot-tools.tar.gz ./
    echo "created chroot-tools.tar.gz..."
}

[ -f /usr/lib/colors.sh ] && . /usr/lib/colors.sh

rm -rf $WD ; mkdir $WD

case "$1" in
    stage1|cross|cross_tools)
        . ./stage1.sh
        ;;
    stage2|tools|toolchain)
        . ./stage2.sh
        ;;
    stage3)
        . ./stage3.sh
        ;;
    package)
        umount_chroot
        package_chroot
        ;;
    *)
        clean
        $0 stage1
        $0 stage2
        $0 stage3
        umount_chroot
        package_chroot
        ;;
esac

