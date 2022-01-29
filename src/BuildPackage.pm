package BuildPackage;

use strict;
use warnings;

use File::Basename;
use XibUtil qw/extract_from_file extract md5_sum/;

sub extract_source{
    return XibUtil::extract_from_file(@_, qr/^SOURCE=(.+)$/);
}

sub extract_branch{
    return XibUtil::extract_from_file(@_, qr/^BRANCH=(.+)$/);
}

sub extract_version{
    return XibUtil::extract_from_file(@_, qr/^PKG_VER=(.+)$/);
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
    my ($build_file) = @_;
   
    mkdir("$main::chroot/build");
    mkdir("$main::chroot/build/source");
    chdir("$main::chroot/build/source");

    my $source = extract_source($build_file);
    my $branch = extract_branch($build_file);
    my $PKG_VER = extract_version($build_file);

    if (XibUtil::is_git_repo($source, $branch)) {
        print("Fetching git repo $source version $PKG_VER\n");
        system("git clone $source .");
        system("git checkout $branch");

    } else {
        print("downloading file $source\n");
        my $downloaded_file = basename($source);
        system("curl $source $downloaded_file");
        extract("$downloaded_file");
        system("pwd; cp -r */* .")
    
    }

    # download source to $chroot/build/mysource.tgz
    # extract source to $chroot/build/source
}

sub build_package{
    my ($build_file) = @_;

    my $existing_version = get_built_version($build_file);
    if (defined($existing_version) && $existing_version eq md5_sum($build_file)) {
        # do not build
        print("do not build\n");
        return
    } 
    # build
    fetch_source($build_file);
    
    

}
1;
