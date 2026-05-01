#!/bin/bash

set -ex

if [ -z "$DB_VERSION" ]; then
    echo "DB_VERSION is required"
    exit 1
fi

# Use the 2048-bit / SHA-256 cert for every DB version. Older MySQL /
# MariaDB are perfectly happy with it on the server side, and modern
# OpenSSL (>= 3.0, default security_level 2) rejects the previous 1024-bit
# SHA-1 cert with "EE certificate key too weak" during client-side verify.
sudo cp t/data/test-sha256.crt t/data/test.crt
sudo cp t/data/test-sha256.key t/data/test.key
sudo cp t/data/test-sha256.pub t/data/test.pub

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

sudo mkdir -p /var/run/mysqld
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

# MariaDB 10.5+ ships the client as `mariadb`; the `mysql` symlink was
# dropped from official images by 11.x. Pick whichever binary the image
# provides so this script works across both naming schemes.
mysql() {
    sudo docker exec mysqld sh -c \
        'exec "$(command -v mariadb || command -v mysql)" "$@"' _ "${@}"
}
for i in {1..100}
do
    sleep 3
    mysql --protocol=tcp -e 'select version()' && break
done
sudo docker logs mysqld

sudo docker cp $path/t/data/world.sql.gz mysqld:/tmp/world.sql.gz
sudo docker exec mysqld /bin/sh -c \
    'zcat /tmp/world.sql.gz | "$(command -v mariadb || command -v mysql)" -uroot'

mysql -uroot -e 'create database ngx_test;'
mysql -uroot -e 'alter database ngx_test character set utf8mb4 collate utf8mb4_unicode_ci;'
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

# MariaDB client_ed25519 (auth_ed25519 plugin, available since MariaDB
# 10.1.22). We use the explicit `USING '<base64>'` form (with a
# pre-computed public key) instead of `USING PASSWORD('plaintext')`
# because:
#   * `USING PASSWORD(...)` syntax landed only in 10.4;
#   * on 11.4 / 11.8, `USING PASSWORD('')` writes an empty
#     authentication_string (no public key) and the user can never
#     authenticate;
#   * the explicit form works on every version that ships the plugin.
#
# The two base64 strings are the Ed25519 public keys derived from
# SHA-512(password) → clamp → scalar-mult-by-base, which is the
# computation MariaDB performs internally:
#   pw="ed25519_pass" -> STIwVk/F6qiXJuOr8AgPSWVxmiN3rUjEX5DfzGAJ32A
#   pw=""             -> 4LH+dBF+G5W2CKTyId8xR3SyDqZoQjUNUVNxx8aWbG4
echo "ed25519: attempting plugin install ..."
mysql -uroot -e "install soname 'auth_ed25519'" 2>&1 || true
if mysql -uroot -BN -e "select 1 from information_schema.plugins where plugin_name='ed25519' and plugin_status='ACTIVE'" 2>/dev/null | grep -q '^1$'; then
    echo "ed25519: plugin active, creating users"
    mysql -uroot -e "create user 'ed25519_user'@'%' identified via ed25519 using 'STIwVk/F6qiXJuOr8AgPSWVxmiN3rUjEX5DfzGAJ32A'"
    mysql -uroot -e "grant all on ngx_test.* to 'ed25519_user'@'%'"
    mysql -uroot -e "create user 'ed25519_nopass'@'%' identified via ed25519 using '4LH+dBF+G5W2CKTyId8xR3SyDqZoQjUNUVNxx8aWbG4'"
    mysql -uroot -e "grant all on ngx_test.* to 'ed25519_nopass'@'%'"
else
    echo "ed25519: plugin not active on $DB_VERSION; skipping ed25519 user creation"
fi

mysql -uroot -e 'select * from information_schema.plugins where  plugin_type="AUTHENTICATION"\G';
mysql -uroot -e 'select User, plugin from mysql.user\G';

mysql -uroot -e 'grant all on world.* to "ngx_test"@"%"; flush privileges;'
