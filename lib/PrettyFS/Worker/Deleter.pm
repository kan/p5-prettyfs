package PrettyFS::Worker::Deleter;
use strict;
use warnings;
use utf8;
use Class::Accessor::Lite (
    new => 0,
    ro => [qw/dbh furl/],
);
use Log::Minimal;
use Furl::HTTP;
use PrettyFS::Constants;

sub new {
    my $class = shift;
    my %args = @_==1 ? %{$_[0]} : @_;
    $args{furl} ||= Furl::HTTP->new();
    bless {
        %args
    }, $class;
}

sub run {
    my ($self, $uuid) = @_;

    my $files = $self->dbh->selectall_arrayref('SELECT * FROM file WHERE uuid=?',{Slice => {}}, $uuid);

    my $bucket_name;
    if ($files->[0]->{bucket_id}) {
        ($bucket_name) = $self->dbh->selectrow_array(q{SELECT bucket.name FROM bucket WHERE id=?}, {}, $files->[0]->{bucket_id});
        unless ($bucket_name) {
            critf("Cannot retrieve bucket. uuid: $uuid");
        }
    }
    my $path  = $bucket_name ? "/$bucket_name/$uuid" : "/$uuid";
       $path .= ".$files->[0]->{ext}" if $files->[0]->{ext};

    for my $file (@$files) {
        my ($host, $port, $status) = $self->dbh->selectrow_array(q{SELECT storage.host, storage.port, storage.status FROM storage WHERE id=?}, {}, $file->{storage_id});
        Carp::croak "Cannot retrieve storage information" unless $host && $port;
        unless ($status == STORAGE_STATUS_ALIVE) {
            critf("Cannot retrieve source. Because the node is currently unavailable.");
            next;
        }

        my ($minor_version, $code, $msg, $headers, $body) = $self->furl->request(
            method     => 'DELETE',
            path_query => $path,
            port       => $port,
            host       => $host,
        );
        unless ($code == 200) {
            # update storage status?
        }

        $self->dbh->do(q{DELETE FROM file WHERE uuid=? AND storage_id=?}, {}, $uuid, $file->{storage_id})
                    or Carp::croak("Cannot insert to database: " . $self->dbh->errstr);
        infof("Deleter successfully. $host:$port uuid:$uuid");
    }
}

1;

