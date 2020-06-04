#!/bin/bash

set -ex

cat << EOF >mysqld.cnf
[mysqld]
ssl-ca=/etc/mysql/ssl/test.crt
ssl-cert=/etc/mysql/ssl/test.crt
ssl-key=/etc/mysql/ssl/test.key
socket=/var/run/mysqld/mysqld.sock

[client]
socket=/var/run/mysqld/mysqld.sock
EOF

path=`pwd`

sudo chmod -R 777 /var/run/mysqld
sudo docker pull ${DB_VERSION}
sudo docker run \
    -itd \
    --privileged \
    --name=mysqld \
    --pid=host \
    --net=host \
    --ipc=host \
    -e MYSQL_ALLOW_EMPTY_PASSWORD=yes \
    --volume=/var/run/mysqld:/var/run/mysqld \
    --volume=$path/mysqld.cnf:/etc/mysql/conf.d/mysqld.cnf \
    --volume=$path/t/data/test.crt:/etc/mysql/ssl/test.crt \
    --volume=$path/t/data/test.key:/etc/mysql/ssl/test.key \
    ${DB_VERSION}

mysql() {
    docker exec mysqld mysql "${@}"
}
while :
do
    sleep 3
    mysql --protocol=tcp -e 'select version()' && break
done
docker logs mysqld

if [ ! -d download-cache ]; then mkdir download-cache; fi
if [ ! -f download-cache/world.sql.gz ]; then wget -O download-cache/world.sql.gz http://downloads.mysql.com/docs/world.sql.gz; fi
docker cp download-cache/world.sql.gz mysqld:/tmp/world.sql.gz
docker exec mysqld /bin/sh -c "zcat /tmp/world.sql.gz | mysql -uroot"

mysql -uroot -e 'create database ngx_test;'
mysql -uroot -e 'create user "ngx_test"@"%" identified by "ngx_test";'
mysql -uroot -e 'grant all on ngx_test.* to "ngx_test"@"%";'
mysql -uroot -e 'grant all on world.* to "ngx_test"@"%"; flush privileges;'
