use strict;
use warnings;
use utf8;

package PrettyFS::Monitor;
use Class::Accessor::Lite (ro => [qw/sth dbh interval client/]);
use PrettyFS::Client;
use Log::Minimal;

sub new {
    my $class = shift;
    my %args = @_==1 ? %{$_[0]} : @_;
    for (qw/dbh/) {
        Carp::croak("missing mandatory parameter: $_") unless exists $args{$_};
    }
    $args{interval} ||= 10;
    my $self = bless {%args}, $class;
    my $sth = $self->dbh->prepare(q{SELECT host, port, status FROM storage}) or die $self->dbh->errstr;
    $self->{client} ||= PrettyFS::Client->new(dbh => $self->dbh);
    $self->{sth} = $sth;
    return $self;
}

sub run {
    my $self = shift;

    while (1) {
        $self->run_once();

        sleep $self->interval;
    }
}

sub run_once {
    my $self = shift;

    $self->sth->execute;
    while (my ($host, $port, $status) = $self->sth->fetchrow_array()) {
        infof("request to $host:$port($status)");

        $self->client->update_storage_status(
            host           => $host,
            port           => $port,
            current_status => $status
        );
    }
}

1;
__END__

=head1 DESCRIPTION

PrettyFS::Monitor monitors storage nodes. It records to the database.

