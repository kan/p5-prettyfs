use strict;
use warnings;
use Test::More;
use PrettyFS::DiskUsage;
use File::Spec;
use File::Temp qw/tempdir/;
use JSON;

my $tmp = tempdir(CLEANUP => 1);
PrettyFS::DiskUsage->new(docroot => File::Spec->rel2abs($tmp))->run_once(); 
my $ufile = File::Spec->catfile($tmp, '__prettyfs_disk_usage__');
ok -f $ufile;
open my $fh, '<', $ufile or die $!;
my $content = do { local $/; <$fh> };
my $data = JSON::decode_json($content);
ok $data->{time};
close $ufile;

done_testing;

