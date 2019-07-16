#!/usr/bin/perl

use strict;
use warnings;

my %thr = ();
my $threading_ok = eval 'use threads; 1';
if ($threading_ok)
{
        use threads;
#        use threads::shared;
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

use DB_File;

my %map = (
	 '&' => 'and',
);
my $chars = join '', keys %map;

my @CHANNELDATA;
my $FVICONS;
my @GUIDEDATA;
my $REGION_TIMEZONE;
my $REGION_NAME;
my $CACHEFILE = "yourtv.db";
my $TMPCACHEFILE = ".$$.yourtv-tmp-cache.db";
my $ua;

my (%dbm_hash, %thrdret);
local (*DBMRO, *DBMRW);

my ($DEBUG, $VERBOSE, $pretty, $usefreeviewicons, $NUMDAYS, $ignorechannels, $REGION, $outputfile, $help) = (0, 0, 0, 0, 7, undef, undef, undef, undef);
GetOptions
(
	'debug'		=> \$DEBUG,
	'verbose'	=> \$VERBOSE,
	'pretty'	=> \$pretty,
	'days=i'	=> \$NUMDAYS,
	'region=s'	=> \$REGION,
	'output=s'	=> \$outputfile,
	'ignore=s'	=> \$ignorechannels,
	'fvicons'	=> \$usefreeviewicons,
	'cachefile'	=> \$CACHEFILE,
	'help|?'	=> \$help,
) or die ("Syntax Error!  Try $0 --help");
die usage() if ($help);

die(usage() ) if (!defined($REGION));

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
}

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

warn("Options...\nregion=$REGION, output=$outputfile, days = $NUMDAYS, fvicons = $usefreeviewicons, Verbose = $VERBOSE, pretty = $pretty, \n\n") if ($VERBOSE);

# Initialise here (connections to the same server will be cached)
my @IGNORECHANNELS;
@IGNORECHANNELS = split(/,/,$ignorechannels) if (defined($ignorechannels));

getFVIcons($ua) if ($usefreeviewicons);

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

getchannels($ua);
getepg($ua);

warn("Closing Queues...\n") if ($VERBOSE);
# this will close the queues
$INQ->end();
$OUTQ->end();
# joining all threads

# while ->detach() threads they will shutdown automatically by
# closing the queues.  So this message is just informational
warn("Shutting down all threads...\n") if ($VERBOSE);
#foreach my $thr ( threads->list() )
#{
#	warn("Joining thread $thr..\n") if ($DEBUG);
#	$thr->join();
#}

warn("Closing Cache files.\n") if ($VERBOSE);
# close out both DBs and write the new temp one over the saved one
untie(%dbm_hash);
untie(%thrdret);
close DBMRW;
close DBMRO;

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
			$OUTQ->enqueue("$airingid|undef");
		} else {
			$OUTQ->enqueue($airingid . "|" . $res->content);
			warn(threads->self()->tid(). ": Thread Fetch SUCCESS for: $url\n") if ($DEBUG);
		}
	}
}

sub getchannels
{
	my $ua = shift;
	my $data;
	warn("Getting channel list from YourTV ...\n") if ($VERBOSE);
	my $url = "https://www.yourtv.com.au/api/regions/" . $REGION . "/channels";
	my $res = $ua->get($url);

	die("Unable to connect to FreeView.\n") if (!$res->is_success);

	$data = $res->content;
	my $tmpchanneldata = decode_json($data);
	for (my $count = 0; $count < @$tmpchanneldata; $count++)
	{
        next if ( ( grep( /^$tmpchanneldata->[$count]->{number}$/, @IGNORECHANNELS ) ) );
		$CHANNELDATA[$count]->{tv_id} = $tmpchanneldata->[$count]->{id};
		$CHANNELDATA[$count]->{name} = $tmpchanneldata->[$count]->{description};
		$CHANNELDATA[$count]->{id} = $tmpchanneldata->[$count]->{number}.".yourtv.com.au";
		$CHANNELDATA[$count]->{lcn} = $tmpchanneldata->[$count]->{number};
		$CHANNELDATA[$count]->{icon} = $tmpchanneldata->[$count]->{logo}->{url};
		$CHANNELDATA[$count]->{icon} = $FVICONS->{$tmpchanneldata->[$count]->{number}} if (defined($FVICONS->{$tmpchanneldata->[$count]->{number}}));
		#FIX SBS ICONS
		if (($usefreeviewicons) && (!defined($CHANNELDATA[$count]->{icon})) && ($CHANNELDATA[$count]->{name} =~ /SBS/)) {
			$tmpchanneldata->[$count]->{number} =~ s/(\d)./$1/;
			$CHANNELDATA[$count]->{icon} = $FVICONS->{$tmpchanneldata->[$count]->{number}} if (defined($FVICONS->{$tmpchanneldata->[$count]->{number}}));
		}
		warn("Got channel $CHANNELDATA[$count]->{id} - $CHANNELDATA[$count]->{name}  ...\n") if ($VERBOSE);
	}
}

sub getepg
{
	my $ua = shift;
	my $showcount = 0;
	my $url;

	warn(" \n") if ($VERBOSE);
	for(my $day = 0; $day < $NUMDAYS; $day++)
	{
		my $day = nextday($day);
		my $id;
		my $url = URI->new( 'https://www.yourtv.com.au/api/guide/' );
		$url->query_form(day => $day, timezone => $REGION_TIMEZONE, format => 'json', region => $REGION);
		warn("Getting channel program listing for $REGION_NAME ($REGION) for $day ($url)...\n") if ($VERBOSE);
		my $res = $ua->get($url);
		die("Unable to connect to YourTV for $url.\n") if (!$res->is_success);
		my $data = $res->content;
		my $tmpdata;
		eval
		{
			$tmpdata = decode_json($data);
			1;
		};
		my $chandata = $tmpdata->[0]->{channels};
		if (defined($chandata))
		{
			for (my $channelcount = 0; $channelcount < @$chandata; $channelcount++)
			{
				next if (!defined($chandata->[$channelcount]->{number}));
				next if ( ( grep( /^$chandata->[$channelcount]->{number}$/, @IGNORECHANNELS ) ) );

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
						if ($day eq "today" || !exists $dbm_hash{$airing} || $dbm_hash{$airing} eq "$airing|undef")
						{
							warn("No cache data for $airing, requesting...\n") if ($DEBUG);
							$INQ->enqueue($airing);
							++$enqueued; # Keep track of how many fetches we do
						} else {
							warn("Using cache for $airing.\n") if ($DEBUG);
							my $data = $dbm_hash{$airing};
							warn("Got cache data for $airing.\n") if ($DEBUG);
							$thrdret{$airing} = $data;
							warn("Wrote cache data for $airing.\n") if ($DEBUG);
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
				print "\n" if ($VERBOSE && $enqueued);
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
						die("Unable to connect to YourTV for https://www.yourtv.com.au/api/airings/$airing\n") if ($thrdret{$airing} eq "undef");
						eval
						{
							$showdata = decode_json($thrdret{$airing});
							1;
						};
						if (defined($showdata))
						{
							$GUIDEDATA[$showcount]->{id} = $id;
							$GUIDEDATA[$showcount]->{airing_tmp} = $airing;
							$GUIDEDATA[$showcount]->{desc} = $showdata->{synopsis};
							$GUIDEDATA[$showcount]->{subtitle} = $showdata->{episodeTitle};
							$GUIDEDATA[$showcount]->{url} = $showdata->{program}->{image};
							$GUIDEDATA[$showcount]->{start} = toLocalTimeString($showdata->{date},$REGION_TIMEZONE);
							$GUIDEDATA[$showcount]->{stop} = addTime($showdata->{duration},$GUIDEDATA[$showcount]->{start});
							$GUIDEDATA[$showcount]->{start} =~ s/[-T:]//g;
							$GUIDEDATA[$showcount]->{start} =~ s/\+/ \+/g;
							$GUIDEDATA[$showcount]->{stop} =~ s/[-T:]//g;
							$GUIDEDATA[$showcount]->{stop} =~ s/\+/ \+/g;
							$GUIDEDATA[$showcount]->{channel} = $showdata->{service}->{description};
							$GUIDEDATA[$showcount]->{title} = $showdata->{title};
							$GUIDEDATA[$showcount]->{rating} = $showdata->{classification};
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

							if ($showdata->{programType}->{id} eq "1") {
								push(@{$GUIDEDATA[$showcount]->{category}}, $showdata->{programType}->{name});
							}
							if ($showdata->{programType}->{id} eq "2") {
								push(@{$GUIDEDATA[$showcount]->{category}}, $showdata->{programType}->{name});
							}
							if ($showdata->{programType}->{id} eq "3") {
								push(@{$GUIDEDATA[$showcount]->{category}}, $showdata->{programType}->{name});
								$GUIDEDATA[$showcount]->{episode} = $showdata->{episodeNumber} if (defined($showdata->{episodeNumber}));
								$GUIDEDATA[$showcount]->{season} = "1";
							}
							if ($showdata->{programType}->{id} eq "4") {
								#push(@{$GUIDEDATA[$showcount]->{category}}, $showdata->{programType}->{id});
								$GUIDEDATA[$showcount]->{premiere} = "1";
								$GUIDEDATA[$showcount]->{originalairdate} = $episodeYear."-".$episodeMonth."-".$episodeDay." ".$episodeHour.":".$episodeMinute.":00";#"$1-$2-$3 $4:$5:00";
								$GUIDEDATA[$showcount]->{episode} = $showdata->{episodeNumber} if (defined($showdata->{episodeNumber}));
							}
							if ($showdata->{programType}->{id} eq "5") {
								#push(@{$GUIDEDATA[$showcount]->{category}}, $showdata->{programType}->{id});
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
							if (defined($showdata->{repeat} ) )
							{
								$GUIDEDATA[$showcount]->{originalairdate} = $episodeYear."-".$episodeMonth."-".$episodeDay." ".$episodeHour.":".$episodeMinute.":00";#"$1-$2-$3 $4:$5:00";
								$GUIDEDATA[$showcount]->{previouslyshown} = "$episodeYear-$episodeMonth-$episodeDay";#"$1-$2-$3";
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
	foreach my $channel (@CHANNELDATA)
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
	foreach my $items (@GUIDEDATA)
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

sub addTime
{
	my ($duration, $startTime) = @_;
	my ($year, $month, $day, $hour, $min, $sec, $offset) = $startTime =~ /(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)(.*)/;#S$1E$2$3$4$5$6$7/;
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
	my $endTime = $dt + DateTime::Duration->new( minutes => $duration );
	my $ymd = $endTime->ymd;
	my $hms = $endTime->hms;
	my $returntime = $ymd . "T" . $hms . $offset;
	return ($returntime);
}

sub buildregions {
	my $url = "https://www.yourtv.com.au/guide/";
	my $res = $ua->get($url);
	die("Unable to connect to FreeView.\n") if (!$res->is_success);
	my $data = $res->content;
	$data =~ s/\R//g;
	$data =~ s/.*window.regionState\s+=\s+(\[.*\]);.*/$1/;
	my $region_json = decode_json($data);
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

sub getFVIcons
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
		my $tmpchanneldata = decode_json($data);
		$tmpchanneldata = $tmpchanneldata->{data};
		for (my $count = 0; $count < @$tmpchanneldata; $count++)
		{
			$FVICONS->{$tmpchanneldata->[$count]->{lcn}} = $tmpchanneldata->[$count]->{related}->{images}[0]->{url};
        }
	}
}


sub usage
{
	return    "Usage:\n"
		. "\t$0 --region=<region> [--output <filename>] [--days=<days to collect>] [--ignore=<channel to ignore>] [--fvicons] [--pretty] [--VERBOSE] [--help|?]\n"
		. "\n\tWhere:\n\n"
		. "\t--region=<region>\t\tThis defines which tv guide to parse. It is mandatory. Refer below for a list of regions.\n"
		. "\t--days=<days to collect>\tThis defaults to 7 days and can be no more than 7.\n"
		. "\t--pretty\t\t\tOutput the XML with tabs and newlines to make human readable.\n"
		. "\t--output <filename>\t\tWrite to the location and file specified instead of standard output.\n"
		. "\t--ignore=<channel to ignore>\tA comma separated list of channel numbers to ignore. The channel number is matched against the lcn tag within the xml.\n"
		. "\t--fvicons\t\t\tUse Freeview icons if they exist.\n"
		. "\t--verbose\t\t\tVerbose Mode (prints processing steps to STDERR).\n"
		. "\t--help\t\t\t\tWill print this usage and exit!\n"
		. "\t  <region> is one of the following:\n\t\t"
		. join("\n\t\t", (map { "$_->{id}\t=\t$_->{name}" } @REGIONS) )
		. "\n\n";
}
