use strict;
use warnings;
use Test::More;
use t::Util;
use Test::TCP;
use Plack::Loader;
use Log::Minimal;

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
        my $src = 'OKOK';
        open my $fh, '<', \$src;
        $client->put_file('hogehoge', $fh, length($src));
        my @urls = $client->get_urls('hogehoge');
        is join(",", @urls), "http://127.0.0.1:$port/hogehoge";

        my $res = Furl->new()->get($urls[0]);
        is $res->status, 200;
        is $res->content, 'OKOK';
    },
    server => sub {
        my $port = shift;
        $ENV{PRETTYFS_CONFIG} = 't/config.pl';
        my $app = PrettyFS::Server::Store->to_app();
        Plack::Loader->auto(port => $port)->run($app);
    },
);


done_testing;

