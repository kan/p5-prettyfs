package PrettyFS::Worker::Reaper;
use strict;
use warnings FATAL => 'all';
use utf8;
use Class::Accessor::Lite (
    new => 0,
    ro => [qw/dbh jonk limit load/],
);
use Log::Minimal;
use PrettyFS::Constants;
use Sub::Throttle qw/throttle/;

sub new {
    my $class = shift;
    my %args = @_==1 ? %{$_[0]} : @_;
    for (qw/dbh/) {
        Carp::croak("missing mandatory parameter: $_") unless exists $args{$_};
    }
    $args{jonk} ||= Jonk::Client->new($args{dbh});
    $args{load} ||= 1; # load 1 sec
    $args{limit} ||= 1000;
    bless {
        %args
    }, $class;
}

sub run {
    my ($self, $host_port) = @_;
    Carp::croak("missing host_port") unless defined $host_port;

    infof("running reaper for $host_port");

    my ($host, $port) = split ':', $host_port;

    my ($storage_id) = $self->dbh->selectrow_array(q{SELECT id FROM storage WHERE host=? AND port=? AND status=?}, {}, $host, $port, STORAGE_STATUS_DEAD);
    unless ($storage_id) {
        Carp::croak "unknown dead storage: $host $port";
    }

    my $sth = $self->dbh->prepare(q{SELECT file_uuid FROM file_on WHERE storage_id=? LIMIT } . $self->limit);
    while (1) {
        infof("running reaper: $host_port");
        throttle($self->load(), sub {
            $sth->execute($storage_id);
            while (my ($uuid) = $sth->fetchrow_array) {
                $self->jonk->enqueue(
                    'PrettyFS::Worker::Replication',
                    $uuid
                ) or Carp::croak $self->jonk->errstr;

                $self->dbh->do(q{DELETE FROM file_on WHERE file_uuid=? AND storage_id=?}, {}, $uuid, $storage_id)==1 or Carp::croak("Cannot delete row: " . $self->dbh->errstr);
            }
            $sth->finish();
        });
        last if $sth->rows == 0;
    }
}

1;

