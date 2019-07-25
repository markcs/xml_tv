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
use DateTime;
use Getopt::Long;
use XML::Writer;
use URI;
use Thread::Queue;
use Fcntl qw(:DEFAULT :flock);
use File::Copy;
use Clone qw( clone );

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
my $FVICONURL;
my @GUIDEDATA;
my $REGION_TIMEZONE;
my $REGION_NAME;
my $CACHEFILE = "yourtv.db";
my $CACHETIME = 86400; # 1 day - don't change this unless you know what you are doing.
my $TMPCACHEFILE = ".$$.yourtv-tmp-cache.db";
my $ua;

my (%dbm_hash, %thrdret);
local (*DBMRO, *DBMRW);

my ($DEBUG, $VERBOSE, $pretty, $USEFREEVIEWICONS, $NUMDAYS, $ignorechannels, $includechannels, $REGION, $outputfile, $help) = (0, 0, 0, 0, 7, undef, undef, undef, undef, undef);
GetOptions
(
	'debug'		=> \$DEBUG,
	'verbose'	=> \$VERBOSE,
	'pretty'	=> \$pretty,
	'days=i'	=> \$NUMDAYS,
	'region=s'	=> \$REGION,
	'output=s'	=> \$outputfile,
	'ignore=s'	=> \$ignorechannels,
  'include=s' => \$includechannels,
  'fvicons'	=> \$USEFREEVIEWICONS,
	'cachefile=s'	=> \$CACHEFILE,
	'cachetime=i'	=> \$CACHETIME,
	'duplicates=s'	=> \@dupes,
	'help|?'	=> \$help,
) or die ("Syntax Error!  Try $0 --help");

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
die usage() if ($help);
die(usage() ) if (!defined($REGION));

$CACHEFILE = "yourtv-region_$REGION.db" if ($CACHEFILE eq "yourtv.db");

my $validregion = 0;
my @REGIONS = buildregions();
for my $tmpregion ( @REGIONS )
{
	if ($tmpregion->{id} eq $REGION) {
        $validregion = 1;
        $REGION_TIMEZONE = $tmpregion->{timezone};
        $REGION_NAME = $tmpregion->{name};
	}
}
die(	  "\n"
	. "Invalid region specified.  Please use one of the following:\n\t\t"
	. join("\n\t\t", (map { "$_->{id}\t=\t$_->{name}" } @REGIONS) )
	. "\n\n"
   ) if (!$validregion); # (!defined($REGIONS->{$REGION}));

warn("Options...\nregion=$REGION, output=$outputfile, days = $NUMDAYS, fvicons = $USEFREEVIEWICONS, Verbose = $VERBOSE, pretty = $pretty, \n\n") if ($VERBOSE);

# Initialise here (connections to the same server will be cached)
my @IGNORECHANNELS;
@IGNORECHANNELS = split(/,/,$ignorechannels) if (defined($ignorechannels));
my @INCLUDECHANNELS;
@INCLUDECHANNELS = split(/,/,$includechannels) if (defined($includechannels));

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
getchannels($ua);
warn("Getting EPG data...\n") if ($VERBOSE);
getepg($ua);

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

warn("Starting to build the XML...\n") if ($VERBOSE);
my $XML = XML::Writer->new( OUTPUT => 'self', DATA_MODE => ($pretty ? 1 : 0), DATA_INDENT => ($pretty ? 8 : 0) );
$XML->xmlDecl("ISO-8859-1");
$XML->doctype("tv", undef, "xmltv.dtd");
$XML->startTag('tv', 'generator-info-url' => "http://www.xmltv.org/");

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
	exit(1);
}

sub close_cache
{
	untie(%dbm_hash);
	untie(%thrdret);
	close DBMRW;
	close DBMRO;
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
	my $ua = shift;
	warn("Getting channel list from YourTV ...\n") if ($VERBOSE);
	my $url = "https://www.yourtv.com.au/api/regions/" . $REGION . "/channels";
	my $res = $ua->get($url);
	my $tmpchanneldata;

	die("Unable to connect to FreeView.\n") if (!$res->is_success);

	$tmpchanneldata = JSON->new->relaxed(1)->allow_nonref(1)->decode($res->content);
	my $dupe_count = 0;

	for (my $count = 0; $count < @$tmpchanneldata; $count++)
	{
		next if ( ( grep( /^$tmpchanneldata->[$count]->{id}$/, @IGNORECHANNELS ) ) );
		next if ( ( !( grep( /^$tmpchanneldata->[$count]->{number}$/, @INCLUDECHANNELS ) ) ) and ((@INCLUDECHANNELS > 0)));
		my $channelIsDuped = 0;
		++$channelIsDuped if ( ( grep( /$tmpchanneldata->[$count]->{number}$/, @DUPLICATED_CHANNELS ) ) );
		$CHANNELDATA[$count]->{tv_id} = $tmpchanneldata->[$count]->{id};
		$CHANNELDATA[$count]->{name} = $tmpchanneldata->[$count]->{description};
		$CHANNELDATA[$count]->{id} = $tmpchanneldata->[$count]->{number}.".yourtv.com.au";
		$CHANNELDATA[$count]->{lcn} = $tmpchanneldata->[$count]->{number};
		$CHANNELDATA[$count]->{icon} = $tmpchanneldata->[$count]->{logo}->{url};
		$CHANNELDATA[$count]->{icon} = $FVICONS->{$tmpchanneldata->[$count]->{number}} if (defined($FVICONS->{$tmpchanneldata->[$count]->{number}}));
		#FIX SBS ICONS
		if (($USEFREEVIEWICONS) && (!defined($CHANNELDATA[$count]->{icon})) && ($CHANNELDATA[$count]->{name} =~ /SBS/))
		{
			$tmpchanneldata->[$count]->{number} =~ s/(\d)./$1/;
			$CHANNELDATA[$count]->{icon} = $FVICONS->{$tmpchanneldata->[$count]->{number}} if (defined($FVICONS->{$tmpchanneldata->[$count]->{number}}));
		}
		warn("Got channel $CHANNELDATA[$count]->{id} - $CHANNELDATA[$count]->{name} ...\n") if ($VERBOSE);
		if ($channelIsDuped)
		{
			foreach my $dchan (sort keys %DUPLICATE_CHANNELS)
			{
				next if ($DUPLICATE_CHANNELS{$dchan} ne $tmpchanneldata->[$count]->{number});
				$DUPECHANDATA[$dupe_count]->{tv_id} = $CHANNELDATA[$count]->{tv_id};
				$DUPECHANDATA[$dupe_count]->{name} = $CHANNELDATA[$count]->{name};
				$DUPECHANDATA[$dupe_count]->{id} = $dchan . ".yourtv.com.au";
				$DUPECHANDATA[$dupe_count]->{lcn} = $dchan;
				$DUPECHANDATA[$dupe_count]->{icon} = $CHANNELDATA[$count]->{icon};
				warn("Duplicated channel $CHANNELDATA[$count]->{name} -> $DUPECHANDATA[$dupe_count]->{id} ...\n") if ($VERBOSE);
				++$dupe_count;
			}
		}
	}
}

sub getepg
{
	my $ua = shift;
	my $showcount = 0;
	my $dupe_scount = 0;
	my $url;

	warn(" \n") if ($VERBOSE);
	my $nl = 0;
	for(my $day = 0; $day < $NUMDAYS; $day++)
	{
		my $day = nextday($day);
		my $id;
		my $url = URI->new( 'https://www.yourtv.com.au/api/guide/' );
		$url->query_form(day => $day, timezone => $REGION_TIMEZONE, format => 'json', region => $REGION);
		warn(($nl ? "\n" : "" ) . "Getting channel program listing for $REGION_NAME ($REGION) for $day ($url)...\n") if ($VERBOSE);
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
									my $offset = getTimeOffset($REGION_TIMEZONE, $subblocks->[$airingcount]->{date}, $day);
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
							$GUIDEDATA[$showcount]->{id} = $id;
							$GUIDEDATA[$showcount]->{airing_tmp} = $airing;
							$GUIDEDATA[$showcount]->{desc} = $showdata->{synopsis};
							$GUIDEDATA[$showcount]->{subtitle} = $showdata->{episodeTitle};
							$GUIDEDATA[$showcount]->{start} = toLocalTimeString($showdata->{date},$REGION_TIMEZONE);
							$GUIDEDATA[$showcount]->{stop} = addTime($showdata->{duration},$GUIDEDATA[$showcount]->{start});
							$GUIDEDATA[$showcount]->{start} =~ s/[-T:]//g;
							$GUIDEDATA[$showcount]->{start} =~ s/\+/ \+/g;
							$GUIDEDATA[$showcount]->{stop} =~ s/[-T:]//g;
							$GUIDEDATA[$showcount]->{stop} =~ s/\+/ \+/g;
							$GUIDEDATA[$showcount]->{channel} = $showdata->{service}->{description};
							$GUIDEDATA[$showcount]->{title} = $showdata->{title};
							$GUIDEDATA[$showcount]->{rating} = $showdata->{classification};
							if (defined($showdata->{program}->{image}))
							{
								$GUIDEDATA[$showcount]->{url} = $showdata->{program}->{image};
							}
							else
							{
								if (defined($FVICONURL->{$chandata->[$channelcount]->{number}}->{$GUIDEDATA[$showcount]->{title}}))
								{
									$GUIDEDATA[$showcount]->{url} = $FVICONURL->{$chandata->[$channelcount]->{number}}->{$GUIDEDATA[$showcount]->{title}}
								}
								else
								{
									$GUIDEDATA[$showcount]->{url} = getFVShowIcon($chandata->[$channelcount]->{number},$GUIDEDATA[$showcount]->{title},$GUIDEDATA[$showcount]->{start},$GUIDEDATA[$showcount]->{stop})
								}
							}
							push(@{$GUIDEDATA[$showcount]->{category}}, $showdata->{genre}->{name});
							#	program types as defined by yourtv $showdata->{programType}->{id}
							#	1	 Television movie
							#	2	 Cinema movie
							#	3	 Mini series
							#	4	 Series no episodes
							#	5	 Series with episodes
							#	8	 Limited series
							#	9	 Special
							my $tmpseries = toLocalTimeString($showdata->{date},$REGION_TIMEZONE);
							my ($episodeYear, $episodeMonth, $episodeDay, $episodeHour, $episodeMinute) = $tmpseries =~ /(\d+)-(\d+)-(\d+)T(\d+):(\d+).*/;#S$1E$2$3$4$5/;

							#if ($showdata->{programType}->{id} eq "1") {
							if ($showdata->{program}->{programTypeId} eq "1") {
								push(@{$GUIDEDATA[$showcount]->{category}}, $showdata->{programType}->{name});
							}
							elsif ($showdata->{program}->{programTypeId} eq "2") {
								push(@{$GUIDEDATA[$showcount]->{category}}, $showdata->{programType}->{name});
							}
							elsif ($showdata->{program}->{programTypeId} eq "3") {
								push(@{$GUIDEDATA[$showcount]->{category}}, $showdata->{programType}->{name});
								$GUIDEDATA[$showcount]->{episode} = $showdata->{episodeNumber} if (defined($showdata->{episodeNumber}));
								$GUIDEDATA[$showcount]->{season} = "1";
							}
							elsif ($showdata->{program}->{programTypeId} eq "4") {
								$GUIDEDATA[$showcount]->{premiere} = "1";
								$GUIDEDATA[$showcount]->{originalairdate} = $episodeYear."-".$episodeMonth."-".$episodeDay." ".$episodeHour.":".$episodeMinute.":00";#"$1-$2-$3 $4:$5:00";
								if (defined($showdata->{episodeNumber}))
								{
									$GUIDEDATA[$showcount]->{episode} = $showdata->{episodeNumber};
								}
								else
								{
									$GUIDEDATA[$showcount]->{episode} = sprintf("%0.2d%0.2d",$episodeMonth,$episodeDay);
								}
								if (defined($showdata->{seriesNumber})) {
									$GUIDEDATA[$showcount]->{season} = $showdata->{seriesNumber};
								}
								else
								{
									$GUIDEDATA[$showcount]->{season} = $episodeYear;
								}
							}
							elsif ($showdata->{program}->{programTypeId} eq "5")
							{
								if (defined($showdata->{seriesNumber})) {
									$GUIDEDATA[$showcount]->{season} = $showdata->{seriesNumber};
								}
								else
								{
									$GUIDEDATA[$showcount]->{season} = $episodeYear;
								}
								if (defined($showdata->{episodeNumber})) {
									$GUIDEDATA[$showcount]->{episode} = $showdata->{episodeNumber};
								}
								else
								{
									$GUIDEDATA[$showcount]->{episode} = sprintf("%0.2d%0.2d",$episodeMonth,$episodeDay);
								}
							}
							elsif ($showdata->{program}->{programTypeId} eq "8")
							{
								if (defined($showdata->{seriesNumber})) {
									$GUIDEDATA[$showcount]->{season} = $showdata->{seriesNumber};
								}
								else
								{
									$GUIDEDATA[$showcount]->{season} = $episodeYear;
								}
								if (defined($showdata->{episodeNumber})) {
									$GUIDEDATA[$showcount]->{episode} = $showdata->{episodeNumber};
								}
								else
								{
									$GUIDEDATA[$showcount]->{episode} = sprintf("%0.2d%0.2d",$episodeMonth,$episodeDay);
								}
							}
							elsif ($showdata->{program}->{programTypeId} eq "9")
							{
								$GUIDEDATA[$showcount]->{season} = $episodeYear;
								$GUIDEDATA[$showcount]->{episode} = sprintf("%0.2d%0.2d",$episodeMonth,$episodeDay);
							}
							if (defined($showdata->{repeat} ) )
							{
								$GUIDEDATA[$showcount]->{originalairdate} = $episodeYear."-".$episodeMonth."-".$episodeDay." ".$episodeHour.":".$episodeMinute.":00";#"$1-$2-$3 $4:$5:00";
								$GUIDEDATA[$showcount]->{previouslyshown} = "$episodeYear-$episodeMonth-$episodeDay";#"$1-$2-$3";
							}
							if ($channelIsDuped)
							{
								foreach my $dchan (sort keys %DUPLICATE_CHANNELS)
								{
									next if ($DUPLICATE_CHANNELS{$dchan} ne $channelIsDuped);
									my $did = $dchan . ".yourtv.com.au";
									$DUPEGUIDEDATA[$dupe_scount] = clone($GUIDEDATA[$showcount]);
									$DUPEGUIDEDATA[$dupe_scount]->{id} = $did;
									$DUPEGUIDEDATA[$dupe_scount]->{channel} = $did;
									warn("Duplicated guide data for show entry $showcount -> $dupe_scount ($GUIDEDATA[$showcount] -> $DUPEGUIDEDATA[$dupe_scount]) ...\n") if ($DEBUG);
									++$dupe_scount;
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
		${$XMLRef}->emptyTag('icon', 'src' => $items->{url}) if (defined($items->{url}));
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
		${$XMLRef}->dataElement('episode-num', $items->{originalairdate}, 'system' => 'original-air-date') if (defined($items->{originalairdate}));
		${$XMLRef}->emptyTag('previously-shown', 'start' => $items->{previouslyshown}) if (defined($items->{previouslyshown}));
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
	$dt->set_time_zone(  "GMT" );


	$startTime = $dt->ymd('-') . 'T' . $dt->hms(':') . 'Z';
	my $stopdt = $dt + DateTime::Duration->new( hours => 24 );

	$stopTime = $stopdt->ymd('-') . 'T' . $stopdt->hms(':') . 'Z';
	my $url = "https://fvau-api-prod.switch.tv/content/v1/epgs/".$dvb_triplet."?start=".$startTime."&end=".$stopTime."&sort=start&related_entity_types=episodes.images,shows.images&related_levels=2&include_related=1&expand_related=full&limit=100&offset=0";
	my $res = $ua->get($url);
	die("Unable to connect to FreeView.\n") if (!$res->is_success);
	my $data = $res->content;
	my $tmpchanneldata = JSON->new->relaxed(1)->allow_nonref(1)->decode($data);
	$tmpchanneldata = $tmpchanneldata->{data};
	if (defined($tmpchanneldata))
	{
		for (my $count = 0; $count < @$tmpchanneldata; $count++)
		{
			$FVICONURL->{$lcn}->{$title} = $tmpchanneldata->[$count]->{related}->{shows}[0]->{images}[0]->{url};
			if ($tmpchanneldata->[$count]->{related}->{shows}[0]->{title} =~ /$title/i)
			{
				$returnurl = $tmpchanneldata->[$count]->{related}->{shows}[0]->{images}[0]->{url};
				return $returnurl;
			}
			elsif ($tmpchanneldata->[$count]->{related}->{episodes}[0]->{title} =~ /$title/i)
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
#		"region_nsw_newcastle",
#		"region_nsw_taree",
		"region_nsw_tamworth",
#		"region_nsw_orange_dubbo_wagga",
		"region_nsw_northern_rivers",
#		"region_nsw_wollongong",
		"region_nsw_canberra",
		"region_nt_regional",
#		"region_vic_albury",
#		"region_vic_shepparton",
		"region_vic_bendigo",
		"region_vic_melbourne",
#		"region_vic_ballarat",
#		"region_vic_gippsland",
		"region_qld_brisbane",
#		"region_qld_goldcoast",
		"region_qld_toowoomba",
#		"region_qld_maryborough",
#		"region_qld_widebay",
#		"region_qld_rockhampton",
#		"region_qld_mackay",
#		"region_qld_townsville",
#		"region_qld_cairns",
		"region_sa_adelaide",
		"region_sa_regional",
		"region_wa_perth",
		"region_wa_regional_wa",
#		"region_tas_hobart",
		"region_tas_launceston",
	);

	foreach my $fvregion (@fvregions)
	{
		my $url = "https://fvau-api-prod.switch.tv/content/v1/channels/region/" . $fvregion
			. "?limit=100&offset=0&include_related=1&expand_related=full&related_entity_types=images";
		my $res = $ua->get($url);

		die("Unable to connect to FreeView.\n") if (!$res->is_success);
		my $data = $res->content;
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
		. "\t--duplicates <orig>=<ch1>,<ch2>\tOption maybe specified more than once, this will create a guide where different channels have the same data.\n"
		. "\t--include=<channel to include>\tA comma separated list of channel numbers to include. The channel number is matched against the lcn tag within the xml.\n"
		. "\t--fvicons\t\t\tUse Freeview icons if they exist.\n"
		. "\t--verbose\t\t\tVerbose Mode (prints processing steps to STDERR).\n"
		. "\t--help\t\t\t\tWill print this usage and exit!\n"
		. "\t  <region> is one of the following:\n\t\t"
		. join("\n\t\t", (map { "$_->{id}\t=\t$_->{name}" } @REGIONS) )
		. "\n\n";
}
