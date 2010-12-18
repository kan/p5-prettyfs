use strict;
use warnings;
use Test::More;
use t::Util;
use Test::TCP;
use PrettyFS::Server::Store;

my $store1 = create_storage();
my $client = get_client();
$client->add_storage(host => '127.0.0.1', port => $store1->port);

subtest 'get_urls' => sub {
    subtest 'normal' => sub {
        my $uuid = $client->put_file(fh => make_tmpfile("OK"));
        is join(',', $client->get_urls($uuid)), sprintf("http://127.0.0.1:%s/%s", $store1->port, $uuid);
    };
    subtest 'with ext' => sub {
        my $uuid = $client->put_file(fh => make_tmpfile("OK"), ext => 'exe');
        is join(',', $client->get_urls($uuid)), sprintf("http://127.0.0.1:%s/%s.exe", $store1->port, $uuid);
    };
    subtest 'with bucket' => sub {
        $client->add_bucket("hoge");
        my $uuid = $client->put_file(fh => make_tmpfile("OK"), bucket => 'hoge');
        is join(',', $client->get_urls($uuid)), sprintf("http://127.0.0.1:%s/hoge/%s", $store1->port, $uuid);
    };
};

done_testing;

