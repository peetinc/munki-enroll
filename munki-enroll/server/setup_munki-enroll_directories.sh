#!/bin/bash

# Munki Enrollment Server - Directory Setup
# Creates required directories for munki-enroll.php v2.0.0

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Create directories
echo "Creating munki-enroll directories..."

# Create manifest directory
mkdir -p /var/munki-enroll/manifests
chown -R www-data:www-data /var/munki-enroll
chmod 755 /var/munki-enroll
chmod 755 /var/munki-enroll/manifests

# Create log directory
mkdir -p /var/log/munki-enroll
chown -R www-data:www-data /var/log/munki-enroll
chmod 755 /var/log/munki-enroll

# Create initial log files (optional)
touch /var/log/munki-enroll/munki-enroll.log
touch /var/log/munki-enroll/php_errors.log
chown www-data:www-data /var/log/munki-enroll/*.log
chmod 640 /var/log/munki-enroll/*.log