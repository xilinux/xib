package BuildOrder;
# tools for determining which order to build packages 

use strict;
use warnings;

use File::Basename "basename";
use Sort::TSort "tsort";

sub list_dependencies{
    my $file = $_;
    my @deps = ();

    open (my $fh, "<", $file) or warn "Cannot open $file";

    while (my $line = <$fh>) {
        if ($line =~ /DEPS=\((.+)\)/) {
            my @words = split(/ /, $1);
            push(@deps, @words);
        }
    }

    return @deps;
}

sub list_buildfiles{
    my @files = glob("$main::buildfiles/repo/*/*.xibuild");
    # ignore any meta packages during this stage, they can be added later
    return grep(!/\/meta\//, @files);
}

sub list_meta_pkgs{
    return map({basename($_, ".xibuild")} glob("$main::buildfiles/repo/meta/*.xibuild"));
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
    my ($file) = @_;
    my %pkgs = get_packages();

    my @edges = get_edges(%pkgs);

    my @install = get_depended_on(@edges);

    # use tsort to determine the build order
    my @sorted = reverse(@{tsort(\@edges)});

    my @meta = list_meta_pkgs();
    push(@sorted, @meta);

    open (my $fh, ">", $file) or die "Cannot open $file";

    foreach(@sorted) {
        my $pkg = $_;
        print($fh "$pkg");
        print($fh "+") if (grep(/^$pkg/, @install));
        print($fh "\n");
    }

    return $file;
}

1;
