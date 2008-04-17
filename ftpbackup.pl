#!/usr/bin/perl

# Subversion Properties:
# $Id$

use strict;
use warnings;
use Net::FTP;
use Getopt::Long;
use Config;
use GnuPG;
# create temporary files
use File::Temp;

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


my %config = getConfig();

vprint(\%config,"Server: $config{'server'}", "debug");
my $ftp=FTPinit(\%config);

my @temp = glob($config{'localdir'} . $config{'ospath'} . "20*");
FTPcheckOldVers(\@temp, \%config);

my $backup_dir = FTPinitLocal(\%config);
vprint(\%config, "Backing up into Directory: $backup_dir", "debug");

@temp = FTPlist($ftp, $config{'dir'});
chdir $backup_dir;
FTPgetFiles($ftp, \@temp, ".", \%config);
$ftp->quit;


sub FTPgetFiles {#{{{
	(my $ftp, my $list, my $ldir, my $config) = @_;
	mkdir $ldir unless -d $ldir;
	chdir $ldir;
	$ftp->cwd($ldir);
	my $status;
	foreach (@$list){
		my @files = split / +/, $_, 9;
		if ($_ =~ /^d/){
			vprint($config, "Downloading directory $files[8]", "debug");
			my @temp = $ftp->dir($files[8]);
			FTPgetFiles($ftp, \@temp, $files[8], $config);
		}
		else {
			vprint($config, "Downloading file $files[8]", "debug");
			$status = $ftp->get($files[8]); 
			vprint($config, "Could not download $files[8]", "warn") unless (defined($status));
		}
	}
	chdir ".." && $ftp->cdup();
	return(0);
}#}}}

sub FTPinit {#{{{
	my $config = shift;
	my $ftp = Net::FTP->new($config->{"server"}, Passive => $config->{"passive"}) or die "Cannot connect to $config->{'server'}";
	vprint($config, "successfull logged into Server $config->{'server'}", "debug");
	$ftp->login($config->{"user"}, $config->{"pass"}) or die "Cannot login\n Are Password and Username correct?";
	 # enable binary mode, if configured
	if($config{"binary"}){
		$ftp->binary;
		vprint($config, "Changed connection to binary mode", "debug");
	}
	# Check local Backup Directory
	eval { 
		mkdir $config->{"localdir"},0700 unless (-d $config->{"localdir"}); 
		chmod 0700, $config->{"localdir"} unless (-w $config->{"localdir"});
	};
	if ($@) {
		die "Error, setting up Backup Directory $config->{'localdir'}, exiting..."
	}
	else { 
		vprint($config, "$config->{'localdir'} looks alright", "debug"); 
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
$name takes an FTP account and recursively downloads all
files. This can be helpful for automatic backups.

Option:
-u --user=<username>       FTP Server User
-p --pass=<password>       FTP Server Password
-s --server                FTP Server
--port                     FTP Server Port
--recursive                recursively calculate size
-h --help

For example:
$name ftp://ftp.eu.kernel.org/pub/ 
would download all files below pub from the kernel mirror. 
(Don't actually try this!)
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
		vprint($config, "Directory \'$dir\' already exists in $config{'localdir'}", "debug");
	}
	else {
		mkdir $config{"localdir"} . $config{"ospath"} . $dir, 0700 ||
		print "Cannot create Directory $dir in $config{'localdir'}.\n";
	}
	return $config{"localdir"} . $config{"ospath"} . $dir;
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
				 die "Could not delete: $!";
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
	my $localdir	 = "~/perl_backup";
	# FTP control port
	my $port		 = 21;
	# Enable Passive mode? 1 enables, 0 disables
	my $passive      = 1;
	# Enable Recurisve mode? 1 enables, 0 disables
	my $recursive    = 1;
	# Enable Debug mode? 1 enables, 0 disables
	my $debug		 = 1;
	# Enable binary mode? 1 enables, 0 disables
	my $binary		 = 1;
	# Wieviele Versionen behalten:
	my $keep		 = 3;

	# Welches Directory?
	my $dir			 = ".";

	# exclude patterns
	my $exclude;

	# Operating System specific
	my $ospath  = ($Config{"osname"} =~ "MsWin" ) ? '\\' : '/';

	GetOptions('user=s' => \$user,
               'pass=s' => \$password,
               'help'  => sub {usage},
               'server=s' => \$host,
               'recursive' => \$recursive,
               'port=i' => \$port,
		       'passive=i' => \$passive,
		       'debug=i'   => \$debug,
			   'binary=i'  => \$binary,
			   'dir=s'	   => \$dir,
			   'localdir=s' => \$localdir);

	if (defined(@ARGV)){
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
	}
#	exit(0);

	my %config = (
		server	 =>  $host,
		user	 =>  $user,
		pass	 =>  $password,
		passive	 =>	 $passive,
		debug	 =>	 $debug,
		binary	 =>	 $binary,
		localdir =>  $localdir,
		ospath   =>  $ospath,
		keep	 =>	 $keep,
		dir		 =>  $dir
	);
	$config{"localdir"}=glob($config{"localdir"});

	return %config;
}#}}}

sub vprint {#{{{
	my ($config, $msg, $facility) = @_;
	if ($config->{"debug"}) {
		print "[$facility] $msg\n";
	}
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


# vim: set fdm=marker fdl=0:
