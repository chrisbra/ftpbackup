#!/usr/bin/perl

use strict;
use warnings;
use Net::FTP;
use Getopt::Long;
use Gnupg;

# Function prototypes
sub usage;
sub vprint;
sub getConfig;
sub FTPinit;
sub FTPlist;


sub getConfig(){#{{{
	
    # Default Options, these can be overruled
    # using commandline optins
	my $user		 = "chrisbra";
	my $password	 = "b97urlington";
	my $host		 = "localhost";
	my $localdir	 = "~/perl_backup";
	# Ftp-Data port, FTP control port
	my @port		 = (20,21);
	# Enable Passive mode? 1 enables, 0 disables
	my $passive      = 1;
	# Enable Recurisve mode? 1 enables, 0 disables
	my $recursive    = 1;
	# Enable Debug mode? 1 enables, 0 disables
	my $debug		 = 1;
	# Enable binary mode? 1 enables, 0 disables
	my $binary		 = 1;

	GetOptions('user=s' => \$user,
               'pass=s' => \$password,
               'help'  => sub {usage},
               'server=s' => \$host,
               'recursive' => \$recursive,
               'port=i' => \$port,
		       'passive=i' => \$passive,
		       'debug=i'   => \$debug,
			   'binary=i'  => \$binary,
			   'localdir=s' => \$localdir);

	my %config = (
		server	 =>  $host,
		user	 =>  $user,
		pass	 =>  $password,
		passive	 =>	 $passive,
		debug	 =>	 $debug,
		binary	 =>	 $binary,
		localdir =>  $localdir
	);
	#my %config = (
	#	server	 =>  "localhost",
	#	user	 =>  "chrisbra",
	#	pass	 =>  "b97urlington",
	#	passive	 =>	 "1",
	#	debug	 =>	 "1",
	#	binary	 =>	 "1",
	#	localdir =>   "~/perl_backup"
	#);
	$config{"localdir"}=glob($config{"localdir"});

	return %config;
}#}}}

sub vprint {#{{{
	my ($config, $msg) = @_;
	if ($config->{"debug"}) {
		print "$msg\n";
	}
}#}}}

my %config;
%config = getConfig();

vprint(\%config,"Server: $config{'server'}");
my $ftp=FTPinit(\%config);
FTPlist(\%config, $ftp);


sub FTPinit {#{{{
	my $config = shift;
	my $ftp = Net::FTP->new($config->{"server"}, Passive => $config->{"passive"}) or die "Cannot connect to $config->{'server'}";
	vprint($config, "successfull logged into Server $config->{'server'}");
	$ftp->login($config->{"user"}, $config->{"pass"}) or die "Cannot login\n Are Password and Username correct?";
	 # enable binary mode, if configured
	if($config{"binary"}){
		$ftp->binary;
		vprint($config, "Changed connection to binary mode");
	}
	# Check local Backup Directory
	eval { 
		mkdir $config->{"localdir"},0700 unless (-d $config->{"localdir"}); 
		chmod 0600, $config->{"localdir"} unless (-w $config->{"localdir"});
	};
	if ($@) {
		die "Error, setting up Backup Directory $config->{'localdir'}, exiting..."
	}
	else { 
		vprint($config, "$config->{'localdir'} looks alright"); 
	}
	return $ftp;
}#}}}

sub FTPlist{#{{{
	(my $config, my $ftp)  = @_;
	my @list = $ftp->ls;
	foreach (@list){
		vprint($config,"Gettting: $_");
		$ftp->get($_, "$config->{'localdir'}"."/"."$_");
	}
}#}}}

sub usage{
    chomp(my $name=`basename $0`);
    print <<EOF;
Usage: $name [OPTION]
$name takes an FTP account and recursively downloads all
files. This can be helpful for automatic backups.

Option:
-u --user=<username>       IMAP Server User
-p --pass=<password>       IMAP Server Password
-s --server                IMAP Server
--port                     IMAP Server Port
--recursive                recursively calculate size
-h --help
EOF
     exit(1);
}

