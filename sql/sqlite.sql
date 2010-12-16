
create table file (
    file_uuid varchar(255) not null,
    storage_id int unsigned not null,
    size int unsigned not null,
    primary key (file_uuid)
);

create table storage (
    storage_id integer not null,
    host     varchar(255) not null,
    port     int          unsigned not null,
    status   TINYTINT     UNSIGNED NOT NULL DEFAULT 1,
    primary key (storage_id),
    unique (host, port)
);

