use strict;
use warnings;
use Test::More;
use PrettyFS::Worker::Reaper;
use PrettyFS::Worker::Replication;
use t::Util;
use PrettyFS::Constants;
use Log::Minimal;

my $storage1 = create_storage(); # will dead
my $storage2 = create_storage();
my $storage3 = create_storage();

my $client = get_client();
$client->add_storage(host => '127.0.0.1', port => $storage1->port);
$client->add_storage(host => '127.0.0.1', port => $storage2->port);
for (1..10) {
    my $uuid = $client->put_file(fh => make_tmpfile("HOGE"));
}
run_workers($client->dbh); # run replications

my $s3_cnt = $client->dbh->selectrow_array(q{SELECT COUNT(*) FROM file INNER JOIN storage ON (storage.id=file.storage_id) WHERE storage.port=?}, {}, $storage3->port);

$client->edit_storage_status(host => '127.0.0.1', port => $storage1->port, status => STORAGE_STATUS_DEAD);
$client->add_storage(host => '127.0.0.1', port => $storage3->port);

run_workers($client->dbh); # run replications

my $s3_cnt2 = $client->dbh->selectrow_array(q{SELECT COUNT(*) FROM file INNER JOIN storage ON (storage.id=file.storage_id) WHERE storage.port=?}, {}, $storage3->port);

cmp_ok $s3_cnt, '<', $s3_cnt2;

done_testing;

use Jonk::Worker;
sub run_workers {
    my $dbh = shift;
    my @workers = qw/PrettyFS::Worker::Reaper PrettyFS::Worker::Replication/;

    my $fetcher = Jonk::Worker->new($client->dbh, {functions => \@workers});
    my %workers = map { $_ => $_->new(dbh => $dbh) } @workers;
    while (my $job = $fetcher->dequeue()) {
        debugf("run $job");
        my $worker = $workers{$job->{func}};
        $worker->run($job->{arg});
        # PrettyFS::Worker::Reaper->new(dbh => $client->dbh)->run('127.0.0.1:' . $storage1->port);
    }
}

