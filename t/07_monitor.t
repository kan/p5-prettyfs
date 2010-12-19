use strict;
use warnings;
use Test::More;
use PrettyFS::Monitor;
use t::Util;
use PrettyFS::Constants;

my $client = get_client();
my $monitor = PrettyFS::Monitor->new(dbh => $client->dbh);

my $store = create_storage();
$client->add_storage(host => '127.0.0.1', port => $store->port);
is [grep { $_->{port} == $store->port } $client->list_storage]->[0]->{status}, STORAGE_STATUS_ALIVE;
$store->stop;
$monitor->run_once();
is [grep { $_->{port} == $store->port } $client->list_storage]->[0]->{status}, STORAGE_STATUS_DOWN;
$store->start;
$monitor->run_once();
is [grep { $_->{port} == $store->port } $client->list_storage]->[0]->{status}, STORAGE_STATUS_ALIVE;

done_testing;

