#!/usr/bin/perl
use strict;
use warnings;

my %thr = ();
my $threading_ok = eval 'use threads; 1';
if ($threading_ok)
{
        use threads;
        use threads::shared;
}

my $MAX_THREADS = 7;

use IO::Socket::SSL;
my $FURL_OK = eval 'use Furl; 1';
if (!$FURL_OK)
{
	warn("Furl not found, falling back to LWP for fetching URLs (this will be slow)...\n");
	use LWP::UserAgent;
}

use JSON;
use JSON::Parse 'valid_json';
use XML::Simple;
use DateTime;
use Getopt::Long;
use XML::Writer;
use URI;
use URI::Escape;
use Thread::Queue;
use Fcntl qw(:DEFAULT :flock);
use File::Copy;
use Clone qw( clone );
use Cwd qw( getcwd );
use HTML::TableExtract;
use DB_File;

my %map = (
	 '&' => 'and',
);
my $chars = join '', keys %map;

my %DUPLICATE_CHANNELS = ();
my @DUPLICATED_CHANNELS = ();
my @dupes;
my @CHANNELDATA;
my @DUPECHANDATA;
my @DUPEGUIDEDATA;
my $FVICONS;
my $DVBTRIPLET;
my @GUIDEDATA;
my $FVCACHEFILE = "fv.db";
my $FVTMPCACHEFILE = ".$$.freeview-tmp-cache.db";
my $CACHEFILE = "yourtv.db";
my $CACHETIME = 86400; # 1 day - don't change this unless you know what you are doing.
my $TMPCACHEFILE = ".$$.yourtv-tmp-cache.db";
my $ua;
my $DUPES_COUNT = 0;
my $STDOLD;
my (%dbm_hash, %thrdret);
my (%fvdbm_hash, %fvthrdret);
local (*DBMRO, *DBMRW);

my ($DEBUG, $VERBOSE, $logdir, $pretty, $USEFREEVIEWICONS, $NUMDAYS, $ignorechannels, $includechannels, $extrachannels, $REGION, $outputfile, $message, $help) = (0, 0, undef, 0, 0, 7, undef, undef, undef, undef, undef ,undef, undef);
GetOptions
(
	'debug'		=> \$DEBUG,
	'verbose'	=> \$VERBOSE,
	'logdir=s'	=> \$logdir,
	'pretty'	=> \$pretty,
	'days=i'	=> \$NUMDAYS,
	'region=s'	=> \$REGION,
	'output=s'	=> \$outputfile,
	'ignore=s'	=> \$ignorechannels,
	'include=s'	=> \$includechannels,
	'fvicons'	=> \$USEFREEVIEWICONS,
	'cachefile=s'	=> \$CACHEFILE,
	'fvcachefile=s'	=> \$FVCACHEFILE,
	'cachetime=i'	=> \$CACHETIME,
	'extrachannels=s'	=> \$extrachannels,
	'duplicates=s'	=> \@dupes,
	'message=s'	=> \$message,
	'help|?'	=> \$help,
) or die ("Syntax Error!  Try $0 --help");

my %ABCRADIO;
$ABCRADIO{"200"}{name}			= "Double J";
$ABCRADIO{"200"}{iconurl}		= "https://www.abc.net.au/cm/lb/8811932/thumbnail/station-logo-thumbnail.jpg";
$ABCRADIO{"200"}{servicename}	= "doublej";
$ABCRADIO{"201"}{name}  		= "ABC Jazz";
$ABCRADIO{"201"}{iconurl}		= "https://www.abc.net.au/cm/lb/8785730/thumbnail/station-logo-thumbnail.png";
$ABCRADIO{"201"}{servicename} 	= "jazz";
$ABCRADIO{"202"}{name}			= "ABC Kids Listen";
$ABCRADIO{"202"}{iconurl}		= "https://d24j9r7lck9cin.cloudfront.net/l/o/7/7118.1519190192.png";
$ABCRADIO{"202"}{servicename}	= "kidslisten";
$ABCRADIO{"203"}{name}			= "ABC Country";
$ABCRADIO{"203"}{iconurl}		= "https://www.abc.net.au/radio/images/service/2018/country_480.png";
$ABCRADIO{"203"}{servicename}	= "";
$ABCRADIO{"204"}{name}			= "ABC News Radio";
$ABCRADIO{"204"}{iconurl}		= "https://upload.wikimedia.org/wikipedia/commons/e/ee/ABC_News_Radio_2014.png";
$ABCRADIO{"204"}{servicename}	= "";

$ABCRADIO{"26"}{name}			= "ABC Radio National";
$ABCRADIO{"26"}{iconurl}		= "https://www.abc.net.au/news/image/8054480-3x2-940x627.jpg";
$ABCRADIO{"26"}{servicename}	= "RN";
$ABCRADIO{"27"}{name}			= "ABC Classic";
$ABCRADIO{"27"}{iconurl}		= "https://www.abc.net.au/cm/lb/9104270/thumbnail/station-logo-thumbnail.png";
$ABCRADIO{"27"}{servicename}	= "classic";
$ABCRADIO{"28"}{name}  			= "Triple J";
$ABCRADIO{"28"}{iconurl} 		= "https://www.abc.net.au/cm/lb/8541768/thumbnail/station-logo-thumbnail.png";
$ABCRADIO{"28"}{servicename}	= "triplej";
$ABCRADIO{"29"}{name}  			= "Triple J Unearthed";
$ABCRADIO{"29"}{iconurl} 		= "https://www.abc.net.au/cm/rimage/8869368-16x9-large.jpg?v=2";
$ABCRADIO{"29"}{servicename}	= "";

my %SBSRADIO;
$SBSRADIO{"36"}{name}   = "SBS Arabic24";
$SBSRADIO{"36"}{iconurl}        = "http://d6ksarnvtkr11.cloudfront.net/resources/sbs/radio/images/headerlogo_sbsarabic24_300_colour.png";
$SBSRADIO{"36"}{servicename}    = "poparaby";
$SBSRADIO{"37"}{name}   = "SBS Radio 1";
$SBSRADIO{"37"}{iconurl}        = "http://d6ksarnvtkr11.cloudfront.net/resources/sbs/radio/images/headerlogo_sbs1_300_colour.png";
$SBSRADIO{"37"}{servicename}    = "sbs1";
$SBSRADIO{"38"}{name}   = "SBS Radio 2";
$SBSRADIO{"38"}{iconurl}        = "http://d6ksarnvtkr11.cloudfront.net/resources/sbs/radio/images/headerlogo_sbs2_300_colour.png";
$SBSRADIO{"38"}{servicename}    = "sbs2";
$SBSRADIO{"39"}{name}   = "SBS Chill";
$SBSRADIO{"39"}{iconurl}        = "http://d6ksarnvtkr11.cloudfront.net/resources/sbs/radio/images/header_chill_300_colour.png";
$SBSRADIO{"39"}{servicename}    = "chill";

$SBSRADIO{"301"}{name}  = "SBS Radio 1";
$SBSRADIO{"301"}{iconurl}       = "http://d6ksarnvtkr11.cloudfront.net/resources/sbs/radio/images/headerlogo_sbs1_300_colour.png";
$SBSRADIO{"301"}{servicename}   = "sbs1";

$SBSRADIO{"302"}{name}  = "SBS Radio 2";
$SBSRADIO{"302"}{iconurl}       = "http://d6ksarnvtkr11.cloudfront.net/resources/sbs/radio/images/headerlogo_sbs2_300_colour.png";
$SBSRADIO{"302"}{servicename}   = "sbs2";

$SBSRADIO{"303"}{name}  = "SBS Radio 3";
$SBSRADIO{"303"}{iconurl}       = "http://d6ksarnvtkr11.cloudfront.net/resources/sbs/radio/images/headerlogo_sbs3_300_colour.png";
$SBSRADIO{"303"}{servicename}   = "sbs3";

$SBSRADIO{"304"}{name}  = "SBS Arabic24";
$SBSRADIO{"304"}{iconurl}       = "http://d6ksarnvtkr11.cloudfront.net/resources/sbs/radio/images/headerlogo_sbsarabic24_300_colour.png";
$SBSRADIO{"304"}{servicename}   = "poparaby";

$SBSRADIO{"305"}{name}  = "SBS PopDesi";
$SBSRADIO{"305"}{iconurl}       = "http://d6ksarnvtkr11.cloudfront.net/resources/sbs/radio/images/header_popdesi_300_colour.png";
$SBSRADIO{"305"}{servicename}   = "popdesi";

$SBSRADIO{"306"}{name}  = "SBS Chill";
$SBSRADIO{"306"}{iconurl}       = "http://d6ksarnvtkr11.cloudfront.net/resources/sbs/radio/images/header_chill_300_colour.png";
$SBSRADIO{"306"}{servicename}   = "chill";

$SBSRADIO{"307"}{name}  = "SBS PopAsia";
$SBSRADIO{"307"}{iconurl}       = "http://d6ksarnvtkr11.cloudfront.net/resources/sbs/radio/images/header_popasia_300_colour.png";
$SBSRADIO{"307"}{servicename}   = "popasia";

get_duplicate_channels(@dupes) if (@dupes and scalar @dupes);

if ($FURL_OK)
{
	warn("Using Furl for fetching http:// and https:// requests.\n") if ($VERBOSE);
	$ua = Furl->new(
				agent => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:67.0) Gecko/20100101 Firefox/67.0',
				timeout => 30,
				headers => [ 'Accept-Encoding' => 'application/json' ],
				ssl_opts => {SSL_verify_mode => 0}
			);
} else {
	warn("Using LWP::UserAgent for fetching http:// and https:// requests.\n") if ($VERBOSE);
	$ua = LWP::UserAgent->new;
	$ua->agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:67.0) Gecko/20100101 Firefox/67.0");
	$ua->default_header( 'Accept-Encoding' => 'application/json');
	$ua->default_header( 'Accept-Charset' => 'utf-8');
}
die usage() if ($help || !defined($REGION));

$CACHEFILE = "yourtv-region_$REGION.db" if ($CACHEFILE eq "yourtv.db");

my $validregion = 0;
my @REGIONS = buildregions();
for my $tmpregion ( @REGIONS )
{
	if ($tmpregion->{id} eq $REGION) {
        $validregion = 1;
		define_ABC_local_radio($tmpregion->{state});
	}
}
die(	  "\n"
	. "Invalid region specified.  Please use one of the following:\n\t\t"
	. join("\n\t\t", (map { "$_->{id}\t=\t$_->{name}" } @REGIONS) )
	. "\n\n"
   ) if (!$validregion); # (!defined($REGIONS->{$REGION}));

if (defined($logdir))
{
    $logdir =~ s/\/?$/\//;
	my $logfile = $logdir.$REGION.".log"; 
	open (my $LOG, '>', $logfile)  || die "can't open $logfile.  Does $logdir exist?";
	open (STDERR, ">>&=", $LOG)         || die "can't redirect STDERR";
	select $LOG;
}

warn("Options...\nregion=$REGION, output=$outputfile, days = $NUMDAYS, fvicons = $USEFREEVIEWICONS, Verbose = $VERBOSE, pretty = $pretty, \n\n") if ($VERBOSE);

# Initialise here (connections to the same server will be cached)
my @IGNORECHANNELS;
@IGNORECHANNELS = split(/,/,$ignorechannels) if (defined($ignorechannels));
my @INCLUDECHANNELS;
@INCLUDECHANNELS = split(/,/,$includechannels) if (defined($includechannels));

warn("ignored channels: @IGNORECHANNELS \n\n") if ($VERBOSE);

getFVInfo($ua);

warn("Initializing queues...\n") if ($VERBOSE);
my $INQ = Thread::Queue->new();
my $OUTQ = Thread::Queue->new();

warn("Initializing $MAX_THREADS worker threads...\n") if ($VERBOSE);

for (1 .. $MAX_THREADS)
{
	threads->create( \&url_fetch_thread )->detach();
	warn("Started thread $_...\n") if ($DEBUG);
}

warn("My current directory for cachefiles is: " . getcwd . "\n") if ($VERBOSE);
if (! -e $FVCACHEFILE)
{
	warn("Freeview cache file not present/readable, this run will be slower than normal...\n");
	# Create a new and empty file so this doesn't fail
	tie %fvdbm_hash, "DB_File", $FVCACHEFILE, O_CREAT | O_RDWR, 0644 or
		die("Cannot write to $FVCACHEFILE");
	untie %fvdbm_hash;
}

warn("Opening Freeview cache files...\n") if ($VERBOSE);
my $fvdbro = tie %fvdbm_hash, "DB_File", $FVCACHEFILE, O_RDONLY, 0644 or
		die("Cannot open $FVCACHEFILE");
my $fvfdro = $fvdbro->fd;							# get file desc
open FVDBMRO, "+<&=$fvfdro" or die "Could not dup DBMRO for lock: $!";	# Get dup filehandle
flock FVDBMRO, LOCK_EX;							# Lock it exclusively
undef $fvdbro;

my $fvdbrw = tie %fvthrdret,  "DB_File", $FVTMPCACHEFILE, O_CREAT | O_RDWR, 0644 or
		die("Cannot write to $FVTMPCACHEFILE");
my $fvfdrw = $fvdbrw->fd;							# get file desc
open FVDBMRW, "+<&=$fvfdrw" or die "Could not dup DBMRW for lock: $!";	# Get dup filehandle
flock FVDBMRW, LOCK_EX;							# Lock it exclusively
undef $fvdbrw;

if (! -e $CACHEFILE)
{
	warn("Cache file not present/readable, this run will be slower than normal...\n");
	# Create a new and empty file so this doesn't fail
	tie %dbm_hash, "DB_File", $CACHEFILE, O_CREAT | O_RDWR, 0644 or
		die("Cannot write to $CACHEFILE");
	untie %dbm_hash;
}

# catch die handler
$SIG{__DIE__} = \&close_cache_and_die;

# WARNING: This has to be done *AFTER* opening threads or thread closure
# segfault the interpreter because of double free()s
warn("Opening Cache files...\n") if ($VERBOSE);
my $dbro = tie %dbm_hash, "DB_File", $CACHEFILE, O_RDONLY, 0644 or
		die("Cannot open $CACHEFILE");
my $fdro = $dbro->fd;							# get file desc
open DBMRO, "+<&=$fdro" or die "Could not dup DBMRO for lock: $!";	# Get dup filehandle
flock DBMRO, LOCK_EX;							# Lock it exclusively
undef $dbro;

my $dbrw = tie %thrdret,  "DB_File", $TMPCACHEFILE, O_CREAT | O_RDWR, 0644 or
		die("Cannot write to $TMPCACHEFILE");
my $fdrw = $dbrw->fd;							# get file desc
open DBMRW, "+<&=$fdrw" or die "Could not dup DBMRW for lock: $!";	# Get dup filehandle
flock DBMRW, LOCK_EX;							# Lock it exclusively
undef $dbrw;

warn("Getting Channel list...\n") if ($VERBOSE);
push(@CHANNELDATA,getchannels($ua, $REGION));
push(@CHANNELDATA,SBSgetchannels());
push(@CHANNELDATA,ABCgetchannels());

warn("Getting EPG data...\n") if ($VERBOSE);
push(@GUIDEDATA,getepg($ua, $REGION));
push(@GUIDEDATA,ABCgetepg($ua));
push(@GUIDEDATA,SBSgetepg($ua));

warn("\nGetting extra channel and EPG data...\n\n") if ($VERBOSE);
if (defined ($extrachannels))
{
	die("--extrachannel option in wrong format. It should be <other region>-<channel number>,<channel number>,etc") if ($extrachannels !~ /(\d+)-.*/);
	my ($extraregion, $extrachannel) = $extrachannels =~ /(\d+)-(.*)/;
	my @channel_array = split(/,/,$extrachannel);
	push(@CHANNELDATA,getchannels($ua, $extraregion, @channel_array));
	push(@GUIDEDATA,getepg($ua, $extraregion, @channel_array));
}
warn("Closing Queues...\n") if ($VERBOSE);
# this will close the queues
$INQ->end();
$OUTQ->end();
# joining all threads

warn("Shutting down all threads...\n") if ($VERBOSE);
warn("Closing Cache files.\n") if ($VERBOSE);
# close out both DBs and write the new temp one over the saved one

&close_cache();

# reset die handler
$SIG{__DIE__} = \&CORE::die;

warn("Replacing old Cache file with the new one...\n") if ($VERBOSE);
move($TMPCACHEFILE, $CACHEFILE);
move($FVTMPCACHEFILE, $FVCACHEFILE);

warn("Starting to build the XML...\n") if ($VERBOSE);
if (defined($message))
{
	$message = "http://xmltv.net - ".$message;
}
else {
	$message = "http://xmltv.net";
}

my $XML = XML::Writer->new( OUTPUT => 'self', DATA_MODE => ($pretty ? 1 : 0), DATA_INDENT => ($pretty ? 8 : 0) );
$XML->xmlDecl("UTF-8");
$XML->doctype("tv", undef, "xmltv.dtd");
$XML->startTag('tv', 'source-info-name' => $message, 'generator-info-url' => "http://www.xmltv.org/");

warn("Building the channel list...\n") if ($VERBOSE);
printchannels(\$XML);
warn("Building the EPG list...\n") if ($VERBOSE);
printepg(\$XML);
warn("Finishing the XML...\n") if ($VERBOSE);
$XML->endTag('tv');

if (!defined $outputfile)
{
	warn("Finished! xmltv guide follows...\n\n") if ($VERBOSE);
	print $XML;
	print "\n" if ($pretty); # XML won't add a trailing newline
} else {
	warn("Writing xmltv guide to $outputfile...\n") if ($VERBOSE);
	open FILE, ">$outputfile" or die("Unable to open $outputfile file for writing: $!\n");
	print FILE $XML;
	close FILE;
	warn("Done!\n") if ($VERBOSE);
}

exit(0);

sub close_cache_and_die
{
	warn($_[0]);
	&close_cache;
	unlink $TMPCACHEFILE;
	unlink $FVTMPCACHEFILE;
	exit(1);
}

sub close_cache
{
	untie(%dbm_hash);
	untie(%thrdret);
	untie(%fvdbm_hash);
	untie(%fvthrdret);
	close DBMRW;
	close DBMRO;
	close FVDBMRW;
	close FVDBMRO;
}

sub url_fetch_thread
{
	local $| = 1;
	my $tua;
	if ($FURL_OK)
	{
		$tua = Furl->new(
					agent => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:67.0) Gecko/20100101 Firefox/67.0',
					timeout => 30,
					headers => [ 'Accept-Encoding' => 'application/json' ],
					ssl_opts => {SSL_verify_mode => 0}
				);
	} else {
		$tua = LWP::UserAgent->new;
		$tua->agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:67.0) Gecko/20100101 Firefox/67.0");
		$tua->default_header('Accept-Encoding' => 'application/json');
		$tua->default_header('Accept-Charset' => 'utf-8');
	}
	while (defined( my $airingid = $INQ->dequeue()))
	{
		my $url = "https://www.yourtv.com.au/api/airings/" . $airingid;
		warn("Using $tua to fetch $url\n") if ($DEBUG);
		print "." if ($VERBOSE);
		my $res = $tua->get($url);
		if (!$res->is_success)
		{
			warn(threads->self()->tid(). ": Thread Fetch FAILED for: $url (" . $res->code . ")\n");
			if ($res->code > 399 and $res->code < 500)
			{
				$OUTQ->enqueue("$airingid|FAILED");
			} elsif ($res->code > 499) {
				$OUTQ->enqueue("$airingid|ERROR");
			} else {
				# shouldn't be reached
				$OUTQ->enqueue("$airingid|UNKNOWN")
			}
		} else {
			$OUTQ->enqueue($airingid . "|" . $res->content);
			warn(threads->self()->tid(). ": Thread Fetch SUCCESS for: $url\n") if ($DEBUG);
		}
	}
}

sub getchannels
{
	#my $ua = shift;
	my ($ua, $region, @extrachannels) = @_;
	my @channeldata;
	warn("Getting channel list from YourTV ...\n") if ($VERBOSE);
	my $url = "https://www.yourtv.com.au/api/regions/" . $region . "/channels";
	my $res = $ua->get($url);
	warn("Getting channel list from YourTV ... ( $url )\n") if ($VERBOSE);
	my $tmpchanneldata;
	die("Unable to connect to FreeView.\n") if (!$res->is_success);
	$tmpchanneldata = JSON->new->relaxed(1)->allow_nonref(1)->decode($res->content);
	my $dupe_count = 0;
	my $channelcount = 0;

	for (my $count = 0; $count < @$tmpchanneldata; $count++)
	{
		next if ( ( grep( /^$tmpchanneldata->[$count]->{number}$/, @IGNORECHANNELS ) ) );
		next if ( ( !( grep( /^$tmpchanneldata->[$count]->{number}$/, @INCLUDECHANNELS ) ) ) and ((@INCLUDECHANNELS > 0)));
		next if ( ( !( grep( /^$tmpchanneldata->[$count]->{number}$/, @extrachannels ) ) ) and ((@extrachannels > 0)));

		my $channelIsDuped = 0;
		++$channelIsDuped if ( ( grep( /$tmpchanneldata->[$count]->{number}$/, @DUPLICATED_CHANNELS ) ) );
		#$channeldata[$channelcount]->{tv_id} = $tmpchanneldata->[$count]->{id};
		$channeldata[$channelcount]->{name} = $tmpchanneldata->[$count]->{description};
		$channeldata[$channelcount]->{id} = $tmpchanneldata->[$count]->{number}.".yourtv.com.au";
		$channeldata[$channelcount]->{lcn} = $tmpchanneldata->[$count]->{number};
		if (defined($tmpchanneldata->[$count]->{logo}->{url}))
		{
			$channeldata[$channelcount]->{icon} = $tmpchanneldata->[$count]->{logo}->{url};
			$channeldata[$channelcount]->{icon} =~ s/.*(https.*?amazon.*)/$1/;
			$channeldata[$channelcount]->{icon} = uri_unescape($channeldata[$channelcount]->{icon});
		}
		$channeldata[$channelcount]->{icon} = $FVICONS->{$tmpchanneldata->[$count]->{number}} if (defined($FVICONS->{$tmpchanneldata->[$count]->{number}}));
		#FIX SBS ICONS
		if (($USEFREEVIEWICONS) && (!defined($channeldata[$channelcount]->{icon})) && ($channeldata[$channelcount]->{name} =~ /SBS/))
		{
			$tmpchanneldata->[$channelcount]->{number} =~ s/(\d)./$1/;
			$channeldata[$channelcount]->{icon} = $FVICONS->{$tmpchanneldata->[$count]->{number}} if (defined($FVICONS->{$tmpchanneldata->[$count]->{number}}));
		}

		warn("Got channel $channeldata[$channelcount]->{id} - $channeldata[$channelcount]->{name} ...\n") if ($VERBOSE);
		if ($channelIsDuped)
		{
			foreach my $dchan (sort keys %DUPLICATE_CHANNELS)
			{
				next if ($DUPLICATE_CHANNELS{$dchan} ne $tmpchanneldata->[$count]->{number});
				$DUPECHANDATA[$dupe_count]->{tv_id} = $channeldata[$count]->{tv_id};
				$DUPECHANDATA[$dupe_count]->{name} = $channeldata[$count]->{name};
				$DUPECHANDATA[$dupe_count]->{id} = $dchan . ".yourtv.com.au";
				$DUPECHANDATA[$dupe_count]->{lcn} = $dchan;
				$DUPECHANDATA[$dupe_count]->{icon} = $channeldata[$count]->{icon};
				warn("Duplicated channel $channeldata[$count]->{name} -> $DUPECHANDATA[$dupe_count]->{id} ...\n") if ($VERBOSE);
				++$dupe_count;
			}
		}
		$channelcount++;
	}
	return @channeldata;
}

sub getepg
{
	#my $ua = shift;
	my ($ua, $region, @extrachannels) = @_;
	my $showcount = 0;
	my $dupe_scount = 0;
	my $url;
	my @guidedata;
	my $region_timezone;
	my $region_name;

	for my $tmpregion ( @REGIONS )
	{
		if ($tmpregion->{id} eq $region) {
        	$region_timezone = $tmpregion->{timezone};
    	    $region_name = $tmpregion->{name};
		}
	}

	warn(" \n") if ($VERBOSE);
	my $nl = 0;
	for(my $day = 0; $day < $NUMDAYS; $day++)
	{
		my $day = nextday($day);
		my $id;
		my $url = URI->new( 'https://www.yourtv.com.au/api/guide/' );
		$url->query_form(day => $day, timezone => $region_timezone, format => 'json', region => $region);
		warn(($nl ? "\n" : "" ) . "Getting channel program listing for $region_name ($region) for $day ($url)...\n") if ($VERBOSE);
		$nl = 0;
		my $res = $ua->get($url);
		die("Unable to connect to YourTV for $url.\n") if (!$res->is_success);
		my $tmpdata;
		eval
		{
			$tmpdata = JSON->new->relaxed(1)->allow_nonref(1)->decode($res->content);
			1;
		};
		my $chandata = $tmpdata->[0]->{channels};
		if (defined($chandata))
		{
			for (my $channelcount = 0; $channelcount < @$chandata; $channelcount++)
			{
				next if (!defined($chandata->[$channelcount]->{number}));
				next if ( ( grep( /^$chandata->[$channelcount]->{number}$/, @IGNORECHANNELS ) ) );
				next if ( ( !( grep( /^$chandata->[$channelcount]->{number}$/, @INCLUDECHANNELS ) ) ) and ((@INCLUDECHANNELS > 0)));
				next if ( ( !( grep( /^$chandata->[$channelcount]->{number}$/, @extrachannels ) ) ) and ((@extrachannels > 0)));
				#if (defined($extrachannel))
				#{
				#	next if ($chandata->[$channelcount]->{number} ne $extrachannel);
				#}
				my $channelIsDuped = 0;
				$channelIsDuped = $chandata->[$channelcount]->{number} if ( ( grep( /^$chandata->[$channelcount]->{number}$/, @DUPLICATED_CHANNELS ) ) );

				my $enqueued = 0;
				$id = $chandata->[$channelcount]->{number}.".yourtv.com.au";
				my $blocks = $chandata->[$channelcount]->{blocks};
				for (my $blockcount = 0; $blockcount < @$blocks; $blockcount++)
				{
					my $subblocks = $blocks->[$blockcount]->{shows};
					for (my $airingcount = 0; $airingcount < @$subblocks; $airingcount++)
					{
						warn("Starting... ($blockcount < " . scalar @$blocks . "| $airingcount < " . scalar @$subblocks . ")\n") if ($DEBUG);
						my $airing = $subblocks->[$airingcount]->{id};
						warn("Starting $airing...\n") if ($DEBUG);
						# We don't use the cache for 'today' incase of any last minute programming changes
						#
						# but if cachetime is set, work out if we use the cache or not. (Advanced users only)
						if (!exists $dbm_hash{$airing} || $dbm_hash{$airing} eq "$airing|undef")
						{
							warn("No cache data for $airing, requesting...\n") if ($DEBUG);
							$INQ->enqueue($airing);
							++$enqueued; # Keep track of how many fetches we do
						} else {
							my $usecache = 1; # default is to use the cache
							$usecache = 0 if ($CACHETIME eq 86400 && ($day eq "today" || $day eq "tomorrow")); # anything today is not cached if default cachetime
							if ($usecache && $CACHETIME ne 86400)
							{
								if ($day eq "today" || $day eq "tomorrow")
								{
									# CACHETIME is non default so more complicated
									# so we just need to know if the airing is within our cachetime
									# however at this level the aring has just things like "5:30 AM" or "6:00 PM"
									# so we need to do some conversions
									my $offset = getTimeOffset($region_timezone, $subblocks->[$airingcount]->{date}, $day);
									warn("Checking $offset against $CACHETIME\n") if ($DEBUG);
									$usecache = 0 if (abs($offset) eq $offset && $CACHETIME > $offset);
								}
							}
							if (!$usecache)
							{
								warn("Cache Data is within the last $CACHETIME seconds, ignoring cache data for $airing, requesting...[" . $subblocks->[$airingcount]->{date} . "]\n") if ($DEBUG);
								$INQ->enqueue($airing);
								++$enqueued; # Keep track of how many fetches we do
							} else {
								# we can use the cache...
								warn("Using cache for $airing.\n") if ($DEBUG && $day eq "today");
								my $data = $dbm_hash{$airing};
								warn("Got cache data for $airing.\n") if ($DEBUG);
								$thrdret{$airing} = $data;
								warn("Wrote cache data for $airing.\n") if ($DEBUG);
							}
						}
						warn("Done $airing...\n") if ($DEBUG);
					}
				}
				for (my $l = 0;$l < $enqueued; ++$l)
				{
					# At this point all the threads should have all the URLs in the queue and
					# will resolve them independently - this means they will not necessarily
					# be in the right order when we get them back.  That said, because we will
					# reuse these threads and queues on each loop we wait here to get back
					# all the results before we continue.
					my ($airing, $result) = split(/\|/, $OUTQ->dequeue(), 2);
					warn("$airing = $result\n") if ($DEBUG);
					$thrdret{$airing} = $result;
				}
				if ($VERBOSE && $enqueued)
				{
					local $| = 1;
					print " ";
					$nl++;
				}
				for (my $blockcount = 0; $blockcount < @$blocks; $blockcount++)
				{
					my $subblocks = $blocks->[$blockcount]->{shows};
					#for (my $airingcount = 0; $airingcount < @$subblocks; $airingcount++)
					#{
					#	my ($airing, $result) = split(/\|/, $OUTQ->dequeue(), 2);
					#	warn("$airing = $result\n") if ($DEBUG);
					#	$thrdret{$airing} = $result;
					#}
					# Here we will have all the returned data in the hash %thrdret with the
					# url as the key.
					for (my $airingcount = 0; $airingcount < @$subblocks; $airingcount++)
					{
						my $showdata;
						my $airing = $subblocks->[$airingcount]->{id};
						if ($thrdret{$airing} eq "FAILED")
						{
							warn("Unable to connect to YourTV for https://www.yourtv.com.au/api/airings/$airing ... skipping\n");
							next;
						} elsif ($thrdret{$airing} eq "ERROR") {
							die("FATAL: Unable to connect to YourTV for https://www.yourtv.com.au/api/airings/$airing ... (error code >= 500 have you need banned?)\n");
						} elsif ($thrdret{$airing} eq "UNKNOWN") {
							die("FATAL: Unable to connect to YourTV for https://www.yourtv.com.au/api/airings/$airing ... (Unknown Error!)\n");
						}
						eval
						{
							$showdata = JSON->new->relaxed(1)->allow_nonref(1)->decode($thrdret{$airing});
							1;
						};
						if (defined($showdata))
						{
							$guidedata[$showcount]->{id} = $id;
							$guidedata[$showcount]->{airing_tmp} = $airing;
							$guidedata[$showcount]->{desc} = $showdata->{synopsis};
							$guidedata[$showcount]->{subtitle} = $showdata->{episodeTitle};
							$guidedata[$showcount]->{start} = toLocalTimeString($showdata->{date},$region_timezone);
							$guidedata[$showcount]->{stop} = addTime($showdata->{duration},$guidedata[$showcount]->{start});
							$guidedata[$showcount]->{start} =~ s/[-T:]//g;
							$guidedata[$showcount]->{start} =~ s/\+/ \+/g;
							$guidedata[$showcount]->{stop} =~ s/[-T:]//g;
							$guidedata[$showcount]->{stop} =~ s/\+/ \+/g;
							$guidedata[$showcount]->{channel} = $showdata->{service}->{description};
							$guidedata[$showcount]->{title} = $showdata->{title};
							$guidedata[$showcount]->{rating} = $showdata->{classification};
							if (defined($showdata->{program}->{image}))
							{
								$guidedata[$showcount]->{url} = $showdata->{program}->{image};
							}
							else
							{
								$guidedata[$showcount]->{url} = getFVShowIcon($chandata->[$channelcount]->{number},$guidedata[$showcount]->{title},$guidedata[$showcount]->{start},$guidedata[$showcount]->{stop});
							}
							push(@{$guidedata[$showcount]->{category}}, $showdata->{genre}->{name});
							push(@{$guidedata[$showcount]->{category}}, $showdata->{subGenre}->{name}) if (defined($showdata->{subGenre}->{name}));
							#	program types as defined by yourtv $showdata->{programType}->{id}
							#	1	 Television movie
							#	2	 Cinema movie
							#	3	 Mini series
							#	4	 Series no episodes
							#	5	 Series with episodes
							#   6    Serial
							#	8	 Limited series
							#	9	 Special
							my $tmpseries = toLocalTimeString($showdata->{date},$region_timezone);
							my ($episodeYear, $episodeMonth, $episodeDay, $episodeHour, $episodeMinute) = $tmpseries =~ /(\d+)-(\d+)-(\d+)T(\d+):(\d+).*/;#S$1E$2$3$4$5/;

							if (defined($showdata->{programType}->{id})) {
								my $programtype = $showdata->{programType}->{id};
								if ($programtype eq "1") {
									push(@{$guidedata[$showcount]->{category}}, $showdata->{programType}->{name});
								}
								elsif ($programtype eq "2") {
									push(@{$guidedata[$showcount]->{category}}, $showdata->{programType}->{name});
								}
								elsif ($programtype eq "3") {
									push(@{$guidedata[$showcount]->{category}}, $showdata->{programType}->{name});
									$guidedata[$showcount]->{episode} = $showdata->{episodeNumber} if (defined($showdata->{episodeNumber}));
									$guidedata[$showcount]->{season} = "1";
								}
								elsif ($programtype eq "4") {
									$guidedata[$showcount]->{premiere} = "1";
									$guidedata[$showcount]->{originalairdate} = $episodeYear."-".$episodeMonth."-".$episodeDay." ".$episodeHour.":".$episodeMinute.":00";#"$1-$2-$3 $4:$5:00";
									if (defined($showdata->{episodeNumber}))
									{
										$guidedata[$showcount]->{episode} = $showdata->{episodeNumber};
									}
									else
									{
										$guidedata[$showcount]->{episode} = sprintf("%0.2d%0.2d",$episodeMonth,$episodeDay);
									}
									if (defined($showdata->{seriesNumber})) {
										$guidedata[$showcount]->{season} = $showdata->{seriesNumber};
									}
									else
									{
										$guidedata[$showcount]->{season} = $episodeYear;
									}
								}
								elsif ($programtype eq "5")
								{
									if (defined($showdata->{seriesNumber})) {
										$guidedata[$showcount]->{season} = $showdata->{seriesNumber};
									}
									else
									{
										$guidedata[$showcount]->{season} = $episodeYear;
									}
									if (defined($showdata->{episodeNumber})) {
										$guidedata[$showcount]->{episode} = $showdata->{episodeNumber};
									}
									else
									{
										$guidedata[$showcount]->{episode} = sprintf("%0.2d%0.2d",$episodeMonth,$episodeDay);
									}
								}
								elsif ($programtype eq "6")
								{
									if (defined($showdata->{seriesNumber})) {
										$guidedata[$showcount]->{season} = $showdata->{seriesNumber};
									}
									else
									{
										$guidedata[$showcount]->{season} = $episodeYear;
									}
									if (defined($showdata->{episodeNumber})) {
										$guidedata[$showcount]->{episode} = $showdata->{episodeNumber};
									}
									else
									{
										$guidedata[$showcount]->{episode} = sprintf("%0.2d%0.2d",$episodeMonth,$episodeDay);
									}
								}
								elsif ($programtype eq "8")
								{
									if (defined($showdata->{seriesNumber})) {
										$guidedata[$showcount]->{season} = $showdata->{seriesNumber};
									}
									else
									{
										$guidedata[$showcount]->{season} = $episodeYear;
									}
									if (defined($showdata->{episodeNumber})) {
										$guidedata[$showcount]->{episode} = $showdata->{episodeNumber};
									}
									else
									{
										$guidedata[$showcount]->{episode} = sprintf("%0.2d%0.2d",$episodeMonth,$episodeDay);
									}
								}
								elsif ($programtype eq "9")
								{
									$guidedata[$showcount]->{season} = $episodeYear;
									$guidedata[$showcount]->{episode} = sprintf("%0.2d%0.2d",$episodeMonth,$episodeDay);
								}
							}
							if (defined($showdata->{repeat} ) )
							{
							#	$guidedata[$showcount]->{originalairdate} = $episodeYear."-".$episodeMonth."-".$episodeDay." ".$episodeHour.":".$episodeMinute.":00";#"$1-$2-$3 $4:$5:00";
								$guidedata[$showcount]->{previouslyshown} = 1; #"$episodeYear-$episodeMonth-$episodeDay";#"$1-$2-$3";
							}
							if (defined($showdata->{program}->{imdbId} ) )
							{
								$guidedata[$showcount]->{imdb} = $showdata->{program}->{imdbId};
							}
							if ($channelIsDuped)
							{
								foreach my $dchan (sort keys %DUPLICATE_CHANNELS)
								{
									next if ($DUPLICATE_CHANNELS{$dchan} ne $channelIsDuped);
									my $did = $dchan . ".yourtv.com.au";
									$DUPEGUIDEDATA[$DUPES_COUNT] = clone($guidedata[$showcount]);
									$DUPEGUIDEDATA[$DUPES_COUNT]->{id} = $did;
									$DUPEGUIDEDATA[$DUPES_COUNT]->{channel} = $did;
									warn("Duplicated guide data for show entry $showcount -> $DUPES_COUNT ($guidedata[$showcount] -> $DUPEGUIDEDATA[$DUPES_COUNT]) ...\n") if ($DEBUG);
									++$DUPES_COUNT;
								}
							}
							$showcount++;
						}
					}
				}
			}
		}
	}
	warn("Processed a total of $showcount shows ...\n") if ($VERBOSE);
	return @guidedata;
}

sub printchannels
{
	my ($XMLRef) = @_;
	foreach my $channel (@CHANNELDATA, @DUPECHANDATA)
	{
		$XML->startTag('channel', 'id' => $channel->{id});
		$XML->dataElement('display-name', $channel->{name});
		$XML->dataElement('lcn', $channel->{lcn});
		$XML->emptyTag('icon', 'src' => $channel->{icon}) if (defined($channel->{icon}));
		$XML->endTag('channel');
	}
	return;
}

sub printepg
{
	my ($XMLRef) = @_;
	foreach my $items (@GUIDEDATA, @DUPEGUIDEDATA)
	{
		my $movie = 0;
		my $originalairdate = "";

		${$XMLRef}->startTag('programme', 'start' => "$items->{start}", 'stop' => "$items->{stop}", 'channel' => "$items->{id}");
		${$XMLRef}->dataElement('title', sanitizeText($items->{title}));
		${$XMLRef}->dataElement('sub-title', sanitizeText($items->{subtitle})) if (defined($items->{subtitle}));
		${$XMLRef}->dataElement('desc', sanitizeText($items->{desc})) if (defined($items->{desc}));
		foreach my $category (@{$items->{category}}) {
			${$XMLRef}->dataElement('category', sanitizeText($category));
		}
		my $uri = $items->{url};
		if (defined $uri)
		{
			$uri =~ s/\s/\%20/g;
			${$XMLRef}->emptyTag('icon', 'src' => $uri);
		}
		if (defined($items->{season}) && defined($items->{episode}))
		{
			my $episodeseries = sprintf("S%0.2dE%0.2d",$items->{season}, $items->{episode});
			${$XMLRef}->dataElement('episode-num', $episodeseries, 'system' => 'SxxExx');
			my $series = $items->{season} - 1;
			my $episode = $items->{episode} - 1;
			$series = 0 if ($series < 0);
			$episode = 0 if ($episode < 0);
			$episodeseries = "$series.$episode.";
			${$XMLRef}->dataElement('episode-num', $episodeseries, 'system' => 'xmltv_ns') ;
		}
		if (defined($items->{imdb}))
		{
			${$XMLRef}->dataElement('episode-num', "title/tt".$items->{imdb}, 'system' => 'imdb.com');
		}
		${$XMLRef}->dataElement('episode-num', $items->{originalairdate}, 'system' => 'original-air-date') if (defined($items->{originalairdate}));
		${$XMLRef}->emptyTag('previously-shown') if (defined($items->{previouslyshown}));
		if (defined($items->{rating}))
		{
			${$XMLRef}->startTag('rating');
			${$XMLRef}->dataElement('value', $items->{rating});
			${$XMLRef}->endTag('rating');
		}
		${$XMLRef}->emptyTag('premiere', "") if (defined($items->{premiere}));
		${$XMLRef}->endTag('programme');
	}
}

sub sanitizeText
{
	my $t = shift;
	$t =~ s/([$chars])/$map{$1}/g;
	$t =~ s/[^\040-\176]/ /g;
	return $t;
}

sub toLocalTimeString
{
	my ($fulldate, $result_timezone) = @_;
	my ($year, $month, $day, $hour, $min, $sec, $offset) = $fulldate =~ /(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)(.*)/;#S$1E$2$3$4$5$6$7/;
	my ($houroffset, $minoffset);

	if ($offset =~ /z/i)
	{
		$offset = 0;
		$houroffset = 0;
		$minoffset = 0;
	}
	else
	{
		($houroffset, $minoffset) = $offset =~ /(\d+):(\d+)/;
	}
	my $dt = DateTime->new(
		 	year		=> $year,
		 	month		=> $month,
		 	day		=> $day,
		 	hour		=> $hour,
		 	minute		=> $min,
		 	second		=> $sec,
		 	nanosecond	=> 0,
		 	time_zone	=> $offset,
		);
	$dt->set_time_zone(  $result_timezone );
	my $tz = DateTime::TimeZone->new( name => $result_timezone );
	my $localoffset = $tz->offset_for_datetime($dt);
	$localoffset = $localoffset/3600;
	if ($localoffset =~ /\./)
	{
		$localoffset =~ s/(.*)(\..*)/$1$2/;
		$localoffset = sprintf("+%0.2d:%0.2d", $1, ($2*60));
	} else {
		$localoffset = sprintf("+%0.2d:00", $localoffset);
	}
	my $ymd = $dt->ymd;
	my $hms = $dt->hms;
	my $returntime = $ymd . "T" . $hms . $localoffset;
	return $returntime;
}

sub addTime
{
	my ($duration, $startTime) = @_;
	my ($year, $month, $day, $hour, $min, $sec, $offset) = $startTime =~ /(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)(.*)/;#S$1E$2$3$4$5$6$7/;
		my $dt = DateTime->new(
		 	year		=> $year,
		 	month		=> $month,
		 	day		=> $day,
		 	hour		=> $hour,
		 	minute		=> $min,
		 	second		=> $sec,
		 	nanosecond	=> 0,
		 	time_zone	=> $offset,
		);
	my $endTime = $dt + DateTime::Duration->new( minutes => $duration );
	my $ymd = $endTime->ymd;
	my $hms = $endTime->hms;
	my $returntime = $ymd . "T" . $hms . $offset;
	return ($returntime);
}

sub getTimeOffset
{
	my ($timezone, $time, $day) = @_;
	my $dtc = DateTime->now(time_zone => $timezone); # create a new object in the timezone
	my $dto = $dtc->clone; #DateTime->now(time_zone => $timezone); # create a new object in the timezone
	#$dtc->now; # from_epoch(time())
	#$dtc->time_zone($timezone); # set where we are working
	my ($hour, $minute, $ampm) = $time =~ /^(\d+):(\d+)\s+(AM|PM)$/; # split it up
	$dto->set_hour($hour);
	# add 12 hours if PM and anything but 12 noon - 12:59pm (as this would push it into tomorrow)
	$dto->add(hours => 12) if ($ampm eq "PM" and $hour ne 12);
	$dto->add(days => 1) if ($day eq "tomorrow");
	$dto->set_minute($minute);
	$dto->set_second("00");
	# add 12 hours if PM
	my $duration = ($dto->epoch)-($dtc->epoch);
	warn($dtc . " - " . $dto . "\n") if ($DEBUG);
	warn($time . " --> " . $dtc->epoch . "-" . $dto->epoch . " = $duration\n") if ($DEBUG);
	return $duration; # should be seconds (negative if before 'now')
}

sub buildregions {
	my $url = "https://www.yourtv.com.au/guide/";
	my $res = $ua->get($url);
	die("Unable to connect to FreeView.\n") if (!$res->is_success);
	my $data = $res->content;
	$data =~ s/\R//g;
	$data =~ s/.*window.regionState\s+=\s+(\[.*\]);.*/$1/;
	my $region_json = JSON->new->relaxed(1)->allow_nonref(1)->decode($data);
	return @$region_json;
}

sub nextday
{
    my $daycount = shift;
    my $returnday;
    my @days = ("mon","tue","wed","thu","fri","sat","sun");
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
    my $daynumber = $wday + $daycount ;
    if ($daycount eq 0)
    {
        $returnday = "today";
    }
    elsif ($daycount eq 1)
    {
        $returnday = "tomorrow";
    }
    elsif ($daynumber < 8)
    {
        $returnday = $days[$daynumber-1];
    }
    else {
        $returnday = $days[$daynumber-7-1];
    }
}

sub getFVShowIcon
{
	my ($lcn,$title,$startTime,$stopTime) = @_;
	my $dvb_triplet = $DVBTRIPLET->{$lcn};
	return if (!defined($dvb_triplet));
	my $returnurl = "";
	my ($year, $month, $day, $hour, $min, $sec, $offset) = $startTime =~ /(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\s+(.*)/;#S$1E$2$3$4$5$6$7/;

	my $dt = DateTime->new(
		 	year		=> $year,
		 	month		=> $month,
		 	day			=> $day,
		 	hour		=> 0,
		 	minute		=> 0,
		 	second		=> 0,
		 	nanosecond	=> 0,
		 	time_zone	=> $offset,
		);
	$dt->set_time_zone(  "UTC" );
	$startTime = $dt->ymd('-') . 'T' . $dt->hms(':') . 'Z';
	my $stopdt = $dt + DateTime::Duration->new( hours => 24 );
	$stopTime = $stopdt->ymd('-') . 'T' . $stopdt->hms(':') . 'Z';
	my $hash = "$dvb_triplet - $startTime";
	my $data = {};
	my $jsonvalid = 0;
	if (defined ($fvdbm_hash{$hash} ))
	{
		if (valid_json ($fvdbm_hash{$hash}))
		{
			$fvthrdret{$hash} = $fvdbm_hash{$hash};
			$data = $fvdbm_hash{$hash};
			$jsonvalid = 1;
		}
		else 
		{
			undef $fvdbm_hash{$hash};
			warn("JSON data invalid for $hash\n") if ($VERBOSE);
		}
	}
	elsif (defined($fvthrdret{$hash}))
	{
		if (valid_json ($fvthrdret{$hash}))
		{
			$data = $fvthrdret{$hash};
			$jsonvalid = 1;
		}
		else
		{
			undef $fvthrdret{$hash};
			warn("JSON data invalid for $hash\n") if ($VERBOSE);
		}
	}

	if (!$jsonvalid)
	{
		my $url = "https://fvau-api-prod.switch.tv/content/v1/epgs/".$dvb_triplet."?start=".$startTime."&end=".$stopTime."&sort=start&related_entity_types=episodes.images,shows.images&related_levels=2&include_related=1&expand_related=full&limit=100&offset=0";
		my $res = $ua->get($url);
		die("Unable to connect to FreeView.\n") if (!$res->is_success);
		my $responsecode = $res->code();
		warn("Freeview response code is $responsecode") if ($DEBUG);
		if ($responsecode == 204) {
			$data = "{}";
		}
		else {
			$data = $res->content;
			$fvthrdret{$hash} = $data;			
		}
		print "+" if ($VERBOSE);
	}
	print "\n-------------------------\ngetFVShowIcon\n$data\n" if ($DEBUG);

	my $tmpchanneldata;
	$tmpchanneldata = JSON->new->relaxed(1)->allow_nonref(1)->decode($data);
	$tmpchanneldata = $tmpchanneldata->{data};
	if (defined($tmpchanneldata))
	{
		for (my $count = 0; $count < scalar @$tmpchanneldata; $count++)
		{
			if ((defined($tmpchanneldata->[$count]->{related}->{shows}[0]->{title})) and ($tmpchanneldata->[$count]->{related}->{shows}[0]->{title} =~ /\Q$title\E/i))
			{
				$returnurl = $tmpchanneldata->[$count]->{related}->{shows}[0]->{images}[0]->{url};
				return $returnurl;
			}
			elsif ((defined($tmpchanneldata->[$count]->{related}->{episodes}[0]->{title})) and ($tmpchanneldata->[$count]->{related}->{episodes}[0]->{title} =~ /\Q$title\E/i))
			{
				$returnurl = $tmpchanneldata->[$count]->{related}->{episodes}[0]->{images}[0]->{url};
				return $returnurl;
			}
		}
	}
   	return;
}

sub getFVInfo
{
    $ua = shift;
	my @fvregions = (
		"region_national",
		"region_nsw_sydney",
		"region_nsw_newcastle",
		"region_nsw_taree",
		"region_nsw_tamworth",
		"region_nsw_orange_dubbo_wagga",
		"region_nsw_northern_rivers",
		"region_nsw_wollongong",
		"region_nsw_canberra",
		"region_nt_regional",
		"region_vic_albury",
		"region_vic_shepparton",
		"region_vic_bendigo",
		"region_vic_melbourne",
		"region_vic_ballarat",
		"region_vic_gippsland",
		"region_qld_brisbane",
		"region_qld_goldcoast",
		"region_qld_toowoomba",
		"region_qld_maryborough",
		"region_qld_widebay",
		"region_qld_rockhampton",
		"region_qld_mackay",
		"region_qld_townsville",
		"region_qld_cairns",
		"region_sa_adelaide",
		"region_sa_regional",
		"region_wa_perth",
		"region_wa_regional_wa",
		"region_tas_hobart",
		"region_tas_launceston",
	);

	foreach my $fvregion (@fvregions)
	{
		my $data;
		if (defined ($fvdbm_hash{$fvregion} ))
		{
			$fvthrdret{$fvregion} = $fvdbm_hash{$fvregion};
			$data = $fvdbm_hash{$fvregion};
		}
		else
		{
			my $url = "https://fvau-api-prod.switch.tv/content/v1/channels/region/" . $fvregion
				. "?limit=100&offset=0&include_related=1&expand_related=full&related_entity_types=images";
			my $res = $ua->get($url);

			die("Unable to connect to FreeView.\n") if (!$res->is_success);
			$data = $res->content;
			$fvthrdret{$fvregion} = $data;
		}
		my $tmpchanneldata = JSON->new->relaxed(1)->allow_nonref(1)->decode($data);
		$tmpchanneldata = $tmpchanneldata->{data};
		for (my $count = 0; $count < @$tmpchanneldata; $count++)
		{
			$FVICONS->{$tmpchanneldata->[$count]->{lcn}} = $tmpchanneldata->[$count]->{related}->{images}[0]->{url};
			$DVBTRIPLET->{$tmpchanneldata->[$count]->{lcn}} = $tmpchanneldata->[$count]->{'dvb_triplet'};
        }
	}
}

sub get_duplicate_channels
{
	foreach my $dupe (@_)
	{
		my ($original, $dupes) = split(/=/, $dupe);
		if (!defined $dupes || !length $dupes)
		{
			warn("WARNING: Ignoring --duplicate $dupe as it is not in the correct format (should be: --duplicate 6=60,61)\n");
			next;
		}
		my @channels = split(/,/, $dupes);
		if (!@channels || !scalar @channels)
		{
			warn("WARNING: Ignoring --duplicate $dupe as it is not in the correct format (should be: --duplicate 6=60,61,... etc)\n");
			next;
		}
		push(@DUPLICATED_CHANNELS, $original);
		foreach my $channel (@channels)
		{
			$DUPLICATE_CHANNELS{$channel} = $original;
		}
	}
}

sub usage
{
	@REGIONS = buildregions() if (!(@REGIONS));
	return    "Usage:\n"
		. "\t$0 --region=<region> [--output <filename>] [--days=<days to collect>] [--ignore=<channels to ignore>] [--include=<channels to include>] [--fvicons] [--pretty] [--VERBOSE] [--help|?]\n"
		. "\n\tWhere:\n\n"
		. "\t--region=<region>\t\tThis defines which tv guide to parse. It is mandatory. Refer below for a list of regions.\n"
		. "\t--days=<days to collect>\tThis defaults to 7 days and can be no more than 7.\n"
		. "\t--pretty\t\t\tOutput the XML with tabs and newlines to make human readable.\n"
		. "\t--output <filename>\t\tWrite to the location and file specified instead of standard output.\n"
		. "\t--ignore=<channel to ignore>\tA comma separated list of channel numbers to ignore. The channel number is matched against the lcn tag within the xml.\n"
		. "\t--duplicates <orig>=<ch1>,<ch2>\tOption may be specified more than once, this will create a guide where different channels have the same data.\n"
		. "\t--include=<channel to include>\tA comma separated list of channel numbers to include. The channel number is matched against the lcn tag within the xml.\n"
		. "\t--extrachannels <region>-<ch1>,<ch2>\tThis will fetch EPG data for the channels specified from one other region.\n"
		. "\t--fvicons\t\t\tUse Freeview icons if they exist.\n"
		. "\t--verbose\t\t\tVerbose Mode (prints processing steps to STDERR).\n"
		. "\t--help\t\t\t\tWill print this usage and exit!\n"
		. "\t  <region> is one of the following:\n\t\t"
		. join("\n\t\t", (map { "$_->{id}\t=\t$_->{name}" } @REGIONS) )
		. "\n\n";
}

################# RADIO

sub define_ABC_local_radio
{
	my $state = shift;
	my %definedregions = (
		"WA"	=> "local_perth", #     =       Perth
		"SA"	=> "local_adelaide", #       Adelaide
		"TAS" 	=>	"local_hobart", #      Hobart
		"VIC"	=>	"local_melbourne",	#Melbourne
		"QLD"	=>	"local_brisbane",
		"NSW"	=>	"local_sydney",
		"NT"	=> 	"local_darwin",
		"ACT"	=> 	"local_canberra",
	);
	my %icons = (
		"WA"	=> "http://www.abc.net.au/radio/images/service/ABC-Radio-Perth.png",
		"SA"	=> "http://www.abc.net.au/radio/images/service/ABC-Radio-Adelaide.png",
		"TAS" 	=>	"http://www.abc.net.au/radio/images/service/ABC-Radio-Hobart.png",
		"VIC"	=>	"http://www.abc.net.au/radio/images/service/ABC-Radio-Melbourne.png",
		"QLD"	=>	"http://www.abc.net.au/radio/images/service/ABC-Radio-Brisbane.png",
		"NSW"	=>	"http://www.abc.net.au/radio/images/service/ABC-Radio-Sydney.png",
		"NT"	=> 	"http://www.abc.net.au/radio/images/service/ABC-Radio-Darwin.png",
		"ACT"	=> 	"http://www.abc.net.au/radio/images/service/ABC-Radio-Canberra.png",
	);
	$ABCRADIO{"25"}{name}  = "ABC Local Radio";
	$ABCRADIO{"25"}{iconurl}       = $icons{$state};
	$ABCRADIO{"25"}{servicename}   = $definedregions{$state};
}

sub ABCgetchannels
{
        my $count = 0;
        my @tmpdata;
        foreach my $key (keys %ABCRADIO)
        {
                next if ( ( grep( /^$key$/, @IGNORECHANNELS ) ) );

                $tmpdata[$count]->{name} = $ABCRADIO{$key}{name};
                $tmpdata[$count]->{id} = $key.".yourtv.com.au";
                $tmpdata[$count]->{lcn} = $key;
                $tmpdata[$count]->{icon} = $ABCRADIO{$key}{iconurl};
                $count++;
        }
        return @tmpdata;
}

sub ABCgetepg
{
        my $ua = shift;
        my $showcount = 0;
        my @tmpguidedata;
		warn("Getting epg for ABC Radio Stations ...\n") if ($VERBOSE);
        foreach my $key (keys %ABCRADIO)
        {
                next if ( ( grep( /^$key$/, @IGNORECHANNELS ) ) );

                my $id = $key;
                warn("$ABCRADIO{$key}{name} ...\n") if ($VERBOSE);
				next if ($ABCRADIO{$key}{servicename} eq "");
                my ($ssec,$smin,$shour,$smday,$smon,$syear,$swday,$syday,$sisdst) = localtime(time-86400);
                my ($esec,$emin,$ehour,$emday,$emon,$eyear,$ewday,$eyday,$eisdst) = localtime(time+(86400*$NUMDAYS));
                my $startdate = sprintf("%0.4d-%0.2d-%0.2dT%0.2d:%0.2d:%0.2dZ",($syear+1900),$smon+1,$smday,$shour,$smin,$ssec);
                my $enddate = sprintf("%0.4d-%0.2d-%0.2dT%0.2d:%0.2d:%0.2dZ",($eyear+1900),$emon+1,$emday,$ehour,$emin,$esec);
                my $url = URI->new( 'https://program.abcradio.net.au/api/v1/programitems/search.json' );
                $url->query_form(service => $ABCRADIO{$key}{servicename}, limit => '100', order => 'asc', order_by => 'ppe_date', from => $startdate, to => $enddate);
                my $res = $ua->get($url);
                if (!$res->is_success)
				{
					warn("Unable to connect to ABC radio schedule: URL: $url. [" . $res->status_line . "]\n");
					next;
				}
                my $tmpdata;
                eval {
                         $tmpdata = JSON->new->relaxed(1)->allow_nonref(1)->decode($res->content);
                        1;
                };
                $tmpdata = $tmpdata->{items};
                if (defined($tmpdata))
                {
                        for (my $count = 0; $count < @$tmpdata; $count++)
                        {
                                $tmpguidedata[$showcount]->{id} = $key.".yourtv.com.au";
                                $tmpguidedata[$showcount]->{start} = $tmpdata->[$count]->{live}[0]->{start};
                                $tmpguidedata[$showcount]->{start} = toLocalTimeString($tmpdata->[$count]->{live}[0]->{start},'UTC');
                                my $duration = $tmpdata->[$count]->{live}[0]->{duration_seconds}/60;
                                $tmpguidedata[$showcount]->{stop} = addTime($duration,$tmpguidedata[$showcount]->{start});
                                $tmpguidedata[$showcount]->{start} =~ s/[-T:]//g;
                                $tmpguidedata[$showcount]->{start} =~ s/\+/ \+/g;
                                $tmpguidedata[$showcount]->{stop} =~ s/[-T:]//g;
                                $tmpguidedata[$showcount]->{stop} =~ s/\+/ \+/g;

                                $tmpguidedata[$showcount]->{channel} = $ABCRADIO{$key}{name};
                                $tmpguidedata[$showcount]->{title} = $tmpdata->[$count]->{title};
                                my $catcount = 0;
                                push(@{$tmpguidedata[$showcount]->{category}}, "Radio");
                                foreach my $tmpcat (@{$tmpdata->[$count]->{categories}})
                                {
									push(@{$tmpguidedata[$showcount]->{category}}, $tmpcat->{label});
									$catcount++;
								}
								if (defined($tmpdata->[$count]->{short_synopsis}))
								{
									$tmpguidedata[$showcount]->{desc} = $tmpdata->[$count]->{short_synopsis};
								}
								elsif (defined($tmpdata->[$count]->{mini_synopsis}))
								{
									$tmpguidedata[$showcount]->{desc} = $tmpdata->[$count]->{mini_synopsis};
								}
								$showcount++;

                        }
                }

        }
        warn("Processed a total of $showcount shows ...\n") if ($VERBOSE);
        return @tmpguidedata;
}

sub SBSgetchannels
{
        my @tmpdata;
        my $count = 0;
        foreach my $key (keys %SBSRADIO)
        {
                next if ( ( grep( /^$key$/, @IGNORECHANNELS ) ) );

                $tmpdata[$count]->{name} = $SBSRADIO{$key}{name};
                $tmpdata[$count]->{id} = $key.".yourtv.com.au";
                $tmpdata[$count]->{lcn} = $key;
                $tmpdata[$count]->{icon} = $SBSRADIO{$key}{iconurl};
                $count++;
        }
        return @tmpdata;
}

sub SBSgetepg
{
        my $ua = shift;
        my $showcount = 0;
        my @tmpguidedata;
		warn("Getting epg for SBS Radio Stations ...\n") if ($VERBOSE);
        foreach my $key (keys %SBSRADIO)
        {
                next if ( ( grep( /^$key$/, @IGNORECHANNELS ) ) );

                my $id = $key;
                warn("$SBSRADIO{$key}{name} ...\n") if ($VERBOSE);
                my $now = time;;
                my ($ssec,$smin,$shour,$smday,$smon,$syear,$swday,$syday,$sisdst) = localtime(time);
                my ($esec,$emin,$ehour,$emday,$emon,$eyear,$ewday,$eyday,$eisdst) = localtime(time+(86400*$NUMDAYS));
                my $startdate = sprintf("%0.4d-%0.2d-%0.2dT%0.2d:%0.2d:%0.2dZ",($syear+1900),$smon+1,$smday,$shour,$smin,$ssec);
                my $enddate = sprintf("%0.4d-%0.2d-%0.2dT%0.2d:%0.2d:%0.2dZ",($eyear+1900),$emon+1,$emday,$ehour,$emin,$esec);

                my $url = "http://two.aim-data.com/services/schedule/sbs/".$SBSRADIO{$key}{servicename}."?days=".$NUMDAYS;
                my $res = $ua->get($url);
                if (!$res->is_success)
				{
					warn("Unable to connect to SBS radio schedule: URL: $url.. [" . $res->status_line . "]\n");
					next;
				}
                my $data = $res->content;
                my $tmpdata;
                eval {
                        $tmpdata = XMLin($data);
                        1;
                };
                $tmpdata = $tmpdata->{entry};
                if (defined($tmpdata))
                {
                        my $count = 0;
                        foreach my $key (keys %$tmpdata)
                        {
                                $tmpguidedata[$showcount]->{id} = $id.".yourtv.com.au";
                                $tmpguidedata[$showcount]->{start} = $tmpdata->{$key}->{start};
                                $tmpguidedata[$showcount]->{start} =~ s/[-T:\s]//g;
                                $tmpguidedata[$showcount]->{start} =~ s/(\+)/00 +/;
                                $tmpguidedata[$showcount]->{stop} = $tmpdata->{$key}->{end};
                                $tmpguidedata[$showcount]->{stop} =~ s/[-T:\s]//g;
                                $tmpguidedata[$showcount]->{stop} =~ s/(\+)/00 +/;
                                $tmpguidedata[$showcount]->{channel} = $SBSRADIO{$key}{name};
                                $tmpguidedata[$showcount]->{title} = $tmpdata->{$key}->{title};
                                my $catcount = 0;
                                push(@{$tmpguidedata[$showcount]->{category}}, "Radio");
                                my $desc = $tmpdata->{$key}->{description};
                                $tmpguidedata[$showcount]->{desc} = $tmpdata->{$key}->{description} if (!(ref $desc eq ref {}));
                                $showcount++;

                        }
                }

        }
        warn("Processed a total of $showcount shows ...\n") if ($VERBOSE);
        return @tmpguidedata;
}
