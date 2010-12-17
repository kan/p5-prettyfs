package PrettyFS::Worker::Repair;
use strict;
use warnings;
use utf8;
use Class::Accessor::Lite (
    new => 0,
    ro => [qw/dbh jonk/],
);
use Log::Minimal;
use PrettyFS::Constants;

sub new {
    my $class = shift;
    my %args = @_==1 ? %{$_[0]} : @_;
    $args{jonk} ||= Jonk::Client->new($args{dbh});
    bless {
        %args
    }, $class;
}

sub run {
    my ($self, $host_port) = @_;

    my ($host, $port) = split ':', $host_port;

    my ($storage_id) = $self->dbh->selectrow_array(q{SELECT id FROM storage WHERE host=? AND port=? AND status=?}, {}, $host, $port, STORAGE_STATUS_DEAD);
    unless ($storage_id) {
        Carp::croak "unknown dead storage: $host $port";
    }

    my @files = $self->dbh->selectall_arrayref(q{SELECT uuid FROM file WHERE storage_id=?}, {Slice => {}}, $storage_id);
    for my $file (@files) {
        $self->jonk->enqueue(
            'PrettyFS::Worker::Replication',
            $file->{uuid}
        );
    }
}

1;

