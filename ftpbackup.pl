#!/usr/bin/perl

=head1 NAME

ftpbackup - backup from an ftp server

=head1 SYNOPSIS

B<ftpbackup> [B<Options>] I<URL>

=head1 DESCRIPTION

B<ftpbackup> allows to backup all files from an FTP server locally. If no
local directory is specified, B<ftpbackup> tries to save in the current
directory. 

When storing, B<ftpbackup> stores all downloaded files below
YYYYMMDD/servername, so you can create a nice little hierachical
storage. For each servername, B<ftpbackup> keeps track of a default of 3
backups, removing old backups if necessary. If you want to keep more
than 3 backup-version, look at the B<--keep> option. 

Additionally B<ftpbackup> can try to hardlink each backup with the previous
version similar to how rsync does it (in fact, it uses rsync for
hardlinking the data). B<ftpbackup> can also encrypt each downloaded file
using C<gpg --encrypt --symmetric>. 

If no username/password is specified, B<ftpbackup> will try to
authenticat using anonymous logins (this means username=anonymous,
password=none@none.invalid).

=head1 OPTIONS

=over 4

=item B<--active>

Use active connection mode. (Default is passive).

=item B<--archivedir>=I<dir>       

Store the backups below I<dir>. Foreach run B<ftpbackup> will create
a directory in the date format 'YYYYMMDD' (as B<date +'%Y%m%d>' would
create it) and below that directory a directory of the I<server>. 
(e.g. when running on Apr. 4th, 2008 and backing up kernel.org,
B<ftpbackup> would create a directory structure I<20080404/kernel.org/>)

=item B<-d>, B<--debug>

Turn on Debugging Infos.

=item B<--encrypt> 

This switch enables symmetric encryption using B<gpg>(1). In order for
this to work, B<gpg>(1) needs to be installed and available in your
path and the perl module B<GnuPG> needs to be installed. If the option
B<--passfile> is not specified, B<ftpbackup> will interactively ask for
an encryption password.

=item B<--exclude=>I<'pattern'>    

Specify an exclude pattern. You can use perl regular expressions (see
B<perlre>(1) for details). It is possible to specify this option several
times and each pattern will be applied to all files and directories on
the server, skipping each match.

=item B<--hardlink>

When storing the data locally, use B<rsync>(1) to store the data.
Basically this will call B<rsync>(1) I<--archive> I<--hard-links>
I<--sparse> I<--link-dest=oldbackup> I<src/> I<dest/>
This is handy, when automatically downloading regularly, since that will
store each version of a file only once.

=item B<-h>, B<--help>

Displays the help screen.

=item B<--keep>=number

Only keep I<number> version locally, deleting the oldest version. If not
specified, ftpbackup will keep 3 versions.

=item B<--passfile=>I<file>      

When encryption has been specified using B<--encrypt>, you can instruct
B<ftpbackup> to read I<file> for a password. This file needs only to
contain the password. B<ftpbackup> will use the B<whole input> as
passphrase.

=item B<--port>

Specify the FTP Server Port

=item B<--[no]recursion>        

By default, B<ftpbackup> will recursively download all files below the
given directory. You can turn off recursive downloading using
B<--norecursion>

=item B<--removesrc>            

Try to remove the directory on the FTP server when finished.

=item B<--statistics>           

Print a little statistic when finished. 


=head1 NOTES

B<ftpbackup> requires B<perl>(1) of version 5.8 or higher. If you want
to make use of hardlinking your downloaded backups, B<ftpbackup> needs
B<rsync>(1) available in your path and the perl module B<File::Rsync>. For
encrypting the downloaded files you'll need the perl module B<GnuPG> and
B<gpg>(1) available in your path.

=head2 FTP URLs

B<ftpbackup> expects B<FTP> URLs using the following syntax:
I<ftp://username:password@server/directory>. If no password is
specified, B<ftpbackup> will ask interactively for the password. If both
username and password are not specified, B<ftpbackup> will use anonymous
authentication. You can leave out the directory, in which case
B<ftpbackup> will simply try to download from the server's root level.

=back

=head1 EXAMPLES

=over 4

=item B<ftpbackup> I<--statistics> ftp://ftp.eu.kernel.org/pub/

Download all data from ftp.eu.kernel.org/pub using anonymous access.
When finished print a litte statistic summary.

=item B<ftpbackup> I<--statistics> I<--exclude='\.iso$'>
ftp://ftp.eu.kernel.org/pub/

Download all files, except iso images, when finished print a little
summary.

=item B<ftpbackup> I<--statistics> I<--exclude='\.iso$'> I<--encrypt>
I<--norecursion> ftp://ftp.eu.kernel.org/pub/dist/knoppix

Download only files in directory knoppix on the kernel server, excluding iso
images and locally encrypting the files. You will be asked for a password when
run.

=item B<ftpbackup> I<--hardlink> I<--encrypt> I<--keep=5>
I<--norecursion> ftp://ftp.eu.kernel.org/pub/dist/knoppix

Download all files in directory knoppix on the kernel server and locally
encrypting the files. When storing the files locally try to hardlink the files
with an older backup if one exists. But keep only 5 versions locally. (The
oldest one will be deleted.) Hardlinking obviously only works, when you
encrypt with the same passphrase every time.

=back

=head1 BUGS

When run several times a day for the same ftp server, B<ftpbackup> will
happily overwrite already existing files.
B<ftpbackup> does not yet take care of the permissions on the server. So it
will create all files as the current user with the default umask.
When interrupted and the option I<--hardlink> is used, it will not clean up
already downloaded files.

=head1 AUTHOR

Copyright 2008 by Christian Brabandt <cb@256bit.org>

Licensed under the GNU GPL.

=cut

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
# create temporary files
use File::Temp qw /tempdir/ ;
#use File::Spec::Functions;
#use Cwd ;
use Cwd  qw / abs_path getcwd / ;

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
sub GPGdetPassphrase;
sub RsyncBackupDirs;

# This is main:

my $DEBUG  = 1;
our %config;
$config{'debug'} = $DEBUG;
%config = getConfig();

vprint("Loggin into Server: $config{'server'} as $config{'user'}", "debug");
my $ftp=FTPinit();

my @temp = glob($config{'localdir'} . $config{'ospath'} . "20*" . $config{'ospath'} . $config{'server'});
my $lsrc = FTPcheckOldVers(\@temp);
if (@$lsrc >= 1){
	$lsrc=abs_path($$lsrc[0]);
}
else {
	$lsrc = undef;
}

my $backup_dir = FTPinitLocal();
vprint( "Backing up $config{'dir'} into Directory: $backup_dir", "debug");
# change relative path of $backup_dir to absolute path
my $final_backup_dir = getcwd();

my $tdir;
if ($config{'hardlink'}){
    $tdir  = tempdir();
    chdir $tdir;
	mkdir $backup_dir;
}
$SIG{TERM} = $SIG{INT} = $SIG{QUIT} = $SIG{HUP} = sub { 
	if ( -d $tdir ){
		deltree $tdir; 
	}
	if ( -d $backup_dir) {
		deltree $backup_dir;
	}
	die "Unexpected signal, quitting...\n";
}

@temp = FTPlist($ftp, $config{'dir'});
chdir $backup_dir;
unless (FTPgetFiles($ftp, \@temp, $config{'dir'} )){
    $ftp->quit;
    die "[error] Some error occured, aborting...",$ftp->message;
}
if ($config{'delftp'}) {
     vprint( "Trying to delete $config{'dir'} on server", "debug");
     $ftp->rmdir($config{'dir'}) or 
     die "[error] Could not delete $config{'dir'}\n", $ftp->message;
 }
$ftp->quit;

if ($config{'hardlink'}){
    RsyncBackupDirs($tdir, $final_backup_dir, $lsrc);
    deltree($tdir);
}

printStats if $config{'stats'};

# Finished


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
                 next LIST;
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
            vprint( "Downloading file $files[8]", "debug");
            $config{'statistics'}->{'files'}+=1;
            $config{'statistics'}->{'size'}+=$files[4];
            $ftp->get($files[8]) or die "[error] Downloading failed: ",$ftp->message;
			my $mtime = $ftp->mdtm($files[8]);
            vprint("Could not download $files[8] $!", "error") unless (defined($status));
            if ($config{'enc'}){
                vprint( "Encrypting file $files[8]", "debug");
                my $s = GPGencrypt($files[8]) if ($config{'enc'});
                vprint("Could not encrypt $files[8] $!", "error") unless (defined($s));
            }
			utime $mtime, $mtime, ($files[8]);
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
    return $ftp;
}#}}}

sub FTPlist{#{{{
    (my $ftp, my $dir)  = @_;
    return $ftp->dir($dir);
}#}}}

sub usage{#{{{
    chomp(my $name=`basename $0`);
    print <<EOF;
Usage: $name [OPTION] URL
$name takes an FTP account and recursively downloads all files. This can
be helpful for automatic backups. By default, it will save all files in
the current directory below a directory YYYYMMDD/hostname.
If no username is given, $name tries to use anonymous login.

Option:
-h --help              This screen
--port                 FTP Server Port
-d|--debug             for debugging $name
--[no]recursion        (do not) download recursively
--active               use active mode (passive=default)
--encrypt              enable encryption using symmetric gpg encryption.
                       (when used, you $name will asked for a password).
--statistics           Print download statistics when finished.
--passfile='file'      When encrypting the files locally using gnupg, 
                       use the password found in file as symmetric
                       passphrase.
--archivedir=dir       Save downloaded files in dir (default: current 
                       directory)
--removesrc            Try to remove the directory on the FTP server
                       when finished.
--exclude='pattern'    Use an exclude pattern. Pattern  is matched
                       as regular expression. You may use this option 
                       several times.
--hardlink             hardlink backups using rsync

URL should generally be of the form: ftp://[user:password]\@host[/directory],
where user and password are optionally 

For example:
$name --statistics  ftp://ftp.eu.kernel.org/pub/ 
would download all files below pub from the kernel mirror and save them in
the current directory below YYYYYMMDD/ftp.eu.kernel.org/. When finished it
will print a nice little statistic.
EOF
     exit(0);
}#}}}

sub FTPinitLocal{#{{{
#   my $config   = shift;

    # Datum im Format YYYYMMDD
    (my $mday, my $mon, my $year) = (localtime(time))[3,4,5];
    # Test for existance of directory
    my $dir = $year+1900 . sprintf("%02d",$mon+1) . sprintf("%02d", $mday);
    if (-d $config{"localdir"} . $config{"ospath"}.$dir) {
        vprint( "Directory '$dir' already exists in $config{'localdir'}", "debug");
    }
    else {
        mkdir $config{"localdir"} . $config{"ospath"} . $dir ||
        vprint("Cannot create Directory $dir in $config{'localdir'}.", "error");
    }
    chdir $config{"localdir"} . $config{"ospath"} . $dir;
    unless ( -d $config{"server"}){
        vprint("Creating directory $config{'server'} in $dir", "debug");
        mkdir $config{"server"} || die "Cannot create Directory $config{'server'} in $config{'localdir'}.\n";
     }
    chdir $config{"server"};
    return $config{"localdir"} . $config{"ospath"} . $dir . $config{'ospath'} . $config{'server'};
}#}}}

sub FTPcheckOldVers{#{{{
    my $temp   = shift;
    #my $config = shift;
    if (@temp >= $config{'keep'}){
         # Determine the oldest entries to delete
         # sort reverse by mtime
         @temp = sort {(stat($a))[9] <=> (stat($b))[9]} @temp;
         while (@temp >= $config{'keep'}){
             vprint("Deleting file $temp[0]", "debug");
             eval{
                 deltree $temp[0];
                 # When we are here, the toplevel directory YYYYMMDD
                 # might be empty, so just in case try to delete it.
                 # This should generelly be safe, since rmdir won't delete
                 # directories that are not empty.
                 # 
                 # $temp contains a string like that: ./20080420/server
                 my @dir=split /$config{'ospath'}/,$temp[0],3;
                 rmdir $dir[1];
                 shift(@temp);
             };
             if ($@){
                 die "[error] Could not delete: $!";
             }
         }
        
    }
    # do not return a reference to array @temp, as 
    # this might change later
    my @array = @temp;
    return \@array;
}#}}}

sub getConfig(){#{{{
    
    # Default Options, these can be overruled
    # using commandline optins
	my $user;
	my $password;
	my $host;
	# Welches Directory downloaden
	my $dir;
    my $localdir     = ".";
    # FTP control port
    my $port         = 21;
    # Enable active mode? 1 enables, 0 disables
    my $active       = 0;
    # disable statistics
    my $stats        = 0;
    # Enable Recurisve mode? 1 enables, 0 disables
    my $recursive    = 1;
    #printf("%s recursion\n", $recursive? "enabled" : "disabled");
    # Enable Debug mode? 1 enables, 0 disables
    my $debug        = 0;
    # Enable binary mode? 1 enables, 0 disables
    my $binary       = 1;
    # Wieviele Versionen behalten:
    my $keep         = 3;


    # exclude patterns
    my @exclude      = ();

    # Operating System specific
    my $ospath  = ($Config{"osname"} =~ "MsWin" ) ? '\\' : '/';

    # Statistics Hash
    my %statistics  =  (
        stime    => time,
        files    => 0,
        dirs     => 0,
        size     => 0
    );

    # Encrpytion: 0 disabled, 1 enabled
    my $encrypt  = 0;
    # holds the name of a file containing the password
    # with which to encrypt using gpg
    my $passfile;
    # Delete original data ?
    my $delete_source = 0;
    # hardlink files
    my $hardlink = 0;

    GetOptions('help'      => sub {usage}, #{{{
               'server=s'  => \$host,
               'recursion!'=> \$recursive,
               'port=i'    => \$port,
               'active'    => \$active,
               'debug'     => \$debug,
               'statistics'=> \$stats,
               'binary'    => \$binary,
               'archivedir=s' => \$localdir,
               'passfile=s'  => \$passfile,
			   'keep=i'	   => \$keep,
               'removesrc' => \$delete_source,
               'encrypt'   => \$encrypt,
               'hardlink'  => \$hardlink,
               'exclude=s' => \@exclude);#}}}

( $user, $password, $host, $dir ) = parseCmdline(@ARGV);

# Only for testing purposes
#print "user: $user\n";
#print "password: $password\n";
#print "host: $host\n";
#print "dir: $dir\n";
#die "exit";


    my %config = (#{{{
        user     =>  $user,
        pass     =>  $password,
        server   =>  $host,
        localdir =>  $localdir,
        port     =>  $port,
        active   =>  $active,
        stats    =>  $stats,
        recursive => $recursive,
        debug    =>  $debug,
        binary   =>  $binary,
        keep     =>  $keep,
        ospath   =>  $ospath,
        exclude  =>  \@exclude,
        statistics => \%statistics,
        delftp   =>  $delete_source,
        dir      =>  $dir,
        hardlink =>  $hardlink,
        enc      =>  $encrypt
    );#}}}
    $config{"localdir"}=glob($config{"localdir"});

    # Determine password for ftp-connection
    if ((!defined($config{'pass'})) or ($config{'pass'} eq "")) {#{{{
        ReadMode('noecho');
        print "No Password has been given, \nplease type password for user $config{'user'}: ";
        chomp($config{'password'} = ReadLine(0));
        print "\n";
        ReadMode('restore');
    }#}}}

    if (defined($passfile) and (not $config{'enc'} )){
        vprint("You specified a passwordfile, but did not enable encryption.
Ignoring --passfile. You probably want the --encrypt switch.", "warn");
    }
    # determine password fpr gpg encryption
    if ($config{'enc'}){
        use GnuPG;
        $config{'epasswd'} = GPGdetPassphrase($passfile);
    }
    if ($config{'hardlink'}){
        use File::Rsync;
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
#   no strict "subs";
    my $file = shift;
    my $gpg = new GnuPG();
    my $password = $config{'epasswd'};
    vprint("encrypting $file using provided password","debug");
    return undef unless defined($gpg->encrypt(plaintext => $file, output => $file.".gpg", passphrase => $password, symmetric => 1));
    unlink $file;
    return 1;
}#}}}

sub GPGdetPassphrase{#{{{
        my $passfile = shift;
        my $try=0;
        my $passphrase, my $temp1;
        if (defined($passfile)) {
            open(PASS, "<$passfile") or die "[error]: Cannot open specified password file\n";
            while (<PASS>) {
                $passphrase .= $_;
            }
        }
        else {
            do {
                print "\nPlease try again, both passphrase did NOT match!\n" if ($try > 0);
                $try++;
                ReadMode('noecho');
                print "\nEnter Password for encryption:";
                $passphrase = ReadLine(0);
                print "\nRe-enter Password for encryption:";
                $temp1 = ReadLine(0);
                die "Could not reliably determine which password to use for encryption" if ($try >= 3);
            }
        until ($passphrase eq $temp1);
        print "\n";
    }
    chomp $passphrase;
return $passphrase;
}#}}}

sub RsyncBackupDirs{#{{{
    # src, hardlink_src, destination
    (my $src, my $dest, my $lsrc) = @_;
    # archive sets some defaults, but for reference we include all options.
    # see rsync(1)
    # --archive sets:
    #   --recursive (-r) # recursive call
    #   --links (-l)     # copy symlinks
    #   --perms (-p)     # preserve permissions
    #   --times (-t)     # preserve modification time
    #   --group (-g)     # preserve group
    #   --owner (-o)     # preserve owner
    #   --devices        # copy devices
    #   --specials       # copy special files
    # --hard-links       # preserve hard-links
    # --acls             # preserve ACLs        (probably not needed for ftp)
    # --xattrs           # prexerve extended attributes (probably not needed for ftp)
    # --sparse           # handle sparse files efficiently
    # --link-dest        # hardlink files with $dir
    no strict "subs";
    my $rsync = File::Rsync->new({ "archive" => 1, "hard-links" => 1, "sparse" => 1, "src" => $src.$config{'ospath'}, "dest" => $dest.$config{'ospath'}});
	if (defined($lsrc)){
		vprint("Trying to hardlink files with $lsrc", "debug");
		$rsync->defopts({"link-dest" => $lsrc.$config{'ospath'}});
	}
    my $cmd = $rsync->getcmd();
    foreach (@$cmd) {
        print "$_\n";
    }
    #$rsync->exec({ src => $src, dest => $dest}) or print "[error] Rsync call failed, aborting ...\n";
    $rsync->exec or print "[error] Rsync call failed, aborting ...\n";
    my $status = $rsync->status;
    return 1;
}#}}}

sub parseCmdline{#{{{
	# sane defaults, if everthing fails, these will be used
	my $user         = "anonymous";
	my $pass         = 'none@none.invalid';
	# Welches Directory downloaden
	my $dir          = ".";

	my $uri = shift(@_);
	if (!defined($uri) or $uri eq "") {
		die "[error] No Server specified, nothing to do, exiting....\n";
	}
	my $user1, my $host, my $pass1, my $dir1;
	# now we have 4 fields: 1: ftp://
	#                       2: <null>
	#                       3: server (possibly including user and password information)
	#                       4: directory
	my @a_uri    = split /\//,$uri, 4;
	( $user1,  $pass1,  $host) = ( $a_uri[2]  =~ /(?:([^:@]*)(?::([^@]*))?@)?(.*)/);
	if ((defined($a_uri[3]) and not ($a_uri[3] eq  ""))){
		 $dir1         = $a_uri[3];
	}
    if ((!defined($pass1)) && defined($user1) && ($user1 ne $user)  ) {#{{{
        ReadMode('noecho');
        print "No Password has been given, \nplease type password for user $user1: ";
        chomp($pass1 = ReadLine(0));
        print "\n";
        ReadMode('restore');
    }#}}}
	($user, $pass, $dir) = 	(defined($user1)?$user1:$user, 
							 defined($pass1)?$pass1:$pass,
							 defined($dir1)?$dir1:$dir);
	return  ($user, $pass, $host, $dir);
}#}}}



# vim: set fdm=marker fdl=0:
