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

use FindBin;
 
sub _config {
 
	my %conf = ( 
 
		# root path
		'root_path'	=> "$FindBin::Bin/..",
		'myscriptname'	=> 'db_backup_runner.pl',

		# database variables
		'db_host'	=> '', # empty for localhost
		'db_user'	=> 'root',
		'db_pass'	=> '', # password if needed
 
		# system programs
		'mysqldump'	=> '/usr/bin/mysqldump',
		'gzip'		=> '/bin/gzip',
		'rm'		=> '/bin/rm',
		'df'		=> '/bin/df',
		'mount'		=> 'sda1,root,xvda1', # additional names for mountpoints can be added
 
	);

	$conf{'keep_days'} = get_custom_config(\%conf, 'keep-days');
	$conf{'runtime'} = get_custom_config(\%conf, 'runtime');
 
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
        print "backups. In this case configure the file 'custom-config' under '[keep_days]'\n";
	print "how many days you want to keep a backup for a specific database.\n\n";
	print "You can also configure the time for each database, when the backup\n";
	print "should be executed. You configure the execution times in the section\n";
	print "[runtime] in the file 'custom-config'.\n\n";
	print "Please configure a cronjob for this script which runs every minute.\n\n";
        print "To disable a backup move the database folder to the folder '_disabled'.\n";
        print "The database is skipped, even a configuration exists.\n\n";
        exit;
}
 
if($arg ne "run" && $arg ne "check") {
        print "Valid arguments are 'check' or 'run'\n";
        print "For more information execute the script without argument\n";
        print "Aborted.\n";
        exit;
}


# check execution

my @execute_db = check_execute(_config());

my $backup = create_backups(_config(), \@execute_db);
my $remove_old_backups = delete_backups(_config(), \@execute_db);

print "Backup creation:\n";
print "================\n\n";
print $backup if($backup);
print "No backup will be created.\n" if(!$backup && $arg eq "check");
print "No backup to create.\n" if(!$backup && $arg eq "run");
print "\n";
if($remove_old_backups) {
	print "Backup cleanup:\n";
	print "===============\n\n";
	print "This backups will be deleted:\n" if($arg eq "checked");
	print $remove_old_backups;
} else {
	print "No backups found to remove.\n";
}

print "\n" . disk_status(_config()) . "\n";
 
sub create_backups {
 
	my $conf = $_[0];
	my @exec_dbs  = @{$_[1]};

	my $output;
 
	opendir(DIR, "$conf->{'root_path'}");
	my @configured_dbs = readdir(DIR);
	closedir(DIR);

	# check which dbs to backup

	my @dbs;

	foreach my $confdb (@configured_dbs) {
		next if($confdb eq "." || $confdb eq ".." || $confdb eq "$conf->{'myscriptname'}" || $confdb eq "_disabled" || $confdb eq "mysql-backup");
		my $exec_is_configured;
		foreach my $key (keys %{$conf->{'runtime'}}) {
			$exec_is_configured = 1 if($key eq "$confdb");
		}
		my $run_now = undef;
		foreach my $execdb (@exec_dbs) {
			if($exec_is_configured) {
				$run_now = 1 if($execdb eq "$confdb");
			} else {
				$run_now = 1 if($execdb eq "default");
			}
		}
		push @dbs, $confdb if($run_now);

			
	}
 
	foreach my $db (@dbs) {
 
		my $filedate = _convert_unixtime_to_date();
		my $options;
		my $result = qx~$conf->{'mysqldump'} --single-transaction --quick --skip-lock-tables --defaults-extra-file=$conf->{'root_path'}/mysql-backup/custom-config $db > $conf->{'root_path'}/$db/db_backup.$filedate.sql 2>&1~ if($arg eq "run");
		next if($result =~ /Got error: 1049/);
		qx~$conf->{'gzip'} $conf->{'root_path'}/$db/db_backup.$filedate.sql~ if($arg eq "run");
		if($arg eq "check") {
		 	 $output .= "Backup /$db/db_backup.$filedate.sql will be created.\n";
		}		
		if($arg eq "run") {
			$output .= "Backup created: $db/db_backup.$filedate.sql\n";
		}
	}
	return($output);
}
 
sub delete_backups {
 
	my $conf = $_[0];
	my @exec_dbs  = @{$_[1]};

	my $output;
 
	opendir(DIR, "$conf->{'root_path'}");
        my @configured_dbs = readdir(DIR);
        closedir(DIR);

	my @dbs;

        foreach my $confdb (@configured_dbs) {
                next if($confdb eq "." || $confdb eq ".." || $confdb eq "$conf->{'myscriptname'}" || $confdb eq "_disabled" || $confdb eq "mysql-backup");
                my $exec_is_configured;
                foreach my $key (keys %{$conf->{'runtime'}}) {
                        $exec_is_configured = 1 if($key eq "$confdb");
                }
                my $run_now = undef;
                foreach my $execdb (@exec_dbs) {
                        if($exec_is_configured) {
                                $run_now = 1 if($execdb eq "$confdb");
                        } else {
                                $run_now = 1 if($execdb eq "default");
                        }
                }
                push @dbs, $confdb if($run_now);


        }

 
	foreach my $db (@dbs) {
 
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
				$output .= "will be deleted: $conf->{'root_path'}/$db/$backup\n" if($arg eq "check");
				$output .= "Backup deleted: $db/$backup\n" if($arg eq "run");
			}	
 
		}
 
	}
	return($output);
}

sub disk_status {

	my $config = shift;

	my $diskstatus = `$config->{'df'} -h`;

	my @status = split("\n", $diskstatus);
	my @mounts = split("\,", $config->{'mount'});

	my $mount;
        foreach my $m (@mounts) {
		foreach my $line (@status) {
        		$mount = $m if($line =~ /$m/);
		}
        }
	
	foreach my $line (@status) {
		if($line =~ /$mount/) {
			my($filesystem,$size,$used,$avail,$use,$mounted) = split(/\s+/, $line);
			$used = $use;
			$used =~ s/\%$//;
			return("Info: Diskspace $size: in use: $use -> Free: $avail") if($used < 80);
			return("Notice: Diskspace $size: in use: $use -> Free: $avail") if($used >= 80 && $used < 87);
			return("Warning: Diskspace $size: in use: $use -> Free: $avail") if($used >= 87 && $used < 92);
			return("Critical: Diskspace $size: in use: $use -> Free: $avail") if($used >= 92);
		}
	}

}
 
sub get_custom_config {

	my $config = shift;
	my $tag    = shift;

	my $pwd = "$config->{'root_path'}/mysql-backup";
	chomp($pwd);

	if(!-d "$config->{'root_path'}/_disabled") {
		mkdir("$config->{'root_path'}/_disabled", 0755) or die "No permissions to create $config->{'root_path'}/_disabled.\nPlease check the permissions of your user.\n";
	}

	if(!-e "$pwd/custom-config") {
		open(C, ">$pwd/custom-config") or die "cannot create $pwd/custom-config\n";
		print C "# Custom configuration file for database backups.\n";
		print C "# Please do not delete the section tags and do not remove 'default'\n";
		print C "# This values must exist.\n\n";
		print C "[keep-days]\n";
		print C "\n# Databasename Days to keep\n#Example:\n#wordpress   5\n\ndefault   3\n";
		print C "\n";
		print C "# configure the time when the backup of a specific database should be executed.\n";
		print C "# Databasename HH:MM\n#Example: wordpress:    09:00,11:00,23:50\n";
		print C "# multiple times comma seperated, without space!\n\n";
		print C "[runtime]\ndefault   04:01\n\n";
		print C "# configure the database access for mysqldump here:\n\n";
		print C "[mysqldump]\nhost = localhost\nuser = dbuser\npassword = \"\"\n";
		close(C);

		chmod 0600, "$pwd/custom-config";

		print "custom configuration was not found.\n";
		print "The file custom-config has been created first.\n";
		print "Please configure the file, or if you just use the defaults, start the script again.\n";
		exit;
	} else {

		my ($custom_config, $tag_on);
		open(C, "<$pwd/custom-config");
		while (<C>) {
			next if($_ eq "\n" || $_ =~ /^\#/);	
			if($_ !~ /[\[\]]/) {
				my ($dbname, $value) = split(/\s+/, $_);
				chomp($value);
				$custom_config->{"$dbname"} = $value if($tag_on);
			} else {
				if($_ =~ /\[$tag\]/) {
					$tag_on = $tag;
				} else {
					$tag_on = undef;
				}
			}
		}

		return($custom_config);
	}

}

sub check_execute {

	my $config = shift;

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
        my $exectime =  sprintf("%02d", $hour) . ':' . sprintf("%02d", $min);

	if($arg eq "check") {
		print "Execution times:\n";
		print "================\n\n";
	}
		
	my @exec_dbs;
	foreach my $db (keys %{$config->{'runtime'}}) {
		my @times = split(",", $config->{'runtime'}->{$db});
		foreach my $time (@times) {
			if($arg eq "check") {
				push @exec_dbs, $db;
				print"$db will execute at $time -> now: $exectime\n";
			}
			if($arg eq "run") {
				push @exec_dbs, $db if($time eq "$exectime");

			}
		}
	}

	print "\n" if($arg eq "check");
	exit if(!@exec_dbs && $arg eq "run");
	return(@exec_dbs);
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
