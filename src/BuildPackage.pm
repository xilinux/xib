package BuildPackage;

use strict;
use warnings;

use File::Basename "basename";
use Digest::MD5;

sub md5_sum{
    my ($file) = @_;

    open(my $fh, "<", $file) or die "Cannot open $file: $!";
    binmode($fh);

    return Digest::MD5->new->addfile($fh)->hexdigest;
}

sub extract_ver_hash{
    my $info_file = $_;
    open (my $fh, "<", $info_file) or warn "Cannot open $info_file";
    while (my $line = <$fh>) {
        if ($line =~ /^VER_HASH=(.+)$/) {
            return $1;
        }
    }
}
sub extract_ver_hash{
    my $info_file = $_;
    open (my $fh, "<", $info_file) or warn "Cannot open $info_file";
    while (my $line = <$fh>) {
        if ($line =~ /^VER_HASH=(.+)$/) {
            return $1;
        }
    }
}

sub get_built_version{
    my ($build_file) = @_;
    my @package_split = split(/\//, $build_file);
    my $repo = $package_split[-2];
    my $name = basename($build_file, ".xibuild");
    my $dest = "$main::export/repo/$repo/$name";

    my $pkg = "$dest.xipkg";
    my $info = "$dest.xipkg.info";
    my $used_build = "$dest.xibuild";
    
    if (-e $pkg && -e $info) {
        return md5_sum($used_build);
    }
}

sub clear_build_folder{
    rmtree("$main::chroot/build");
}

sub fetch_source{
    my $source_url = $_;
   
    mkdir("$main::chroot/build")
    mkdir("$main::chroot/build/source")

    # download source to $chroot/build/mysource.tgz
    # extract source to $chroot/build/source
}

sub build_package{
    my ($build_file) = @_;

    $existing_version = get_built_version($build_file);
    if (defined($existing_version) && $existing_version eq md5_sum($build_file)) {
        # do not build
        return
    } 
    # build
    

}
