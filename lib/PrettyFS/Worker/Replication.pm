package PrettyFS::Worker::Replication;
use strict;
use warnings;
use utf8;
use Class::Accessor::Lite (
    new => 0,
    ro => [qw/dbh furl client/],
);
use Log::Minimal;
use Furl::HTTP;
use List::Util qw/shuffle/;
use File::Temp;
use PrettyFS::Constants;
use PrettyFS::Client;
use URI;

sub new {
    my $class = shift;
    my %args = @_==1 ? %{$_[0]} : @_;
    $args{furl} ||= Furl::HTTP->new();
    for (qw/dbh/) {
        Carp::croak("missing mandatory parameter: $_") unless exists $args{$_};
    }
    my $self = bless {
        %args
    }, $class;
    $self->{client} ||= PrettyFS::Client->new(dbh => $self->dbh);
    return $self;
}

sub run {
    my ($self, $uuid, $replicate_cnt) = @_;
    $replicate_cnt ||= 2;

    my ($temp, $url) = $self->client->get_file_fh($uuid) or Carp::croak("Cannot get the content from storage");
    my $path = URI->new($url)->path;

    $replicate_cnt -= $self->dbh->selectrow_array(q{SELECT COUNT(*) FROM file INNER JOIN file_on ON (file_on.file_uuid=file.uuid) INNER JOIN storage ON (storage.id=file_on.storage_id) WHERE uuid=? AND storage.status!=?}, {}, $uuid, STORAGE_STATUS_DEAD);

    my @storage_nodes = shuffle @{$self->dbh->selectall_arrayref(q{SELECT id, host, port FROM storage WHERE status=? AND id NOT IN (SELECT storage_id FROM file_on WHERE file_uuid=?)}, {Slice => {}}, STORAGE_STATUS_ALIVE, $uuid)};
    for my $storage (@storage_nodes) {
        return if $replicate_cnt==0;
        seek $temp, 0, SEEK_SET;

        my ( $minor_version, $code, $msg, $headers, $body ) = $self->furl->request(
            method     => 'PUT',
            host       => $storage->{host},
            port       => $storage->{port},
            path_query => $path,
            content    => $temp,
        );

        if ($code == 200) {
            $self->dbh->do(
                q{INSERT INTO file_on (file_uuid, storage_id) VALUES (?,?)},
                {},
                $uuid,
                $storage->{id},
              )
              or
              Carp::croak( "Cannot insert to database: " . $self->dbh->errstr );

            infof("Replication successfully to $storage->{host}:$storage->{port}");

            $replicate_cnt--;
            return if $replicate_cnt==0;
        } else {
            next;
        }
    }
    die "Cannot replication: $uuid: $replicate_cnt";
}

1;

