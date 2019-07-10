#!/usr/bin/perl

# ^^ this is not good on a mac if you're using macports, it also
# wont be good on *BSD because that should be /usr/local

use strict;
use warnings;

use JSON;
use POSIX qw(strftime);
use LWP::UserAgent;
use XML::Writer;
use Time::Local;
use Getopt::Long;

# You don't actually need this as XML::Writer will turn
# & into &amp; automatically
my %map = (
    '&' => 'and',
);

my $chars = join '', keys %map;

# This is a lot simpler and should work with Windows (ActivePerl)
# Try to make globals in all CAPS and locals (starting with) lowercase
# it makes it easier to understand when someone else comes in to
# read the code.
my $TZ = strftime("%z", localtime());

my ($VERBOSE, $TIMEOUT, $pretty, $output, $help) = (0, 30, 0, undef, undef);
my $localIP;
GetOptions
(
	'verbose'	=> \$VERBOSE,
	'timeout=i'	=> \$TIMEOUT,
	'ip=s'		=> \$localIP,
	'pretty'	=> \$pretty,
	'output=s'	=> \$output,
	'help|?'	=> \$help,
) or die ("Syntax Error!  Try $0 --help");

die usage() if ($help);

my $XML = XML::Writer->new( OUTPUT => 'self', DATA_MODE => ($pretty ? 1 : 0), DATA_INDENT => ($pretty ? 8 : 0) );
my $ua = LWP::UserAgent->new;
$ua->timeout( $TIMEOUT );
$ua->agent("PurePerl-HomeRun-EPG-Fetch/1.0");

my ($req, $res, $rdisc, $ldisc, $guide);
my ($discoverURL, $lineUpURL);

if (defined $localIP)
{
	# Build URLs with the IP as we got told an IP
	$discoverURL = "http://$localIP/discover.json";
	$lineUpURL = "http://$localIP/lineup.json";
} else {
	$req = HTTP::Request->new(GET => 'http://ipv4-api.hdhomerun.com/discover');
	warn("Box Discovery, locating...\n") if ($VERBOSE);
	$res = $ua->request($req);

	# Check the outcome of the response
	die("FATAL: Unable to get box IP!\n" . $res->status_line . "\n") if (!$res->is_success);

	$rdisc = decode_json($res->content);
	die("FATAL: Unable to decode descovery for the local config.\nWe received:\n\n"
			. $res->content . "\n\nDo might need to specify the box IP manually.\n")
			if (!defined $rdisc || !@$rdisc[0]);

	# Grab URLs and store them so we don't need to test for a
	# supplied IP later.
	$discoverURL = @$rdisc[0]->{DiscoverURL};
	$lineUpURL = @$rdisc[0]->{LineupURL} if (exists @$rdisc[0]->{LineupURL});
	$localIP = @$rdisc[0]->{LocalIP};
}

$req = HTTP::Request->new(GET => $discoverURL);
warn("Querying tuner for configuration information...\n") if ($VERBOSE);
$res = $ua->request($req);
die("FATAL: Unable to get discovery information from the tuner box!\n" . $res->status_line . "\n") if (!$res->is_success);
$ldisc = decode_json($res->content);

my $DeviceAuth = $ldisc->{DeviceAuth};
$lineUpURL = $ldisc->{LineupURL} if (!defined $lineUpURL);

#$req = HTTP::Request->new(GET => $ldisc->{LineupURL});
$req = HTTP::Request->new(GET => $lineUpURL);
warn("Getting channel list from box [$localIP] ...\n") if ($VERBOSE);
$res = $ua->request($req);
die("FATAL: Unable to get LINEUP!\n" . $res->status_line . "\n") if (!$res->is_success);

my $channeldata = decode_json($res->content);

# OK here we are cleaned up with Error correction, now lets process everything.

$XML->xmlDecl("ISO-8859-1");
$XML->doctype("tv", undef, "xmltv.dtd");
$XML->startTag('tv', 'generator-info-url' => "http://www.xmltv.org/");

$req = HTTP::Request->new(GET => 'http://ipv4-api.hdhomerun.com/api/guide.php?DeviceAuth=' . $DeviceAuth);
warn("Getting guide data for the channels configured...\n") if ($VERBOSE);
$res = $ua->request($req);
die("FATAL: Unable to get the guide data!\n" . $res->status_line . "\n") if (!$res->is_success);

my $guidedata = decode_json($res->content);

warn("Processing channel list...\n") if ($VERBOSE);

foreach my $items (@$guidedata)
{
	my $channelnumber;
	my $channelname;
	my $channel = $items->{GuideNumber};
	foreach my $lineup (@$channeldata)
	{
		if ($lineup->{GuideNumber} eq $items->{GuideNumber})
		{
			$channelname = $lineup->{GuideName};
		}
	}
	$XML->startTag('channel', 'id' => $channel . ".hdhomerun.com");
	$XML->dataElement('display-name', $channelname);
	$XML->dataElement('lcn', $channel);
	$XML->emptyTag('icon', 'src' => $items->{ImageURL}) if (defined($items->{ImageURL}));
	$XML->endTag('channel');
}

foreach my $items (@$channeldata)
{
	my $channel = $items->{GuideNumber};
	my $channelid = $items->{GuideName};
	my $starttime = time();
	warn("Getting program guide for channel $channelid...\n") if ($VERBOSE);
	while (1)
	{
		$req = HTTP::Request->new(GET => 'http://ipv4-api.hdhomerun.com/api/guide.php?DeviceAuth=' . $DeviceAuth . '&Channel=' . $channel . '&Start=' . $starttime);
		$res = $ua->request($req);
		if (!$res->is_success)
		{
			warn("Error: Unable to get program guide for channel $channelid skipping...\n");
			last;
		}
		if ($res->content eq "null")
		{
			warn("Finished channel $channelid...\n\n") if ($VERBOSE);
			last;
		}
		$guide->{$channel} = decode_json($res->content);
		warn("Processing program guide for channel $channelid...\n") if ($VERBOSE);
		# send over the reference to the XML object rather than using it in global scope.
		printProgramXML(\$XML, $channel . ".hdhomerun.com", $guide->{$channel}[0]->{Guide});
		my $size = scalar @{ $guide->{$channel}[0]->{Guide}} - 1;
		$starttime = $guide->{$channel}[0]->{Guide}[$size]->{EndTime};
	}
}

$XML->endTag('tv');
# doing this here like this because it will give better error
# reporting than relying on XML::Writer to tell you the right
# thing.
if (!defined $output)
{
	warn("Finished! xmltv guide follows...\n\n") if ($VERBOSE);
	print $XML;
	print "\n"; # Add a trailing newline because the xml will not have it.
} else {
	warn("Writing xmltv guide to $output...\n") if ($VERBOSE);
	open FILE, ">$output" or die("Unable to open $output file for writing: $!\n");
	print FILE $XML;
	close FILE;
	warn("Done!\n") if ($VERBOSE);
}
exit 0;

sub printProgramXML
{
	my ($XMLRef, $channelid, $data) = @_;
	foreach my $items (@$data)
	{
		my $starttime = $items->{StartTime};
		my $endtime = $items->{EndTime};
		my $title = $items->{Title};
		my $movie = 0;
		my $originalairdate = "";
		my ($ssec,$smin,$shour,$smday,$smon,$syear,$swday,$syday,$sisdst) = localtime($starttime);
		my ($esec,$emin,$ehour,$emday,$emon,$eyear,$ewday,$eyday,$eisdst) = localtime($endtime);
		# should do this with strftime, but hey-ho, this'll do
		my $startdate = sprintf("%0.4d%0.2d%0.2d%0.2d%0.2d%0.2d",($syear+1900),$smon+1,$smday,$shour,$smin,$ssec);
		my $senddate = sprintf("%0.4d%0.2d%0.2d%0.2d%0.2d%0.2d",($eyear+1900),$emon+1,$emday,$ehour,$emin,$esec);
		$title =~ s/([$chars])/$map{$1}/g;
		${$XMLRef}->startTag('programme', 'start' => "$startdate $TZ", 'stop' => "$senddate $TZ", 'channel' => $channelid);
		${$XMLRef}->dataElement('title', $title);
		if (defined($items->{EpisodeTitle}))
		{
			my $subtitle = $items->{EpisodeTitle};
			$subtitle =~ s/([$chars])/$map{$1}/g;
			${$XMLRef}->dataElement('sub-title', $subtitle);
		}
		if (defined($items->{Synopsis}))
		{
			my $description = $items->{Synopsis};
			$description =~ s/([$chars])/$map{$1}/g;
			${$XMLRef}->dataElement('desc', $description);
		}
		if (defined($items->{Filter}))
		{
			foreach my $category (@{$items->{Filter}})
			{
				if ($category =~ /Movie/)
				{
					$movie = 1;
				}
				${$XMLRef}->dataElement('category', $category);
			}
		}
		${$XMLRef}->emptyTag('icon', 'src' => $items->{ImageURL}) if (defined($items->{ImageURL}));
		if (defined($items->{EpisodeNumber}))
		{
			my $series = 0;
			my $episode = 0;
			if ($items->{EpisodeNumber} =~ /^S(.+)E(.+)/)
			{
				($series, $episode) = ($1, $2);
				${$XMLRef}->dataElement('episode-num', $items->{EpisodeNumber}, 'system' => 'SxxExx') if (defined($items->{EpisodeNumber}));
				$series--;
				$episode--;
			} elsif ($items->{EpisodeNumber} =~ /^EP(.*)-(.*)/) {
				($series, $episode) = ($1, $2);
				$series--;
				$episode--;
			} elsif ($items->{EpisodeNumber} =~ /^EP(.*)/) {
				$episode = $1;
				$episode--;
			}
			$series = 0 if ($series < 0);
			$episode = 0 if ($episode < 0);
			${$XMLRef}->dataElement('episode-num', "$series.$episode.", 'system' => 'xmltv_ns') if (defined($items->{EpisodeNumber}));
		}
		if ((!defined($items->{EpisodeNumber})) and (!defined($items->{OriginalAirdate})) and !($movie))
		{
			my $startdate = sprintf("%0.4d-%0.2d-%0.2d %0.2d:%0.2d:%0.2d",($syear+1900),$smon+1,$smday,$shour,$smin,$ssec);
			my $tmpseries = sprintf("S%0.4dE%0.2d%0.2d%0.2d%0.2d%0.2d",($syear+1900),($smon+1),$smday,$shour,$smin,$ssec);
			${$XMLRef}->dataElement('episode-num', $startdate, 'system' => 'original-air-date');
			${$XMLRef}->dataElement('episode-num', $tmpseries, 'system' => 'SxxExx');
		}
		if (defined($items->{OriginalAirdate}))
		{
			my ($oadsec,$oadmin,$oadhour,$oadmday,$oadmon,$oadyear,$oadwday,$oadyday,$oadisdst) = localtime($items->{OriginalAirdate});
			$originalairdate = sprintf("%0.4d-%0.2d-%0.2d %0.2d:%0.2d:%0.2d",($oadyear+1900),$oadmon+1,$oadmday,$oadhour,$oadmin,$oadsec);
			${$XMLRef}->dataElement('episode-num', $originalairdate, 'system' => 'original-air-date');
			${$XMLRef}->emptyTag('previously-shown', 'start' => $originalairdate);
		} else {
			${$XMLRef}->emptyTag('previously-shown');
		}
		${$XMLRef}->endTag('programme');
	}
}

sub usage
{
	print "Usage:\n";
	print "\t$0 [--ip <IP Address>] [--timeout <seconds>] [--pretty] [--output <filename>] [--verbose] [--help|?]\n";
	print "Where:\n\n";
	print "\t--ip <IP Address>\tManually Set Box IP in the event that the hdhomerun.com API doesn't know where your box is.\n";
	print "\t--timeout <seconds>\tTimeout in seconds for all connections to the API (Default=30).\n";
	print "\t--pretty\t\tOutput the XML with tabs and newlines to make human readable.\n";
	print "\t--output <filename>\tWrite to the location and file specified instead of standard output\n";
	print "\t--verbose\t\tVerbose Mode (prints processing steps to STDERR).\n";
	print "\t--help\t\t\tWill print this usage and exit!\n";
	return "\n";
}
