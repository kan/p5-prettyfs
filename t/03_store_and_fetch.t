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

my $storage = create_storage();

my $dbh = get_dbh();

my $client = PrettyFS::Client->new(dbh => $dbh);
$client->add_storage(host => '127.0.0.1', port => $storage->port);
note(ddf $client->list_storage);

subtest 'normal use' => sub {
    my $fh = IO::File->new_tmpfile;
    $fh->print('OKOK');
    $fh->flush;
    $fh->seek(0, 0);

    my $uuid = $client->put_file({fh => $fh});

    my @urls = $client->get_urls($uuid);

    is join(",", @urls), "http://127.0.0.1:@{[ $storage->port ]}/$uuid";

    my $res = Furl->new()->get($urls[0]);

    is $res->status, 200;
    is $res->content, 'OKOK';
};
subtest 'bucket use' => sub {
    $client->add_bucket('nekokak');

    my $fh = IO::File->new_tmpfile;
    $fh->print('MEME');
    $fh->flush;
    $fh->seek(0, 0);

    my $uuid = $client->put_file({fh => $fh, bucket => 'nekokak'});

    my @urls = $client->get_urls($uuid);

    is join(",", @urls), "http://127.0.0.1:@{[ $storage->port ]}/nekokak/$uuid";

    my $res = Furl->new()->get($urls[0]);

    is $res->status, 200;
    is $res->content, 'MEME';
};
subtest 'specific ext' => sub {
    my $fh = IO::File->new_tmpfile;
    $fh->print('EXT');
    $fh->flush;
    $fh->seek(0, 0);

    my $uuid = $client->put_file({fh => $fh, ext => 'txt'});

    my @urls = $client->get_urls($uuid);

    is join(",", @urls), "http://127.0.0.1:@{[ $storage->port ]}/${uuid}.txt";

    my $res = Furl->new()->get($urls[0]);

    is $res->status, 200;
    is $res->content, 'EXT';
};


done_testing;

