use strict;
use warnings;
use Test::More;
use t::Util;
use Test::TCP 1.08;
use Plack::Loader;
use Log::Minimal;
use IO::File;

use PrettyFS::Server::Store;
use PrettyFS::Client;
use Furl;
use PrettyFS::Worker::Replication;

my $store1 = Test::TCP->new(
    code => sub {
        my $port = shift;
        $ENV{PRETTYFS_CONFIG} = 't/config.pl';
        my $app = PrettyFS::Server::Store->new->to_app();
        Plack::Loader->auto(port => $port)->run($app);
    },
);

my $client = get_client();
$client->add_storage(host => '127.0.0.1', port => $store1->port);
note(ddf $client->list_storage);

my $uuid;
{
    my $fh = IO::File->new_tmpfile;
    $fh->print('OKOK');
    $fh->flush;
    $fh->seek(0, 0);

    $uuid = $client->put_file({fh => $fh});

    my @urls = $client->get_urls($uuid);

    is join(",", @urls), "http://127.0.0.1:@{[ $store1->port ]}/$uuid";

    my $res = Furl->new()->get($urls[0]);

    is $res->status, 200;
    is $res->content, 'OKOK';
}

# create more storage server
my $store2 = Test::TCP->new(
    code => sub {
        my $port = shift;
        $ENV{PRETTYFS_CONFIG} = 't/config.pl';
        my $app = PrettyFS::Server::Store->new->to_app();
        Plack::Loader->auto(port => $port)->run($app);
    },
);
$client->add_storage(host => '127.0.0.1', port => $store2->port);
note(ddf $client->list_storage);

my $rpl = PrettyFS::Worker::Replication->new(dbh => $client->dbh);
$rpl->run($uuid);

my @urls = $client->get_urls($uuid);
is join(",", sort @urls), join(',', sort "http://127.0.0.1:@{[ $store1->port ]}/$uuid", "http://127.0.0.1:@{[ $store2->port ]}/$uuid");

for my $url (@urls) {
    my $res = Furl->new->get($url);
    is $res->code, 200;
    is $res->content, 'OKOK';
}

done_testing;

