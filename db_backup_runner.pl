#!/usr/bin/perl
 
use strict;
 
# Database Backupper (c) Bernd Hilmar 2017-03-31 // Virtexxa SRL Romania.
#
# This script creates backups of a database. You dont need to configure something special,
# just in case you want to keep backups not in the default value. 
# 
# IMPORTANT: a backup is made automatically, if the directory /var/backups/mysql/$databasename exists.
# The database must be accessible via root and with no password as root and must have the same name as the directory.
# You can disable backups for specific databases by moving them into the folder "_disabled". 
# The folder _disabled is ignored.
# This script must run as root.
 
sub _config {
 
	my %conf = ( 
 
		# root path
		'root_path'	=> '/var/backups/mysql',
		'myscriptname'	=> 'db_backup_runner.pl',
 
		# system programs
		'mysqldump'	=> '/usr/bin/mysqldump',
		'gzip'		=> '/bin/gzip',
		'rm'		=> '/bin/rm',
		'df'		=> '/bin/df',
		'mount'		=> 'sda1',
 
		# how long to keep backups // each database who should be backed up must be defined here
		'keep_days'	=> {
			'default'       => 3,
			'wordpress'	=> 5, # directory must exist
			#'databasename2'	=> 2, # directory must exist
			# for other database values you need to write the name of the database as key and the value in days
		},
	);
 
 
	return(\%conf);
 
}
 
my ($arg) = @ARGV;
 
if(!$arg) {
        print "\nCall This script with the argument 'check' or 'run'\n\n";
        print "- check   All databases for backups are listed.\n";
        print "          Also backups to delete will be listed.\n";
        print "          Nothing is executed.\n\n";
        print "-run      The sript runs in live-mode\n";
        print "          it creates backups and deletes old backups\n\n";
        print "To backup a specific database create a directory with the exact name\n";
        print "of the database in the mysql server. You do not need to configure anything else\n";
        print "as long as you use the default values. But you can use different days to keep\n";
        print "backups. In this case configure in the _config section under 'keep_days'\n";
        print "how many days you want to keep a backup for a specific database.\n\n";
        print "To disable a backup create the folder '_disabled' and move the database\n";
        print "folder into this directory. The database is skipped, even a configuration\n";
        print "in \$conf->{'keep_days'} exists\n\n";
        exit;
}
 
if($arg ne "run" && $arg ne "check") {
        print "Valid arguments are 'check' or 'run'\n";
        print "For more information execute the script without argument\n";
        print "Aborted.\n";
        exit;
}
 
my $backup = create_backups(_config());
print "\n";
my $remove_old_backups = delete_backups(_config());
 
sub create_backups {
 
	my $conf = shift;
 
	opendir(DIR, "$conf->{'root_path'}");
	my @dbs = readdir(DIR);
	closedir(DIR);
 
	foreach my $db (@dbs) {
		next if($db eq "." || $db eq ".." || $db eq "$conf->{'myscriptname'}" || $db eq "_disabled" || eq "sbin");
 
		#print $db ."\n";
		my $filedate = _convert_unixtime_to_date();
		my $result = qx~$conf->{'mysqldump'} -u root $db > $conf->{'root_path'}/$db/db_backup.$filedate.sql 2>&1~ if($arg eq "run");
		next if($result =~ /Got error: 1049/);
		qx~$conf->{'gzip'} $conf->{'root_path'}/$db/db_backup.$filedate.sql~ if($arg eq "run");
		if($arg eq "check") {
		 	 print "Backup /$db/db_backup.$filedate.sql will be created.\n";
		}		
		if($arg eq "run") {
			print "Backup created: $db/db_backup.$filedate.sql\n";
		}
	}
}
 
sub delete_backups {
 
	my $conf = shift;
 
	opendir(DIR, "$conf->{'root_path'}");
        my @dbs = readdir(DIR);
        closedir(DIR);
 
	foreach my $db (@dbs) {
		next if($db eq "." || $db eq ".." || $db eq "$conf->{'myscriptname'}" || $db eq "_disabled");
 
		my $keep_days = $conf->{'keep_days'}->{'default'};
		$keep_days = $conf->{'keep_days'}->{$db} if($conf->{'keep_days'}->{$db});
 
		my @keep_backups;
 
		for (my $i=0; $i < $keep_days; $i++) {
			my $timestamp;
			$timestamp = time if($i == 0);
			$timestamp = time - ($i * 86400) if($i > 0);
			my $filedate_to_keep = _convert_unixtime_to_date($timestamp);
			$filedate_to_keep =~ m/^([0-9]{4}\-[0-9]{2}\-[0-9]{2})/;
			$filedate_to_keep = $1;
			push @keep_backups, $filedate_to_keep;
		}
 
		if(-e "$conf->{'root_path'}/$db") {
 
			opendir(DBDIR, "$conf->{'root_path'}/$db");
			my @backups = readdir(DBDIR);
			closedir(DBDIR);
 
			foreach my $backup (@backups) {
				next if($backup eq "." || $backup eq ".." || $backup eq "$conf->{'myscriptname'}" || $db eq "_disabled");
				my $keep;
				foreach my $filedate (@keep_backups) {
					$keep = 1 if($backup =~ /^db_backup\.$filedate/);
				}
				next if($keep);
				qx~$conf->{'rm'} $conf->{'root_path'}/$db/$backup~ if($arg eq "run");
				print "will be deleted: $conf->{'root_path'}/$db/$backup\n" if($arg eq "check");
				print "Backup deleted: $db/$backup\n" if($arg eq "run");
			}	
 
		}
 
	}
}

print "\n" . disk_status(_config()) . "\n";


sub disk_status {

	my $config = shift;

	my $diskstatus = `$config->{'df'} -h`;

	my @status = split("\n", $diskstatus);
	
	foreach my $line (@status) {
		if($line =~ /$config->{'mount'}/) {
			my($filesystem,$size,$used,$avail,$use,$mounted) = split(/\s+/, $line);
			my $used = $use;
			$used =~ s/\%$//;
			return("Info: Diskspace $size: in use: $use -> Free: $avail") if($used < 80);
			return("Notice: Diskspace $size: in use: $use -> Free: $avail") if($used >= 80 && $used < 87);
			return("Warning: Diskspace $size: in use: $use -> Free: $avail") if($used >= 87 && $used < 92);
			return("Critical: Diskspace $size: in use: $use -> Free: $avail") if($used >= 92);
		}
	}

}
 
 
sub _convert_unixtime_to_date {
 
        my $timestamp = shift;
 
        # usage: _convert_unixtime_to_date(time); # time can be any unix-timestamp or empty (if empty it takes the current time).
        # returns: filename date
 
        $timestamp = time if(!$timestamp);
 
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($timestamp);
        my $date = $year + 1900 . '-' . 
                sprintf("%02d", $mon + 1) . '-' . 
                sprintf("%02d", $mday) . '-' . 
                sprintf("%02d", $hour) . '-' . 
                sprintf("%02d", $min);# . ':' . sprintf("%02d", $sec);
 
        return($date);
}
