package XibUtil;

use v5.12;

use strict;
use warnings;

use File::Basename;

sub md5_sum{
    my ($file) = @_;

    open(my $fh, "<", $file) or die "Cannot open $file: $!";
    binmode($fh);

    return Digest::MD5->new->addfile($fh)->hexdigest;
}

sub extract_from_file{
    my ($file, $regex) = @_;
    open (my $fh, "<", $file) or warn "Cannot open $file";
    while (my $line = <$fh>) {
        if ($line =~ $regex) {
            return $1;
        }
    }
}

sub is_git_repo{
    return system("git ls-remote -q @_");
}

sub extract{
    my ($file) = @_;
    my $ext = (fileparse($file, qr/\.[^.]*/))[2];
    print("$ext\n");

    my $cmd = "";
    given($ext) {
        $cmd = "tar -zxf $file" when ".gz";
        $cmd = "tar -xf $file" when ".xz";
        $cmd = "unzip $file" when ".zip";
        $cmd = "tar --lzip -xf $file" when ".lz";
        default { 
            $cmd = "tar -xf $file"; 
        }
    }

    system($cmd);
}

1;
