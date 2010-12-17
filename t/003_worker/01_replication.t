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

test_tcp(
    client => sub {
        my $port = shift;
        my $dbh = get_dbh();

        my $client = PrettyFS::Client->new(dbh => $dbh);
        $client->add_storage(host => '127.0.0.1', port => $port);
        note(ddf $client->list_storage);

        my $uuid;
        {
            my $fh = IO::File->new_tmpfile;
            $fh->print('OKOK');
            $fh->flush;
            $fh->seek(0, 0);

            $uuid = $client->put_file({fh => $fh});

            my @urls = $client->get_urls($uuid);

            is join(",", @urls), "http://127.0.0.1:$port/$uuid";

            my $res = Furl->new()->get($urls[0]);

            is $res->status, 200;
            is $res->content, 'OKOK';
        }

        test_tcp(
            client => sub {
                my $port_c = shift;

                my $client = PrettyFS::Client->new(dbh => $dbh);
                $client->add_storage(host => '127.0.0.1', port => $port_c);
                note(ddf $client->list_storage);

                my $rpl = PrettyFS::Worker::Replication->new({dbh => $dbh});
                $rpl->run($uuid);

                my $files = $dbh->selectall_arrayref('SELECT * FROM file WHERE uuid=?',{Slice => {}}, $uuid);

                my @urls = $client->get_urls($uuid);
                is join(",", @urls), "http://127.0.0.1:$port/$uuid,http://127.0.0.1:$port_c/$uuid";
            },
            server => sub {
                my $port_c = shift;
                $ENV{PRETTYFS_CONFIG} = 't/config.pl';
                my $app = PrettyFS::Server::Store->to_app();
                Plack::Loader->auto(port => $port_c)->run($app);
            },
        );
    },
    server => sub {
        my $port = shift;
        $ENV{PRETTYFS_CONFIG} = 't/config.pl';
        my $app = PrettyFS::Server::Store->to_app();
        Plack::Loader->auto(port => $port)->run($app);
    },
);

done_testing;

