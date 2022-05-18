#!/bin/bash

clean_build () {
    rm -rf ${chroot}/build
    mkdir ${chroot}/build
}

build_headers () {
    src "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$LINUX_VER.tar.xz"
    make mrproper

    ptch "https://raw.githubusercontent.com/dslm4515/Musl-LFS/master/patches/kernel/include-uapi-linux-swab-Fix-potentially-missing-__always_inline.patch"

    cat > ${chroot}/build/build.sh << "EOF"
#!/bin/bash
cd /build/
cp -r */* .

make headers
mkdir /usr/include
cp -r usr/include/* /usr/include
find /usr/include -name '.*' -exec rm -f {} \; 
rm /usr/include/Makefile
EOF
    chmod +x ${chroot}/build/build.sh
    tchroot  /build/build.sh
}

build_musl () {
    src "https://musl.libc.org/releases/musl-$MUSL_VER.tar.gz"
    ptch "https://raw.githubusercontent.com/dslm4515/Musl-LFS/master/patches/musl-mlfs/fix-utmp-wtmp-paths.patch"
    ptch "https://raw.githubusercontent.com/dslm4515/Musl-LFS/master/patches/musl-mlfs/change-scheduler-functions-Linux-compatib.patch"
    ptch "https://raw.githubusercontent.com/dslm4515/Musl-LFS/master/patches/musl-alpine/0001-riscv64-define-ELF_NFPREG.patch"
    ptch "https://raw.githubusercontent.com/dslm4515/Musl-LFS/master/patches/musl-alpine/handle-aux-at_base.patch
"
    ptch "https://raw.githubusercontent.com/dslm4515/Musl-LFS/master/patches/musl-alpine/syscall-cp-epoll.patch"
    curl "https://raw.githubusercontent.com/dslm4515/Musl-LFS/master/files/__stack_chk_fail_local.c" > __stack_chk_fail_local.c

    cat > ${chroot}/build/build.sh << "EOF"
#!/bin/bash
cd /build/
cp -r */* .
LDFLAGS="$LDFLAGS -Wl,-soname,libc.musl-${CARCH}.so.1" \
./configure --prefix=/usr \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --disable-gcc-wrapper

make && make  install


/tools/bin/x86_64-linux-musl-gcc -fpie -c __stack_chk_fail_local.c -o __stack_chk_fail_local.o
/tools/bin/x86_64-linux-musl-gcc-ar r libssp_nonshared.a __stack_chk_fail_local.o

cp libssp_nonshared.a /usr/lib/

export ARCH="x86_64"

ln -s /lib/ld-musl-$ARCH.so.1 /bin/ldd
EOF
    chmod +x ${chroot}/build/build.sh
    tchroot /build/build.sh
}

adjust_tools() {
    
    cat > ${chroot}/build/build.sh << "EOF"
#!/bin/bash
export TARGET="x86_64-linux-musl"
mv /tools/bin/{ld,ld-old}
mv /tools/${TARGET}/bin/{ld,ld-old}
mv /tools/bin/{ld-new,ld}
ln -s /tools/bin/ld /tools/${TARGET}/bin/ld

export SPECFILE=`dirname $(gcc -print-libgcc-file-name)`/specs
gcc -dumpspecs | sed -e 's@/tools@@g'                   \
    -e '/\*startfile_prefix_spec:/{n;s@.*@/usr/lib/ @}' \
    -e '/\*cpp:/{n;s@$@ -isystem /usr/include@}' >  tempspecfile
mv -f tempspecfile $SPECFILE &&
unset SPECFILE  TARGET

echo 'int main(){}' > dummy.c
cc dummy.c -v -Wl,--verbose > dummy.log 2>&1 
readelf -l a.out | grep ': /lib'
printf "above should be:\n\033[0;33m[Requesting program interpreter: /lib/ld-musl-x86_64.so.1]\033[0m\n"
printf "######################\n"
read wait

grep -o '/usr/lib.*/crt[1in].*succeeded' dummy.log
printf "above should be:\033[0;33m\n"
printf "/usr/lib/crt1.o succeeded\n"
printf "/usr/lib/crti.o succeeded\n"
printf "/usr/lib/crtn.o succeeded\n"
printf "\033[0m\n"
printf "######################\n"
read wait


grep -B1 '^ /usr/include' dummy.log
printf "above should be:\033[0;33m\n"
printf "#include <...> search starts here:\n"
printf "/usr/include\n"
printf "\033[0m\n"
printf "######################\n"
read wait

grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'
printf "above should be:\033[0;33m\n"
printf "SEARCH_DIR(\"=/tools/x86_64-mlfs-linux-musl/lib64\")\n"
printf "SEARCH_DIR(\"/usr/lib\")\n"
printf "SEARCH_DIR(\"/lib\")\n"
printf "SEARCH_DIR(\"=/tools/x86_64-mlfs-linux-musl/lib\")\n"
printf "\033[0m\n"
printf "######################\n"
read wait
rm dummy.c a.out dummy.log
EOF
    chmod +x ${chroot}/build/build.sh
    tchroot /build/build.sh
}

umount_chroot
rm -r ${chroot}
create_chroot
mount_chroot
export WD=${chroot}/build
clean_build
build_headers
clean_build
build_musl
clean_build
adjust_tools
clean_build

printf "${GREEN}Completed stage3\n"
