use strict;
use warnings;
use Test::More;
use DBI;
use PrettyFS::Client;
use Jonk::Client;
use t::Util;

my $dbh = get_dbh();
my $jonk = Jonk::Client->new($dbh);
my $pf = PrettyFS::Client->new(dbh => $dbh, jonk => $jonk);
$pf->add_storage(host => '127.0.0.1', port => 4649);
$pf->add_storage(host => '127.0.0.1', port => 5963);
is(
    join("\n", map { $_->{host} .':'. $_->{port} } sort { $a->{port} <=> $b->{port} } $pf->list_storage()),
    "127.0.0.1:4649\n127.0.0.1:5963"
);
$pf->delete_storage(host => '127.0.0.1', port => 5963);
is(
    join("\n", map { $_->{host} .':'. $_->{port} } sort { $a->{port} <=> $b->{port} } $pf->list_storage()),
    "127.0.0.1:4649"
);

done_testing;

