use strict;
use warnings;
use utf8;

package PrettyFS::ConfigLoader;

sub load {
    my ($class, $conf) = @_;
    die "Missing configuration file: $conf" unless -f $conf;
    do $conf or die "Cannot load configuration file: $conf: $@";
}

1;

