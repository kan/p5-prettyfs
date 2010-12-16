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

test_tcp(
    client => sub {
        my $port = shift;
        my $dbh = get_dbh();

        my $client = PrettyFS::Client->new(dbh => $dbh);
        $client->add_storage(host => '127.0.0.1', port => $port);
        note(ddf $client->list_storage);

        subtest 'normal use' => sub {
            my $fh = IO::File->new_tmpfile;
            $fh->print('OKOK');
            $fh->flush;
            $fh->seek(0, 0);

            my $uuid = $client->put_file($fh);

            my @urls = $client->get_urls($uuid);

            is join(",", @urls), "http://127.0.0.1:$port/$uuid";

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

            my $uuid = $client->put_file($fh, {bucket => 'nekokak'});

            my @urls = $client->get_urls($uuid, {bucket => 'nekokak'});

            is join(",", @urls), "http://127.0.0.1:$port/nekokak/$uuid";

            my $res = Furl->new()->get($urls[0]);

            is $res->status, 200;
            is $res->content, 'MEME';
        };
    },
    server => sub {
        my $port = shift;
        $ENV{PRETTYFS_CONFIG} = 't/config.pl';
        my $app = PrettyFS::Server::Store->to_app();
        Plack::Loader->auto(port => $port)->run($app);
    },
);


done_testing;

