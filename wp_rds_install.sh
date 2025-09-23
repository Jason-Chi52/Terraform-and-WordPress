#!/bin/bash

# Update the system packages
yum update -y

# Install Apache web server, PHP, and MySQL connector for PHP
yum install -y httpd php php-mysqlnd

# Start and enable Apache web server
systemctl start httpd
systemctl enable httpd

# Change to the web root directory
cd /var/www/html

# Download and extract WordPress
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
mv wordpress/* .

# Clean up downloaded and extracted files
rm -rf wordpress latest.tar.gz

# Set proper ownership and permissions
chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html

# Create WordPress config file
cp wp-config-sample.php wp-config.php

# TODO: Add database configuration using the 4 variables passed in from the main.tf file