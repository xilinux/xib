# xib
xilinux build system

requires xibuild and xipkg to function correctly. Will build a whole "repo" of packages, or single packages if requested, using portable chroot system

## Usage

`xibd` - the xib daemon, will automatically pull and build packages

`xib package` - build a single package

`xib` - build all packages in order

### Generating all xilinux packages
1. cross compile toolchain

- start with a nice easy clean install 
- make sure you have all needed build tools on host
- create some directories, /tools, /cross-tools
- copy ./bootstrap/* to a nice clean place to begin working

- run ./bootstrap.sh stage1

- run ./bootstrap.sh stage2

- run ./bootstrap.sh stage3

- run ./bootstrap.sh package

- alternatively just run ./bootstrap.sh

2. prepare stage3 chroot

- create /var/lib/xib/chroot
- extract the created chroot-tools.tar.gz there
- ensure that you can chroot into it
- run ./build in xib
- ensure all packages build correctly
