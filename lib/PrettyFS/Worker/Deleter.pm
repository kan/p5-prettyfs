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
    for (qw/dbh/) {
        Carp::croak("missing mandatory parameter: $_") unless exists $args{$_};
    }
    bless {
        %args
    }, $class;
}

sub run {
    my ($self, $uuid) = @_;

    my ($ext, $bucket_id) = $self->dbh->selectrow_array('SELECT ext, bucket_id FROM file WHERE uuid=?',{Slice => {}}, $uuid);

    my $bucket_name;
    if (defined $bucket_id) {
        ($bucket_name) = $self->dbh->selectrow_array(q{SELECT bucket.name FROM bucket WHERE id=?}, {}, $bucket_id);
        unless ($bucket_name) {
            critf("Cannot retrieve bucket. uuid: $uuid");
        }
    }
    my $path  = $bucket_name ? "/$bucket_name/$uuid" : "/$uuid";
       $path .= ".${ext}" if defined $ext;

    my @storage_ids = map { $_->[0] } @{$self->dbh->selectall_arrayref(q{SELECT storage_id FROM file_on WHERE file_uuid=?}, {}, $uuid)};
    for my $storage_id (@storage_ids) {
        my ($host, $port, $status) = $self->dbh->selectrow_array(q{SELECT storage.host, storage.port, storage.status FROM storage WHERE id=?}, {}, $storage_id);
        Carp::croak "Cannot retrieve storage information" unless $host && $port;
        unless ($status == STORAGE_STATUS_ALIVE) {
            critf("Cannot retrieve source. Because the node is currently unavailable.");
            next;
        }

        infof("remove data from http://$host:$port$path");
        my ($minor_version, $code, $msg, $headers, $body) = $self->furl->request(
            method     => 'DELETE',
            host       => $host,
            port       => $port,
            path_query => $path,
        );
        unless ($code == 200) {
            # update storage status?
        }

        if ($code == 200) {
            $self->dbh->do(q{DELETE FROM file_on WHERE file_uuid=? AND storage_id=?}, {}, $uuid, $storage_id)
                        or Carp::croak("Cannot insert to database: " . $self->dbh->errstr);
            infof("Deleter successfully. $host:$port uuid:$uuid");
        }
    }
}

1;

