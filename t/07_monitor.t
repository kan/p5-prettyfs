use strict;
use warnings;
use Test::More;
use PrettyFS::Monitor;
use t::Util;
use PrettyFS::Constants;
use PrettyFS::DiskUsage;

my $client = get_client();
my $monitor = PrettyFS::Monitor->new(dbh => $client->dbh);

my $docroot = tempdir();
my $store = create_storage($docroot);
my $diskusage = PrettyFS::DiskUsage->new(docroot => $docroot);
$diskusage->run_once();
$client->add_storage(host => '127.0.0.1', port => $store->port);
is [grep { $_->{port} == $store->port } $client->list_storage]->[0]->{status}, STORAGE_STATUS_ALIVE;
$store->stop;
$monitor->run_once();
is [grep { $_->{port} == $store->port } $client->list_storage]->[0]->{status}, STORAGE_STATUS_DOWN;
$store->start;
$monitor->run_once();
note ddf($client->list_storage);
is [grep { $_->{port} == $store->port } $client->list_storage]->[0]->{status}, STORAGE_STATUS_ALIVE;
ok [grep { $_->{port} == $store->port } $client->list_storage]->[0]->{disk_total};
ok [grep { $_->{port} == $store->port } $client->list_storage]->[0]->{disk_used};

done_testing;

