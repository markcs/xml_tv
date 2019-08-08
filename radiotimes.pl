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

my $MAX_THREADS = 4;

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
use LWP::UserAgent;
use XML::Writer;
use Data::Dumper;
use URI;
my %map = (
	 '&' => 'and',
);
my $chars = join '', keys %map;
use Thread::Queue;
use Fcntl qw(:DEFAULT :flock);
use File::Copy;
use Clone qw( clone );
use Cwd qw( getcwd );

use DB_File;

my @CHANNELDATA;

my @GUIDEDATA;
my $REGION_TIMEZONE;
my $CHANNELLIST;
my $ua;
my $CACHEFILE = "radiotimes.db";
my $CACHETIME = 86400; # 1 day - don't change this unless you know what you are doing.
my $TMPCACHEFILE = ".$$.radiotimes-tmp-cache.db";
my (%dbm_hash, %thrdret);
local (*DBMRO, *DBMRW);

my $BBCREGIONS;
my $ITVREGIONS;
my $MAINCHANNELS;
my $OTHERCHANNELS;

my ($PLEX, $VERBOSE, $pretty, $NUMDAYS, $extrachannels, $BBCREGION, $ITVREGION, $DEBUG, $outputfile, $VERIFY, $help) = (0, 0, 0, 1, "", undef, undef, undef, undef, undef, undef);
GetOptions
(
	'verbose'	=> \$VERBOSE,
	'pretty'	=> \$pretty,
	'days=i'	=> \$NUMDAYS,
	'bbcregion=s'	=> \$BBCREGION,
	'itvregion=s'	=> \$ITVREGION,
	'output=s'	=> \$outputfile,
	'extrachannels=s'	=> \$extrachannels,
	'onlychannels=s'	=> \$CHANNELLIST,
	'plex=i'		=> \$PLEX,
	'debug'		=> \$DEBUG,
	'verify'	=> \$VERIFY,
	'help|?'	=> \$help,
) or die ("Syntax Error!  Try $0 --help");

if ($FURL_OK)
{
	warn("Using Furl for fetching http:// and https:// requests.\n") if ($VERBOSE);
	$ua = Furl->new(
				agent => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:67.0) Gecko/20100101 Firefox/67.0',
				timeout => 45,
#				headers => [ 'Accept-Encoding' => 'application/json' ],
				headers => ['Connection'	=> 'keep-alive'],
				ssl_opts => {SSL_verify_mode => 0}
			);
} else {
	warn("Using LWP::UserAgent for fetching http:// and https:// requests.\n") if ($VERBOSE);
	$ua = LWP::UserAgent->new;
	$ua->agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:67.0) Gecko/20100101 Firefox/67.0");
	#$ua->default_header( 'Accept-Encoding' => 'application/json');
	#$ua->default_header( 'Accept-Charset' => 'utf-8');
}
buildregions($ua);

extrachannelsusage() if ($extrachannels =~ /help/i);
usage() if ($help);
usage() if (!defined($BBCREGION) and (!defined($CHANNELLIST)));
usage() if (!defined($ITVREGION) and (!defined($CHANNELLIST)));



my $validregion = 1;###FIXME

die(	  "\n"
	. "Invalid region specified.  Please use one of the following:\n\t\t"
	. join("\n\t\t", (map { "$_->{id}\t=\t$_->{name}" } @$BBCREGIONS) )
	. "\n\n"
   ) if (!$validregion); # (!defined($REGIONS->{$REGION}));

warn("Options...\nbbcregion=$BBCREGION, itvregion=$ITVREGION, output=$outputfile, days = $NUMDAYS, Verbose = $VERBOSE, pretty = $pretty, \n\n") if ($VERBOSE);

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

definechannels($extrachannels) if (!(defined($CHANNELLIST)));
# Initialise here (connections to the same server will be cached)


getchannels($ua);
getepg($ua);

warn("Closing Cache files.\n") if ($VERBOSE);
# close out both DBs and write the new temp one over the saved one

&close_cache();

# reset die handler
$SIG{__DIE__} = \&CORE::die;

warn("Replacing old Cache file with the new one...\n") if ($VERBOSE);
move($TMPCACHEFILE, $CACHEFILE);

my $XML = XML::Writer->new( OUTPUT => 'self', DATA_MODE => ($pretty ? 1 : 0), DATA_INDENT => ($pretty ? 8 : 0) );
$XML->xmlDecl("ISO-8859-1");
$XML->doctype("tv", undef, "xmltv.dtd");
$XML->startTag('tv', 'source-info-name' => "https://github.com/markcs/xml_tv", 'generator-info-url' => "http://www.xmltv.org/");

printchannels(\$XML);
printepg(\$XML);
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

sub definechannels
{
	my $extrachannels = shift;
	$CHANNELLIST = "";
	my $bbcfound = 0;
	my $itvfound = 0;
	foreach my $key (keys %{$BBCREGIONS})
	{
		if ($key eq $BBCREGION)
		{
			$bbcfound = 1;
			foreach my $regionkey (@{$BBCREGIONS->{$key}})
			{
				$CHANNELLIST = $CHANNELLIST.$regionkey->{number}.",";
			}
		}
	}

	foreach my $key (keys %{$ITVREGIONS})
	{
		if ($key eq $ITVREGION)
		{
			$itvfound = 1;
			foreach my $regionkey (@{$ITVREGIONS->{$key}})
			{
				$CHANNELLIST = $CHANNELLIST.$regionkey->{number}.",";
			}
		}
	}
	foreach my $key (@$MAINCHANNELS)
	{
		$CHANNELLIST = $CHANNELLIST.$key->{number}."," if ($key->{name} ne 'S4C');
	}
	die usage() if (!($bbcfound) && !($itvfound));
	$CHANNELLIST = $CHANNELLIST.$extrachannels if (defined($extrachannels));
	$CHANNELLIST =~ s/,$//;
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
	while (defined( my $episodedata = $INQ->dequeue()))
	{
		my $url = "https://immediate-prod.apigee.net/broadcast-content/1/episodes/" . $episodedata;
		warn("Using $tua to fetch $url\n") if ($DEBUG);
		print "." if ($VERBOSE);
		my $res = $tua->get($url);
		if (!$res->is_success)
		{
			warn(threads->self()->tid(). ": Thread Fetch FAILED for: $url (" . $res->code . ")\n");
			if ($res->code > 399 and $res->code < 500)
			{
				$OUTQ->enqueue("$episodedata|FAILED");
			} elsif ($res->code > 499) {
				$OUTQ->enqueue("$episodedata|ERROR");
			} else {
				# shouldn't be reached
				$OUTQ->enqueue("$episodedata|UNKNOWN")
			}
		} else {
			$OUTQ->enqueue($episodedata . "|" . $res->content);
			warn(threads->self()->tid(). ": Thread Fetch SUCCESS for: $url\n") if ($DEBUG);
		}
	}
}

sub getchannels
{
	my $ua = shift;
	my $channelcount = 0;
	my $dt = DateTime->now;
	$dt->set_time_zone( 'Europe/London' );
	my $startdate = $dt->dmy . "%2012:00:00";
	my $url = "https://immediate-prod.apigee.net/broadcast/v1/schedule?startdate=".$startdate."&hours=1&totalwidthunits=898&channels=".$CHANNELLIST;
	warn("Getting all program data for all channels ($url)...\n") if ($VERBOSE);
	my $res = $ua->get($url);
	my $data ;
	eval
	{
		$data = JSON->new->relaxed(1)->allow_nonref(1)->decode($res->content);
		1;
	};
	$data = $data->{Channels};
	print "\n=============================\nChannel Number\tChannel Name\n" if ($VERIFY);
	for (my $count = 0; $count < @$data; $count++)
	{
		for (my $packagecount = 0; $packagecount < @{$data->[$count]->{Packages}}; $packagecount++)
		{
			if ($data->[$count]->{Packages}->[$packagecount]->{Package} =~ /Freeview/)
			{
				$CHANNELDATA[$channelcount]->{id} = $data->[$count]->{Packages}->[$packagecount]->{EpgChannel}.".".$data->[$count]->{Id}.".radiotimes.com";
				$CHANNELDATA[$channelcount]->{lcn} = $data->[$count]->{Packages}->[$packagecount]->{EpgChannel};
			}
		}
		$CHANNELDATA[$channelcount]->{name} = sanitizeHTML($data->[$count]->{DisplayName});
		#$CHANNELDATA[$channelcount]->{name} =~ s/&amp;/&/g;

		#$CHANNELDATA[$channelcount]->{icon} = sanitizeURL($data->[$count]->{Image});
		$CHANNELDATA[$channelcount]->{icon} = sanitizeHTML($data->[$count]->{Image});
		#$CHANNELDATA[$channelcount]->{icon} =~ s/&amp;/&/g;

		warn("Got channel $CHANNELDATA[$channelcount]->{id} - $CHANNELDATA[$channelcount]->{name}  ...\n") if ($VERBOSE);
		if ($VERIFY) {

			$CHANNELDATA[$channelcount]->{id} =~ s/^([0-9]+)\.([0-9]+).*/$1/;
			my $radiotimesid = $2;
			print "$CHANNELDATA[$channelcount]->{id}\t\t$CHANNELDATA[$channelcount]->{name} ($radiotimesid)\n";
		}
		$channelcount++

	}
	exit() if ($VERIFY);
}

sub getepg
{
	my $ua = shift;
	my $channelcount = 0;
	my $showcount = 0;
	my $nl = 0;
	for(my $day = -1; $day < $NUMDAYS; $day++)
	{
		my $seconds = $day*86400;
		my $dt = DateTime->now;
		$dt->set_time_zone( 'Europe/London' );
		$dt = $dt + DateTime::Duration->new( seconds => $seconds );
		my $startdate = $dt->dmy;
		my $res;
		my $try = 0;
		while ($try < 5)
		{
			my $url = "https://immediate-prod.apigee.net/broadcast/v1/schedule?startdate=".$startdate."%2012:00:00&hours=24&totalwidthunits=898&channels=".$CHANNELLIST;
			warn("\n\nGetting all program data for channels for $startdate ($url)...\n") if ($VERBOSE);
			$res = $ua->get($url);
			last if ($res->is_success());
			warn ("Timeout in receiving data on try $try (Code ".$res->code."). Sleeping for 5 seconds .... \n") if ($VERBOSE);
			sleep 5;
			$try++;
		}
		my $data;
		eval
		{
			$data = JSON->new->relaxed(1)->allow_nonref(1)->decode($res->content);
			1;
		};
		my $tmpchanneldata = $data->{Channels};
		#print Dumper $tmpchanneldata;
		for (my $channelcount = 0; $channelcount < @$tmpchanneldata; $channelcount++)
		{
			my $id;
			for (my $packagecount = 0; $packagecount < @{$tmpchanneldata->[$channelcount]->{Packages}}; $packagecount++)
			{
				if ($tmpchanneldata->[$channelcount]->{Packages}->[$packagecount]->{Package} =~ /Freeview/)
				{
					$id = $tmpchanneldata->[$channelcount]->{Packages}->[$packagecount]->{EpgChannel}.".".$tmpchanneldata->[$channelcount]->{Id}.".radiotimes.com";
				}
			}
			my $shows = $tmpchanneldata->[$channelcount]->{TvListings};
			my $enqueued = 0;

			for (my $listings = 0; $listings < @$shows; $listings++)
			{
				my $showdata = $tmpchanneldata->[$channelcount]->{TvListings}->[$listings];
				if ((defined($showdata->{Specialisation}) and ($showdata->{Specialisation}) =~ /tv/i))
				{
						my $episodeid = $showdata->{EpisodeId};

						if (!exists $dbm_hash{$episodeid} || $dbm_hash{$episodeid} eq "$episodeid|undef")
						{
							warn("No cache data for $episodeid, requesting...\n") if ($DEBUG);
							$INQ->enqueue($episodeid);
							++$enqueued; # Keep track of how many fetches we do
						}
						else
						{
							warn("Using cache for $episodeid.\n") if ($DEBUG);
							#$episodedata = $dbm_hash{$episodeid};
							$thrdret{$episodeid} = $dbm_hash{$episodeid};

						}
				}
			}
			if ($enqueued > 0) {
				for (my $l = 0;$l < $enqueued; ++$l)
				{
					# At this point all the threads should have all the URLs in the queue and
					# will resolve them independently - this means they will not necessarily
					# be in the right order when we get them back.  That said, because we will
					# reuse these threads and queues on each loop we wait here to get back
					# all the results before we continue.
					my ($episodeid, $result) = split(/\|/, $OUTQ->dequeue(), 2);
					warn("$episodeid = $result\n") if ($DEBUG);
					$thrdret{$episodeid} = $result;
					if ($thrdret{$episodeid} eq "FAILED")
					{
						warn("Unable to connect ... skipping\n");
						next;
					} elsif ($thrdret{$episodeid} eq "ERROR") {
						warn ("FATAL: Unable to connect ... (error code >= 500 have you need banned?)\n");
						next;
					} elsif ($thrdret{$episodeid} eq "UNKNOWN") {
						die("FATAL: Unable to connect ... (Unknown Error!)\n");
					}
					else {

						$dbm_hash{$episodeid} = $thrdret{$episodeid};
					}
				}
				if ($VERBOSE && $enqueued)
				{
					local $| = 1;
					print " ";
					$nl++;
				};
			}
			for (my $listings = 0; $listings < @$shows; $listings++)
			{
				my $showdata = $tmpchanneldata->[$channelcount]->{TvListings}->[$listings];
				$showdata->{StartTimeMF} =~ s/Z/ 01:00/;
				$showdata->{EndTimeMF} =~ s/Z/ 01:00/;
				#$GUIDEDATA[$showcount]->{start} = toLocalTimeString($showdata->{StartTimeMF},'Europe/London');
				#$GUIDEDATA[$showcount]->{stop} = toLocalTimeString($showdata->{EndTimeMF},'Europe/London');
				$GUIDEDATA[$showcount]->{start} = toLocalTimeString($showdata->{StartTimeMF},'UTC');
				$GUIDEDATA[$showcount]->{stop} = toLocalTimeString($showdata->{EndTimeMF},'UTC');
	#			$GUIDEDATA[$showcount]->{start} =~ s/[-: ]//g;
	#			$GUIDEDATA[$showcount]->{start} =~ s/Z/ \+00:00/g;
	#			$GUIDEDATA[$showcount]->{stop} =~ s/[-: ]//g;
	#			$GUIDEDATA[$showcount]->{stop} =~ s/Z/ \+00:00/g;
				$GUIDEDATA[$showcount]->{start} =~ s/[-T:]//g;
				$GUIDEDATA[$showcount]->{start} =~ s/\+/ \+/g;
				$GUIDEDATA[$showcount]->{stop} =~ s/[-T:]//g;
				$GUIDEDATA[$showcount]->{stop} =~ s/\+/ \+/g;
				$GUIDEDATA[$showcount]->{id} = $id;
				$GUIDEDATA[$showcount]->{desc} = sanitizeHTML($showdata->{Description}) if (defined($GUIDEDATA[$showcount]->{desc}));
				#$GUIDEDATA[$showcount]->{desc} =~ s/&amp;/&/g if (defined($GUIDEDATA[$showcount]->{desc}));
				$GUIDEDATA[$showcount]->{url} = sanitizeHTML($showdata->{Image});
				#$GUIDEDATA[$showcount]->{url} =~ s/&amp;/&/g;
				$GUIDEDATA[$showcount]->{title} = sanitizeHTML($showdata->{Title});
				#$GUIDEDATA[$showcount]->{title} =~ s/&amp;/&/g;
				#if (defined($showdata->{EpisodePositionInSeries}))

				if ((defined($showdata->{Specialisation})) and ($showdata->{Specialisation} =~ /tv/i))
				{
					#TEMP INCASE WE FAILED TO COLLECT DATA BELOW
					if (defined($showdata->{EpisodePositionInSeries}))
					{
						$GUIDEDATA[$showcount]->{episode} = $showdata->{EpisodePositionInSeries};
						$GUIDEDATA[$showcount]->{episode} =~ s/(.*)\/.*/$1/;
					}
					else {
						$GUIDEDATA[$showcount]->{episode} = 1;
					}
					$GUIDEDATA[$showcount]->{season} = "2019";
					#getseries($ua,$showdata->{EpisodePositionInSeries});
					my $episodeid = $showdata->{EpisodeId};
					my $episodedata = $thrdret{$episodeid};
					if (($episodedata ne "FAILED") and ($episodedata ne "ERROR"))
					{
						eval
						{
							$episodedata = JSON->new->relaxed(1)->allow_nonref(1)->decode($episodedata);
							1;
						};
						$GUIDEDATA[$showcount]->{subtitle} = $episodedata->{display_title}->{subtitle};
						$GUIDEDATA[$showcount]->{episode} = $episodedata->{episode_number};
						$GUIDEDATA[$showcount]->{season} = $episodedata->{series_number};
					}
				}
				if ($showdata->{IsRepeat} eq "1")
				{
					$GUIDEDATA[$showcount]->{originalairdate} = $showdata->{StartTimeMF};# $episodeYear."-".$episodeMonth."-".$episodeDay." ".$episodeHour.":".$episodeMinute.":00";#"$1-$2-$3 $4:$5:00";
					$GUIDEDATA[$showcount]->{originalairdate} =~ s/Z//;
					$GUIDEDATA[$showcount]->{previouslyshown} = $GUIDEDATA[$showcount]->{originalairdate};#"$1-$2-$3";
					$GUIDEDATA[$showcount]->{previouslyshown} =~ s/(.*)\s.*/$1/;
				}
				$GUIDEDATA[$showcount]->{category} = $showdata->{Genre} if (defined($showdata->{Genre}));
				$showcount++;
			}
		}
	}
	warn("\nProcessed a total of $showcount shows ...\n") if ($VERBOSE);
}


sub printchannels
{
	my ($XMLRef) = @_;
	foreach my $channel (@CHANNELDATA)
	{
		$XML->startTag('channel', 'id' => $channel->{id});
		$XML->dataElement('display-name', $channel->{name});
		$XML->dataElement('lcn', $channel->{lcn}) if ($PLEX);
		$XML->emptyTag('icon', 'src' => $channel->{icon}) if (defined($channel->{icon}));
		$XML->endTag('channel');
	}
	return;
}

sub printepg
{
	my ($XMLRef) = @_;
	foreach my $items (@GUIDEDATA)
	{
		my $movie = 0;
		my $originalairdate = "";

		${$XMLRef}->startTag('programme', 'start' => "$items->{start}", 'stop' => "$items->{stop}", 'channel' => "$items->{id}");
		${$XMLRef}->dataElement('title', sanitizeText($items->{title}));
		${$XMLRef}->dataElement('sub-title', sanitizeText($items->{subtitle})) if (defined($items->{subtitle}));
		${$XMLRef}->dataElement('desc', sanitizeText($items->{desc})) if (defined($items->{desc}));
		${$XMLRef}->dataElement('category', sanitizeText($items->{category})) if (defined($items->{category}));
		${$XMLRef}->emptyTag('icon', 'src' => $items->{url}) if (defined($items->{url}));
		if (defined($items->{episode}))
		{
			$items->{season} = '2019' if (!defined($items->{season}));
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
		${$XMLRef}->endTag('programme');
	}
}


sub sanitizeHTML
{
	my $t = shift;
	$t =~ s/&#39;/'/g;
	$t =~ s/&amp;/&/g;
	return $t;
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
	##2019-08-07 16:00:00Z
	my ($year, $month, $day, $hour, $min, $sec, $offset) = $fulldate =~ /(\d+)-(\d+)-(\d+)\s(\d+):(\d+):(\d+)(.*)/;#S$1E$2$3$4$5$6$7/;
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
		$offset =~ s/[\s:]//g;
		#$offset = "+".$offset;
	}

	my $dt = DateTime->new(
		 	year		=> $year,
		 	month		=> $month,
		 	day			=> $day,
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

sub buildregions {
	my $ua = shift;
	my $url = "https://immediate-prod.apigee.net/broadcast/v1/schedulesettings?media=tv&platform=freeview";
	my $res = $ua->get($url);
	die("Unable to connect to Radio Times in buildregions.\n") if (!$res->is_success);
	#my $data = $res->content;
	#my $region_json = decode_json($data);
	my $region_json = JSON->new->relaxed(1)->allow_nonref(1)->decode($res->content);
	my $bbc_region = $region_json->{BbcRegions};
	my $itv_region = $region_json->{ItvRegions};
	my $main_channels = $region_json->{MainChannels};
	my $other_channels = $region_json->{OtherChannels};

	for (my $count = 0; $count < @$bbc_region; $count++)
	{
		for (my $channelcount = 0; $channelcount < @{$bbc_region->[$count]->{Channels}}; $channelcount++)
		{
			$BBCREGIONS->{$bbc_region->[$count]->{Region}}->[$channelcount]->{name} = $bbc_region->[$count]->{Channels}->[$channelcount]->{Name};
			$BBCREGIONS->{$bbc_region->[$count]->{Region}}->[$channelcount]->{number} = $bbc_region->[$count]->{Channels}->[$channelcount]->{Id};
		}
	}
	for (my $count = 0; $count < @$itv_region; $count++)
	{
		for (my $channelcount = 0; $channelcount < @{$itv_region->[$count]->{Channels}}; $channelcount++)
		{
			$ITVREGIONS->{$itv_region->[$count]->{Region}}->[$channelcount]->{name} = $itv_region->[$count]->{Channels}->[$channelcount]->{Name};
			$ITVREGIONS->{$itv_region->[$count]->{Region}}->[$channelcount]->{number} = $itv_region->[$count]->{Channels}->[$channelcount]->{Id};
		}
	}
	for (my $count = 0; $count < @$main_channels; $count++)
	{
		my $name = $main_channels->[$count]->{Name};
		my $number = $main_channels->[$count]->{Id};
		my %data = ( name => $name, number => $number );
		if (defined($main_channels->[$count]->{Region}))
		{
			if ($main_channels->[$count]->{Region} =~ /BBC/)
			{
				my $found = 0;
				foreach my $checkname (@{$BBCREGIONS->{$main_channels->[$count]->{Region}}})
				{
					$found = 1 if ($checkname->{name} eq $name);
				}
				push( @{$BBCREGIONS->{$main_channels->[$count]->{Region}}}, \%data ) if (!$found);
			}
			elsif ($main_channels->[$count]->{Region} =~ /ITV/)
			{
				my $found = 0;
				foreach my $checkname (@{$ITVREGIONS->{$main_channels->[$count]->{Region}}})
				{
					$found = 1 if ($checkname->{name} eq $name);
				}
				push( @{$ITVREGIONS->{$main_channels->[$count]->{Region}}}, \%data ) if (!$found);
			}
			else {
				push (@{$MAINCHANNELS}, \%data);
			}
		}
	}
	for (my $count = 0; $count < @$other_channels; $count++)
	{
		my $name = $other_channels->[$count]->{Name};
		my $number = $other_channels->[$count]->{Id};
		my %data = ( name => $name, number => $number );
		if (defined($other_channels->[$count]->{Region}))
		{
			if ($other_channels->[$count]->{Region} =~ /BBC/)
			{
				my $found = 0;
				foreach my $checkname (@{$BBCREGIONS->{$other_channels->[$count]->{Region}}})
				{
					$found = 1 if ($checkname->{name} eq $name);
				}
				push( @{$BBCREGIONS->{$other_channels->[$count]->{Region}}}, \%data ) if (!$found);
			}
			elsif ($other_channels->[$count]->{Region} =~ /ITV/)
			{
				my $found = 0;
				foreach my $checkname (@{$ITVREGIONS->{$other_channels->[$count]->{Region}}})
				{
					$found = 1 if ($checkname->{name} eq $name);
				}
				push( @{$ITVREGIONS->{$other_channels->[$count]->{Region}}}, \%data ) if (!$found);
			}
			else {
				push (@{$OTHERCHANNELS}, \%data);
			}
		}
	}
}

sub usage
{
	print    "Usage:\n"
		. "\t$0 [--bbcregion=<bbcregion>] [--itvregion=<itvregion>] [--onlychannels=<channel numbers.] [--extrachannels=<channel numbers> ] [--output <filename>] [--output <filename>] [--days=<days to collect>] [--pretty] [--verify] [--VERBOSE] [--help|?]\n"
		. "\n\tWhere:\n\n"
		. "\t--bbcregion=<bbcregion>\t\t\tThis defines which BBC guide to parse. It is mandatory if <onlychannels> is not defined. Refer below for a list of regions.\n"
		. "\t--itvregion=<itvregion>\t\t\tThis defines which ITV guide to parse. It is mandatory if <onlychannels> is not defined. Refer below for a list of regions.\n"
		. "\t--onlychannels=<channel list>\t\tThis defines the channels to collect and will ignore any other defined channel options.\n"
		. "\t--extrachannels=<channel list>\t\tThis defines the extra channels to collect. Use option '--extrachannels help' for complete list.\n"
		. "\t--days=<days to collect>\t\tThis defaults to 7 days and can be no more than 7.\n"
		. "\t--pretty\t\t\t\tOutput the XML with tabs and newlines to make human readable.\n"
		. "\t--output <filename>\t\t\tWrite to the location and file specified instead of standard output.\n"
		. "\t--verbose\t\t\t\tVerbose Mode (prints processing steps to STDERR).\n"
		. "\t--verify\t\t\t\tPrints the actual LCN numbers and channel names to verify what will be collected.\n"
		. "\t--help\t\t\t\t\tWill print this usage and exit!\n"
		. "\n\n\t!!! NOTE: Channel numbers are not the same channel numbers seen on the TV, but a number used by radiotimes.com to identify the channel. Do not get them mixed up!!!!.\n"
		. "\t!!! NOTE: To see a list of radiotimes channel numbers and names use option --extrachannels help!!!!.\n"
		. "\n\t  <bbcregion> is one of the following:\n";
		foreach my $key (keys %{$BBCREGIONS})
		{
			print "\t\t\t$key\n";
		}
		print "\n\t  <itvregion> is one of the following:\n";
		foreach my $key (keys %{$ITVREGIONS})
		{
			print "\t\t\t$key\n";
		}

		die;
}

sub extrachannelsusage
{
	print    "Usage:\n"
		. "\t$0 --bbcregion=<bbcregion> --itvregion=<itvregion> [--extrachannels=<channel numbers> ] [--output <filename>] [--days=<days to collect>] [--pretty] [--VERBOSE] [--help|?]\n"
		. "Option --extrachannels is a comma separate list of channel numbers as defined by radiotime below\n"
		. "\nBy default, all channels under 'Main Channels' are included and channels matching the regions for 'BBC Channels' and 'ITV Channels' are included\n"
		. "\n!!!!!!!!! NOTE: The number IS NOT A CHANNEL NUMBER. It is an identifier used by RadioTimes and does not correspond to the channel numbers seen on the TV !!!!!!!!!!\n";

	print "\n\n\t\t\tNumber to use\t\tChannel Name\n";
	my $allchannels = "";
	foreach my $key (@{$OTHERCHANNELS})
	{
		print "\t\t\t$key->{number}\t\t\t$key->{name}\n";
		$allchannels = $key->{number}.",".$allchannels;
	}
	print "\n=====================================\nMAIN Channels\n";

	foreach my $key (@$MAINCHANNELS)
	{
		print "\t\t\t$key->{number}\t\t\t$key->{name}\n";
		$allchannels = $key->{number}.",".$allchannels;
	}

	print "\n=====================================\nITV Channels\n";
	foreach my $key (keys %{$ITVREGIONS})
	{
		foreach my $regionkey (@{$ITVREGIONS->{$key}})
			{
				print "\t\t\t$regionkey->{number}\t\t\t $key - $regionkey->{name}\n";
				$allchannels = $regionkey->{number}.",".$allchannels;
			}

	}

	print "\n=====================================\nBBC Channels\n";
	foreach my $key (keys %{$BBCREGIONS})
	{
		foreach my $regionkey (@{$BBCREGIONS->{$key}})
			{
				print "\t\t\t$regionkey->{number}\t\t\t $key - $regionkey->{name}\n";
				$allchannels = $regionkey->{number}.",".$allchannels;
			}

	}
	print "$allchannels\n";
	die;
}