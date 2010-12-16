
create table bucket (
    id   int unsigned not null primary key auto_increment,
    name varchar(32) unique
) ENGINE=InnoDB;

create table file (
    uuid       varchar(255)  not null primary key,
    storage_id int unsigned not null,
    bucket_id  int unsinged not null,
    size       int unsigned not null
) ENGINE=InnoDB;

create table storage (
    id       int unsigned not null primary key auto_increment,
    hostname varchar(255) binary not null,
    port     int          unsigned not null,
    status   TINYTINT     UNSIGNED NOT NULL DEFAULT 1,
    unique (hostname, port)
) ENGINE=InnoDB;

