#!/usr/bin/env perl

# TODO for building the whole system
# We first need to have a base system that we can build from
#   (up to chapter 6 in lfs book, done by make_tools.sh)
# packages need to be build in order of importance
# need to some how find out which packages are the most important and build and install them to the chroot first
# build a package, install it if necessary
# copy the generated package/info to a safe place
# sign the package
# put the package in the export folder

# TODO for building a single package:
# do all the preliminary checks (exists, deps are installed, etc)
# download source to $chroot/source
# download additional tools 
# copy xibuild to the chroot
# create a "build.sh" script in the chroot
# - run the 3 stages of package building
# - create the pacakage in $chroot/$name.xipkg
# - add some info to package info
# - if requested, install to the chroot

use strict;
use warnings;
use Getopt::Long "HelpMessage";

our $BUILDFILES_REPO = "https://xi.davidovski.xyz/git/buildfiles.git";

GetOptions(
        "chroot:s" => \(our $chroot = "/var/xilinux/chroot"),
        "buildfiles" => \(our $buildfiles = "/var/xilinux/buildfiles"),
        "export:s" => \(our $export = "/var/xilinux/export"),
) or HelpMessage(1);

sub prepare_xib_environment{
    die "chroot environment at $chroot doesn't yet exist\n" unless ( -e $chroot);
    
    if (!-d $export) {
        mkdir($export);
    }

    pull_buildfiles();
}

sub pull_buildfiles{
    if (-d $buildfiles) {
        system("cd $buildfiles && git pull");
    } else {
        system("git clone $BUILDFILES_REPO $buildfiles");
    }
    list_buildfiles();
} 

sub list_buildfiles{
    my @files = glob("$buildfiles/repo/*/*.xibuild");
    foreach (@files) {
        print("$_\n");
    }
}

unless (caller) {
    prepare_xib_environment();
}
