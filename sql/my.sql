
create table bucket (
    id   int unsigned not null primary key auto_increment,
    name varchar(32),
    unique (name)
) ENGINE=InnoDB;

create table file (
    uuid       varchar(255)  not null primary key,
    bucket_id  int unsigned not null,
    size       int unsigned not null,
    ext        varchar(10)
) ENGINE=InnoDB;

create table file_on (
    file_uuid  varchar(255) not null,
    storage_id int unsigned not null,
    primary key (file_uuid, storage_id)
) ENGINE=InnoDB;

create table storage (
    id       int unsigned not null primary key auto_increment,
    host     varchar(255) binary not null,
    port     int          unsigned not null,
    status   TINYINT      UNSIGNED NOT NULL DEFAULT 1,
    disk_total int unsigned default null,
    disk_used int unsigned default null,
    unique (host, port)
) ENGINE=InnoDB;

-- Jonk

create TABLE job (
    id       int unsigned not null primary key auto_increment,
    func     text,
    arg      text,
    enqueue_time text
);

