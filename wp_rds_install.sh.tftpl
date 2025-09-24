#!/bin/bash
set -e
yum update -y
yum install -y httpd php php-mysqlnd wget tar
systemctl start httpd
systemctl enable httpd

cd /var/www/html
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
mv wordpress/* .
rm -rf wordpress latest.tar.gz

chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html

cp wp-config-sample.php wp-config.php
sed -i "s/database_name_here/${DB_NAME}/" wp-config.php
sed -i "s/username_here/${DB_USER}/" wp-config.php
sed -i "s/password_here/${DB_PASSWORD}/" wp-config.php
sed -i "s/localhost/${DB_HOST}/" wp-config.php

echo "OK" > /var/www/html/health.txt
systemctl restart httpd
