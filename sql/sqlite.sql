
create table bucket (
    id   integer not null primary key,
    name varchar(32),
    unique(name)
);

create table file (
    uuid       varchar(255) not null,
    bucket_id  int unsigned,
    size       int unsigned not null,
    ext        varchar(10),
    primary key (uuid)
);

create table file_on (
    file_uuid  varchar(255) not null,
    storage_id int unsigned not null,
    primary key (file_uuid, storage_id)
);

create table storage (
    id       integer not null,
    host     varchar(255) not null,
    port     int          unsigned not null,
    status   tinyint     unsigned not null default 1,
    disk_total int unsigned default null,
    disk_used  int unsigned default null,
    primary key (id),
    unique (host, port)
);

-- Jonk

CREATE TABLE job (
    id           INTEGER PRIMARY KEY ,
    func         text,
    arg          text,
    enqueue_time text
);

