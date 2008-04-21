#!/usr/bin/perl

# Subversion Properties:
# $Id$

use strict;
use warnings;
# obviously we need a ftp module
use Net::FTP;
# commandline parsing
use Getopt::Long;
# access perl-variables
use Config;
# read from terminal (e.g. password)
use Term::ReadKey;
# not yet needed
#
# create temporary files
#use File::Temp;

# Function prototypes
sub usage;
sub vprint;
sub getConfig;
sub FTPinit;
sub FTPlist;
sub FTPinitLocal;
sub FTPcheckOldVers;
sub FTPgetFiles;
sub deltree;
sub printStats;
sub GPGencrypt;

our %config = getConfig();

vprint("Loggin into Server: $config{'server'} as $config{'user'}", "debug");
my $ftp=FTPinit();

my @temp = glob($config{'localdir'} . $config{'ospath'} . "20*");
FTPcheckOldVers(\@temp, \%config);
FTPcheckOldVers(\@temp);

my $backup_dir = FTPinitLocal();
vprint( "Backing up $config{'dir'} into Directory: $backup_dir", "debug");

@temp = FTPlist($ftp, $config{'dir'});
chdir $backup_dir;
unless (FTPgetFiles($ftp, \@temp, $config{'dir'} )){
	vprint( "Error occured, aborting.", "debug");
	$ftp->quit;
	exit(1);
}
$ftp->quit;
printStats if $config{'stats'};


sub FTPgetFiles {#{{{
	(my $ftp, my $list, my $ldir) = @_;
	mkdir $ldir unless -d $ldir;
	chdir $ldir;
	foreach ( split /$config{'ospath'}/, $ldir){
		vprint( "Enter directory: $_", "debug");
		if ( not $ftp->cwd($_)) {
			vprint( "Could not enter directory: $_", "error");
			return(0);
		}
	}
	my $status=1;
	LIST: foreach (@$list){
		my $skip = 0;
		my $xpattern;
		my @files = split / +/, $_, 9;
		# Skip files/directories that match exclude pattern
		foreach $xpattern (@{$config{'exclude'}}){
			 if ($files[8] =~ /$xpattern/) {
				 vprint( "Skipping File $files[8] because it matches exclude pattern", "debug"); 
				 last LIST;
			 }
		 }
		# Recursive download for directories, if configured
		if (/^d/){
			unless ($config{'recursive'}) {
				vprint( "Skipping directory $files[8]", "debug");
				next LIST;
			}
			vprint( "Downloading directory $files[8]", "debug");
			$config{'statistics'}->{'dirs'}+=1;
			my @temp = $ftp->dir($files[8]);
			$status = FTPgetFiles($ftp, \@temp, $files[8]);
		}
		# download files
		else {
			vprint( "Downloading file $files[8] $!", "debug");
			$config{'statistics'}->{'files'}+=1;
			$config{'statistics'}->{'size'}+=$files[4];
			$status = $ftp->get($files[8]); 
			if ($config{'enc'}){
				use GnuPG;
				vprint("encrypting $files[8] using provided password\n", "debug");
				chomp(my $dir=`pwd`);
				GPGencrypt($dir.$config{'ospath'}.$files[8]);

			}
			vprint("Could not download $files[8] $!", "error") unless (defined($status));
		}
	}
	chdir ".." && $ftp->cdup();
	return($status);
}#}}}

sub FTPinit {#{{{
	# This looks a little bit odd, Passive mode is enabled, if $config{'active'} is not zero
	my $ftp = Net::FTP->new($config{"server"}, Passive => $config{"active"}) or die "[error] Cannot connect to $config{'server'}";
	vprint( "successfull logged into Server $config{'server'}", "debug");
	$ftp->login($config{"user"}, $config{"pass"}) or die "[error] Cannot login\n Are Password and Username correct?";
	 # enable binary mode, if configured
	if($config{"binary"}){
		$ftp->binary;
		vprint( "Changed connection to binary mode", "debug");
	}
	# Check local Backup Directory
	eval { 
		mkdir $config{"localdir"} unless (-d $config{"localdir"}); 
		chmod 0700, $config{"localdir"} unless (-w $config{"localdir"});
	};
	if ($@) {
		die "[error] Setting up Backup Directory $config{'localdir'}, exiting..."
	}
	else { 
		vprint( "$config{'localdir'} looks alright", "debug"); 
	}
	return $ftp;
}#}}}

sub FTPlist{#{{{
	(my $ftp, my $dir)  = @_;
	return $ftp->dir($dir);
}#}}}

sub usage{#{{{
    chomp(my $name=`basename $0`);
    print <<EOF;
Usage: $name [OPTION] ftp://server/directory
$name takes an FTP account and recursively downloads all files. This can
be helpful for automatic backups. By default, it will save all files in
the current directory below a directory YYYYMMDD/hostname.
If no username is given, $name tries to use anonymous login.

Option:
-h --help			   This screen
-u --user=<username>   FTP Server User
-p --pass=<password>   FTP Server Password (in general:
					   DO NOT USE THIS OPTION)
--port                 FTP Server Port
-d --debug             for debugging $name
--[no]recursive        (do not) download recursively
--active               use active mode (passive=default)
--encrypt			   enable encryption using symmetric gpg encryption.
					   (when used, you will be asked for a password).
--statistics           Print download statistics when finished.
--encrypt			   encrypt each file using gpg. By default $name
					   will ask for a passphrase.
--archivedir=dir       Save downloaded files in dir (default: current 
					   directory)
--exclude='pattern'    Use an exclude pattern. Pattern  is matched
					   as regular expression. You may use this option 
					   several times.

For example:
$name --statistics  ftp://ftp.eu.kernel.org/pub/ 
would download all files below pub from the kernel mirror and save them in
the current directory below YYYYYMMDD/ftp.eu.kernel.org/. When finished it
will print a nice little statistic.
EOF
     exit(1);
}#}}}

sub FTPinitLocal{#{{{
	my $config	 = shift;

	# Datum im Format YYYYMMDD
	(my $mday, my $mon, my $year) = (localtime(time))[3,4,5];
	# Test for existance of directory
	my $dir = $year+1900 . sprintf("%02d",$mon+1) . $mday;
	if (-d $config{"localdir"} . $config{"ospath"}.$dir) {
		vprint( "Directory '$dir' already exists in $config{'localdir'}", "debug");
	}
	else {
		mkdir $config{"localdir"} . $config{"ospath"} . $dir ||
		vprint("Cannot create Directory $dir in $config{'localdir'}.", "error");
	}
	chdir $config{"localdir"} . $config{"ospath"} . $dir;
	vprint( "Creating directory $config{'server'} in $dir", "debug");
	unless ( -d $config{"server"}){
		vprint($config, "Creating directory $config{'server'} in $dir", "debug");
		mkdir $config{"server"} || print "Cannot create Directory $config{'server'} in $config{'localdir'}.\n";
	 }
	return $config{"localdir"} . $config{"ospath"} . $dir . $config{'ospath'} . $config{'server'};
}#}}}

sub FTPcheckOldVers{#{{{
	my $temp   = shift;
	my $config = shift;
	if (@temp >= $config{'keep'}){
		 # Determine the oldest entries to delete
		 # sort reverse by mtime
		 @temp = sort {(stat($a))[9] <=> (stat($b))[9]} @temp;
		 while (@temp >= $config{'keep'}){
			 vprint(\%config, "Deleting file $temp[0]", "debug");
			 eval{
				 deltree $temp[0];
				 shift(@temp);
			 };
			 if ($@){
				 die "[error] Could not delete: $!";
			 }
		 }
		
	}
	return(0);
}#}}}

sub getConfig(){#{{{
	
    # Default Options, these can be overruled
    # using commandline optins
	my $user		 = "anonymous";
	my $password	 = 'none@none.invalid';
	my $host		 = "localhost";
	my $localdir	 = ".";
	# FTP control port
	my $port		 = 21;
	# Enable active mode? 1 enables, 0 disables
	my $active       = 0;
	# disable statistics
	my $stats		 = 0;
	# Enable Recurisve mode? 1 enables, 0 disables
	my $recursive    = 1;
	#printf("%s recursion\n", $recursive? "enabled" : "disabled");
	# Enable Debug mode? 1 enables, 0 disables
	my $debug		 = 0;
	# Enable binary mode? 1 enables, 0 disables
	my $binary		 = 1;
	# Wieviele Versionen behalten:
	my $keep		 = 3;

	# Welches Directory downloaden
	my $dir			 = ".";

	# exclude patterns
	my @exclude		 = ();

	# Operating System specific
	my $ospath  = ($Config{"osname"} =~ "MsWin" ) ? '\\' : '/';

	# Statistics Hash
	my %statistics  =  (
		stime	 => time,
		files	 => 0,
		dirs	 => 0,
		size     => 0
	);

	# Encrpytion: 0 disabled, 1 enabled
	my $encrypt  = 0;

	GetOptions('user=s'    => \$user,#{{{
               'pass=s'    => \$password,
               'help'      => sub {usage},
               'server=s'  => \$host,
               'recursion!'=> \$recursive,
               'port=i'    => \$port,
		       'active'    => \$active,
		       'debug'     => \$debug,
			   'statistics'=> \$stats,
			   'binary'    => \$binary,
			   'archivedir=s' => \$localdir,
			   'encrypt'   => \$encrypt,
			   'exclude=s' => \@exclude);#}}}

	if (defined(@ARGV)){#{{{
		my $uri		 = shift(@ARGV);
		# now we have 4 fields: 1: ftp:/
		#                       2: <null>
		#                       3: server
		#                       4: directory
		my @a_uri	 = split /\//,$uri, 4;
		$host        = $a_uri[2];
		if ((defined($a_uri[3]) and not ($a_uri[3] eq  ""))){
			$dir		 = $a_uri[3];
		}
	}#}}}


	my %config = (
		user	 =>  $user,
		pass	 =>  $password,
		server	 =>  $host,
		localdir =>  $localdir,
		port     =>  $port,
		active	 =>	 $active,
		stats    =>  $stats,
		recursive => $recursive,
		debug	 =>	 $debug,
		binary	 =>	 $binary,
		keep	 =>	 $keep,
		ospath   =>  $ospath,
		exclude  =>  \@exclude,
		statistics => \%statistics,
		dir		 =>  $dir,
		enc		 =>  $encrypt
	);
	$config{"localdir"}=glob($config{"localdir"});

	if ((!defined($config{'pass'})) or ($config{'pass'} eq "") or ($config{'user'} ne "anonymous") ) {
		ReadMode('noecho');
		print "No Password has been given, \nplease type password for user $config{'user'}: ";
		$config{'password'} = ReadLine(0);
		print "\n";
		ReadMode('restore');
	}
	if ($config{'enc'}){
			my $try=0;
			my $temp, my $temp1;
			do {
				print "\nPlease try again, both passphrase did NOT match!\n" if ($try > 0);
				$try++;
				ReadMode('noecho');
				print "\nEnter Password for encryption:";
				$temp = ReadLine(0);
				print "\nRe-enter Password for encryption:";
				$temp1 = ReadLine(0);
				die "Could not reliably determine which password to use for encryption" if ($try >= 3);
			}
		until ($temp eq $temp1);
		print "\n";
		chomp($config{'epasswd'} = $temp);
	}

		


	return %config;
}#}}}

sub vprint {#{{{
	my ($msg, $facility) = @_;
	if ($config{"debug"}) {
		print "[$facility] $msg\n";
	}
}#}}}

sub printStats {#{{{
	my %stat= %{$config{'statistics'}};
	$stat{'etime'} = time;
	my $duration   = $stat{'etime'} - $stat{'stime'};
	my $bandwidth  = ($duration == 0) ? $stat{'size'} : sprintf("%02d", $stat{'size'} / $duration);
	my $bandwith   = 0;
	my $time_unit  = "sec";
	my $size_unit  = "bytes";
	if ($duration >= 3600*24){
		$duration  = sprintf("%02d", $duration/(3600*24));
		$time_unit = 'days';
	}
	elsif ($duration >= 3600) {
		$duration  = sprintf("%02d", $duration/3600);
		$time_unit = 'hours';
	}
	elsif ($duration >= 60) {
		$duration  = sprintf("%02d", $duration/60);
		$time_unit = 'minutes';
	}
	# Gigabytes
	if ($stat{'size'} >= 1024*1024*1024){
		$stat{'size'}  = sprintf("%02d", $stat{'size'}/(1024*1024*1024));
		$size_unit     = "GB";
	}
	# Megabytes
	elsif ($stat{'size'} >= 1024*1024){
		$stat{'size'}  = sprintf("%02d", $stat{'size'}/(1024*1024));
		$size_unit       = "MB";
	}
	# Kilobytes
	elsif ($stat{'size'} >= 1024){
		$stat{'size'}  = sprintf("%02d", $stat{'size'}/1024);
		$size_unit       = "kB";
	}

	print "\nDownload Summary:\n";
	print "=" x 70;
	print "\n";
	print "Files:\t\t$stat{'files'}\n";
	print "Folder:\t\t$stat{'dirs'}\n";
	print "Duration: \t$duration $time_unit\n";
	print "Transfered: \t$stat{'size'} $size_unit\n";
	print "Bandwith: \t$bandwidth bytes/s\n"; 
	print "=" x 70;
	print "\n\n";
}#}}}

sub deltree {#{{{
	my $dir = shift;
	local *DIR;
	opendir DIR, $dir or die "[error]: Cannot open $dir: $!";
	foreach (readdir DIR) {
		next if /^\.{1,2}$/;
		my $name = "$dir/$_";
		deltree $name if ( -d $name );
		unlink $name;
	}
	closedir DIR;
	rmdir $dir;
	return(0);
}#}}}

sub GPGencrypt {#{{{
#	no strict "subs";
	my $file = shift;
	my $gpg = new GnuPG();
	my $password = $config{'epasswd'};
	$gpg->encrypt(plaintext => $file, output => $file.".gpg", 
		passphrase => $password, symmetric => 1);
	vprint("encrypting $file using $config{'epasswd'},debug)";
	unlink $file;
}#}}}

# vim: set fdm=marker fdl=0:
