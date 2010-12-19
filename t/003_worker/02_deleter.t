use strict;
use warnings;
use Test::More;
use t::Util;
use Test::TCP;
use Plack::Loader;
use Log::Minimal;
use IO::File;

use PrettyFS::Server::Store;
use PrettyFS::Client;
use Furl;
use PrettyFS::Worker::Replication;
use PrettyFS::Worker::Deleter;

my $storage = create_storage();

my $dbh = get_dbh();

my $client = PrettyFS::Client->new(dbh => $dbh);
$client->add_storage(host => '127.0.0.1', port => $storage->port);
note(ddf $client->list_storage);

my $uuid;
{
    my $fh = make_tmpfile("OKOK");

    $uuid = $client->put_file(fh => $fh);

    my @urls = $client->get_urls($uuid);

    is join(",", @urls), "http://127.0.0.1:@{[ $storage->port ]}/$uuid";

    my $res = Furl->new()->get($urls[0]);

    is $res->status, 200;
    is $res->content, 'OKOK';
}

my $storage2 = create_storage();
$client->add_storage(host => '127.0.0.1', port => $storage2->port);
note(ddf $client->list_storage);
run_workers($dbh);

my @storage_urls = $client->get_urls($uuid);
is join(",", sort @storage_urls), join(',', sort "http://127.0.0.1:@{[ $storage->port ]}/$uuid", "http://127.0.0.1:@{[ $storage2->port ]}/$uuid"), 'stored';

$client->delete_file($uuid);

note 'delete';
run_workers($dbh);

{
    my @urls = $client->get_urls($uuid);
    is scalar(@urls), 0;
}
for (@storage_urls) {
    my $res = Furl->new()->get($_);
    is $res->code, 404, "really removed: $_";
}

done_testing;

