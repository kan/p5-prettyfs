
create table bucket (
    id   integer not null primary key,
    name varchar(32),
    unique(name)
);

create table file (
    uuid       varchar(255) not null,
    storage_id int unsigned not null,
    bucket_id  int unsigned,
    size       int unsigned not null,
    ext        varchar(10),
    del_fg     tinyint unsigned not null default 0,
    primary key (uuid, storage_id)
);

create table storage (
    id       integer not null,
    host     varchar(255) not null,
    port     int          unsigned not null,
    status   tinyint     unsigned not null default 1,
    primary key (id),
    unique (host, port)
);

