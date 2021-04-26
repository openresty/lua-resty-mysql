#!/bin/bash

set -ex

if [ -z "$DB_VERSION" ]; then
    echo "DB_VERSION is required"
    exit 1
fi

if [ "$DB_VERSION" = 'mysql:8.0' ] || [ "$DB_VERSION" = 'mariadb:10.3' ]; then
    sudo cp t/data/test-sha256.crt t/data/test.crt
    sudo cp t/data/test-sha256.key t/data/test.key
else
    sudo cp t/data/test-sha1.crt t/data/test.crt
    sudo cp t/data/test-sha1.key t/data/test.key
    sudo cp t/data/test-sha1.pub t/data/test.pub
fi

cat << EOF >mysqld.cnf
[mysqld]
ssl-ca=/etc/mysql/ssl/test.crt
ssl-cert=/etc/mysql/ssl/test.crt
ssl-key=/etc/mysql/ssl/test.key
socket=/var/run/mysqld/mysqld.sock
EOF

if [ "$DB_VERSION" != 'mysql:8.0' ] && [ "$DB_VERSION" != 'mysql:5.7' ]; then
cat << EOF >>mysqld.cnf
secure-auth=0
EOF
fi

if [ "$DB_VERSION" = 'mysql:5.6' ]; then
cat << EOF >>mysqld.cnf
sha256_password_private_key_path=/etc/mysql/ssl/test.key
sha256_password_public_key_path=/etc/mysql/ssl/test.pub
EOF
fi

cat << EOF >>mysqld.cnf

[client]
socket=/var/run/mysqld/mysqld.sock
EOF

path=`pwd`
container_name=mysqld

if [ "$(sudo docker ps -a --filter "name=^/$container_name$" --format '{{.Names}}')" = "$container_name" ]; then
    sudo docker stop "$container_name"
    sudo docker rm "$container_name"
fi

sudo chmod -R 777 /var/run/mysqld
sudo docker pull "${DB_VERSION}"
sudo docker run \
    -itd \
    --privileged \
    --name="$container_name" \
    --pid=host \
    --net=host \
    --ipc=host \
    -e MYSQL_ALLOW_EMPTY_PASSWORD=yes \
    -e MYSQL_TCP_PORT="${TEST_NGINX_MYSQL_PORT:-3306}" \
    --volume=/var/run/mysqld:/var/run/mysqld \
    --volume="$path/mysqld.cnf":/etc/mysql/conf.d/mysqld.cnf \
    --volume="$path/t/data/test.crt":/etc/mysql/ssl/test.crt \
    --volume="$path/t/data/test.key":/etc/mysql/ssl/test.key \
    --volume="$path/t/data/test.pub":/etc/mysql/ssl/test.pub \
    ${DB_VERSION}

mysql() {
    sudo docker exec mysqld mysql "${@}"
}
for i in {1..100}
do
    sleep 3
    mysql --protocol=tcp -e 'select version()' && break
done
sudo docker logs mysqld

if [ ! -d download-cache ]; then mkdir download-cache; fi
if [ ! -f download-cache/world.sql.gz ] || [ ! -s download-cache/world.sql.gz ]; then
    curl -SsLo download-cache/world.sql.gz https://downloads.mysql.com/docs/world.sql.gz
fi
sudo docker cp download-cache/world.sql.gz mysqld:/tmp/world.sql.gz
sudo docker exec mysqld /bin/sh -c "zcat /tmp/world.sql.gz | mysql -uroot"

mysql -uroot -e 'create database ngx_test;'
mysql -uroot -e 'create user "ngx_test"@"%" identified by "ngx_test";'
mysql -uroot -e 'grant all on ngx_test.* to "ngx_test"@"%";'

if [ "$DB_VERSION" = 'mysql:8.0' -o "$DB_VERSION" = 'mysql:5.7' ]; then # sha256_password, mysql_native_password
    mysql -uroot -e 'create user "user_sha256"@"%" identified with "sha256_password" by "pass_sha256";'
    mysql -uroot -e 'grant all on ngx_test.* to "user_sha256"@"%";'
    mysql -uroot -e 'create user "nopass_sha256"@"%" identified with "sha256_password";'
    mysql -uroot -e 'grant all on ngx_test.* to "nopass_sha256"@"%";'

    if [ "$DB_VERSION" != 'mysql:5.7' ]; then # mysql:8.0 caching_sha2_password
        mysql -uroot -e 'create user "user_caching_sha2"@"%" identified with "caching_sha2_password" by "pass_caching_sha2";'
        mysql -uroot -e 'grant all on ngx_test.* to "user_caching_sha2"@"%";'
        mysql -uroot -e 'create user "nopass_caching_sha2"@"%" identified with "caching_sha2_password";'
        mysql -uroot -e 'grant all on ngx_test.* to "nopass_caching_sha2"@"%";'
    fi

    mysql -uroot -e 'create user "user_native"@"%" identified with "mysql_native_password" by "pass_native";'
else # other: mysql_native_password, mysql_old_password
    if [ "$DB_VERSION" = 'mysql:5.6' ]; then # mysql:5.6 sha256_password
        mysql -uroot -e 'create user "user_sha256"@"%" identified with "sha256_password";'
        mysql -uroot -e 'set old_passwords = 2;set password for "user_sha256"@"%" = PASSWORD("pass_sha256");'
        mysql -uroot -e 'grant all on ngx_test.* to "user_sha256"@"%";'
        mysql -uroot -e 'create user "nopass_sha256"@"%" identified with "sha256_password";'
        mysql -uroot -e 'grant all on ngx_test.* to "nopass_sha256"@"%";'
    fi

    mysql -uroot -e 'create user "user_old"@"%" identified with mysql_old_password;'
    mysql -uroot -e 'set old_passwords = 1;set password for "user_old"@"%" = PASSWORD("pass_old");'
    mysql -uroot -e 'grant all on ngx_test.* to "user_old"@"%";'
    mysql -uroot -e 'create user "nopass_old"@"%" identified with mysql_old_password;'
    mysql -uroot -e 'set password for "nopass_old"@"%" = "";'
    mysql -uroot -e 'grant all on ngx_test.* to "nopass_old"@"%";'

    mysql -uroot -e 'create user "user_native"@"%" identified with mysql_native_password;'
    mysql -uroot -e 'set old_passwords = 0;set password for "user_native"@"%" = PASSWORD("pass_native");'
fi

mysql -uroot -e 'grant all on ngx_test.* to "user_native"@"%";'
mysql -uroot -e 'create user "nopass_native"@"%" identified with mysql_native_password;'
mysql -uroot -e 'grant all on ngx_test.* to "nopass_native"@"%";'

mysql -uroot -e 'select * from information_schema.plugins where  plugin_type="AUTHENTICATION"\G';
mysql -uroot -e 'select User, plugin from mysql.user\G';

mysql -uroot -e 'grant all on world.* to "ngx_test"@"%"; flush privileges;'
