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

use Env;
use File::Basename;
use lib dirname (__FILE__);
use Sort::TSort "tsort";

our $buildfiles = $ENV{XIB_BUILDFILES};

sub list_dependencies{
    my $file = $_;
    my @deps = ();

    open (my $fh, "<", $file) or warn "Cannot open $file";

    while (my $line = <$fh>) {
        if ($line =~ /DEPS="(.+)"/) {
            my @words = split(/ /, $1);
            push(@deps, @words);
        }
    }

    return @deps;
}

sub list_buildfiles{
    my @files = glob("$buildfiles/repo/*/*.xibuild");
    # ignore any meta packages during this stage, they can be added later
    @files = grep(!/\/meta\//, @files);
    @files = grep(!/\/skip\//, @files);

    return @files
}

sub list_meta_pkgs{
    return map({basename($_, ".xibuild")} glob("$buildfiles/repo/meta/*.xibuild"));
}

sub get_packages{
    my %pkgs = ();
    
    my @files = list_buildfiles();

    foreach (@files) {
        my $pkg_file = $_;
        my $pkg_name = basename($pkg_file, ".xibuild");

        my @deps = list_dependencies($pkg_file);
        $pkgs{$pkg_name} = \@deps;
    }

    return %pkgs;
}

# Get a list of all the edges 
sub get_edges{
    my %pkgs = @_;

    my @edges = ();
    foreach (keys(%pkgs)) {
        my $pkg = $_;
        my @deps = @{$pkgs{$_}};
        foreach (@deps) {
            my $dep = $_;

            my @edge = ($pkg, $dep);
            push @edges, [ @edge ];

        }
    }
    return @edges;
}

# Determine which packages are depended on
sub get_depended_on{
    my @edges = @_;

    my %install = ();
    foreach (@edges) {
        my @edge = @{$_};
        $install{$edge[1]} = $edge[0];
    }
    
    return keys(%install);
}

sub determine_build_order{
    my %pkgs = get_packages();

    my @edges = get_edges(%pkgs);

    my @install = get_depended_on(@edges);

    # use tsort to determine the build order
    my @sorted = reverse(@{tsort(\@edges)});

    my @meta = list_meta_pkgs();
    push(@sorted, @meta);

    foreach(@sorted) {
        my $pkg = $_;
        print("$pkg");
        print("+") if (grep(/^$pkg/, @install));
        print("\n");
    }
}

unless (caller) {
    determine_build_order();
}
