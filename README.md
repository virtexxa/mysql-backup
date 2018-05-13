mysql backup
============

This is a simple script to create local backups in
/var/backups/mysql of local databases.

It has a comfortable config file where you can
use the default values how many days a database should be kept
and at which time the backup should be executed.

Additionally you can definde different values for each database.

To backup a database, you just need to create a folder with
the name of the mysql database.

Execute the script by cron every minute

\*/1 *   * * *   root    /usr/bin/perl /var/backups/mysql/mysql-backup/db_backup_runner.pl run

for the first time run the script with:

./db_backup_runner.pl check



