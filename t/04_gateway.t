use strict;
use warnings;
use Test::More;
use PrettyFS::Server::Gateway;
use Test::TCP 1.08;
use Plack::Runner;
use File::Temp qw/tempdir tmpnam/;
use t::Util;
use Furl;
use PrettyFS::Server::Store;
use Plack::Loader;
use PrettyFS::Worker::Replication;
use LWP::UserAgent;

my $tmp = tmpnam();

my $store1 = create_storage();
my $store2 = create_storage();

my $gateway = Test::TCP->new(
    code => sub {
        my $port = shift;
        my $dbh = DBI->connect("dbi:SQLite:dbname=$tmp", '', '');
        my $client = PrettyFS::Client->new(dbh => $dbh);
        my $g = PrettyFS::Server::Gateway->new(
            callback => sub {
                my $key = shift;
                note "callback : $key";
                my @urls = $client->get_urls($key);
                note "urls: @urls";
                return @urls;
            },
        );
        Plack::Loader->load('Twiggy', port => $port)->run($g->to_app);
    }
);

note "client: $$";
my $dbh = get_dbh("dbi:SQLite:dbname=$tmp");
my $client = PrettyFS::Client->new(dbh => $dbh);
note "setup storage";
my $content = "OK";
open my $fh, '<', \$content;
$client->add_storage(host => '127.0.0.1', port => $_->port) for $store1, $store2;
my $uuid = $client->put_file(fh => $fh, size => 2);

note sprintf("gateway: %d, store1: %d, store2: %d", $gateway->port, $store1->port, $store2->port);

note "run replication";
PrettyFS::Worker::Replication->new(dbh => $dbh)->run($uuid);

note "send request";
my $ua = LWP::UserAgent->new(timeout => 1);
for my $url ($client->get_urls($uuid)) {
    ok $url;
    my $res = $ua->get($url);
    is $res->code, 200, "request: $url";
}

subtest 'normal scenario' => sub {
    my $res = $ua->get(sprintf('http://127.0.0.1:%d/%s', $gateway->port, $uuid));
    is $res->code, 200;
    is $res->content, 'OK';
};

subtest 'not found' => sub {
    my $res = $ua->get(sprintf('http://127.0.0.1:%d/UNKNOWN', $gateway->port));
    is $res->code, 404;
};

subtest 'only alive store2' => sub {
    undef $store1;

    my $res = $ua->get(sprintf('http://127.0.0.1:%d/%s', $gateway->port, $uuid));
    is $res->code, 200;
    is $res->content, 'OK';
};

subtest 'no storage is alive' => sub {
    undef $store2;

    my $res = $ua->get(sprintf('http://127.0.0.1:%d/%s', $gateway->port, $uuid));
    is $res->code, 500;
};

done_testing;

