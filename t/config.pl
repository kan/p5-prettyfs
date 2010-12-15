#!/usr/bin/perl
use File::Temp qw/tempdir/;
+{
    DB => ['dbi:SQLite:', '', ''],
    base => tempdir(CLEANUP => 1),
};
