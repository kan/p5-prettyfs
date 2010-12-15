create table file (
    file_uuid varchar(255) binary not null,
    storage_id int unsigned not null auto_increment,
    size int unsigned not null,
    primary key (file_uuid)
) ENGINE=InnoDB;

create table storage (
    storage_id int unsigned not null auto_increment,
    hostname varchar(255) binary not null,
    port     int          unsigned not null,
    primary key (storage_id)
) ENGINE=InnoDB;

