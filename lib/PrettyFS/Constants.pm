package PrettyFS::Constants;
use strict;
use warnings;
use utf8;

my %code;

BEGIN {
    my $i = 0;
    %code = (
        map { $_ => $i++ } qw/STORAGE_STATUS_ALIVE STORAGE_STATUS_DEAD STORAGE_STATUS_DOWN/
    );
}

use parent qw/Exporter/;
use constant \%code;

our @EXPORT = keys %code;

1;

