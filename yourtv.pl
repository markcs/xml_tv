#!/usr/bin/perl
use strict;
use warnings;
use JSON;
use DateTime;
use Getopt::Long;
use LWP::UserAgent;
use XML::Writer;
use Data::Dumper;

my %map = (
	 '&' => 'and',
);
my $chars = join '', keys %map;

my @CHANNELDATA;
my @GUIDEDATA;

my ($VERBOSE, $pretty, $NUMDAYS, $REGION, $outputfile, $help) = (0, 0, 7, undef, undef, undef);
GetOptions
(
	'verbose'	=> \$VERBOSE,
	'pretty'	=> \$pretty,
	'days=i'	=> \$NUMDAYS,
	'region=s'	=> \$REGION,
	'output=s'	=> \$outputfile,
	'help|?'	=> \$help,
) or die ("Syntax Error!  Try $0 --help");
die usage() if ($help);

my $ua = LWP::UserAgent->new;
$ua->agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:67.0) Gecko/20100101 Firefox/67.0");
$ua->default_header('Accept' => 'application/json');
my @REGIONS = buildregions();

die(      "\n"
	. "Please use the command.\n"
	. "\tfree_epg.pl --region=<region> --output=<output xmltv filename>.\n\n"
	. "\tREGION-NUMBER is one of the following:\n\t\t"
	. join("\n\t\t", (map { "$_->{id}\t=\t$_->{name}" } @REGIONS) )
	. "\n\n"
   ) if (!defined($REGION));

my $validregion = 0;
for my $tmpregion ( @REGIONS )
{
	if ($tmpregion->{id} eq $REGION) {
        $validregion = 1;
	}
}
die(	  "\n"
	. "Invalid region specified.  Please use one of the following:\n\t\t"
	. join("\n\t\t", (map { "$_->{id}\t=\t$_->{name}" } @REGIONS) )
	. "\n\n"
   ) if (!$validregion); # (!defined($REGIONS->{$REGION}));

warn("Options...\nVerbose = $VERBOSE, days = $NUMDAYS, pretty = $pretty, region=$REGION, output=$outputfile\n\n") if ($VERBOSE);

# Initialise here (connections to the same server will be cached)


getchannels($ua);
getepg($ua);

my $XML = XML::Writer->new( OUTPUT => 'self', DATA_MODE => ($pretty ? 1 : 0), DATA_INDENT => ($pretty ? 8 : 0) );
$XML->xmlDecl("ISO-8859-1");
$XML->doctype("tv", undef, "xmltv.dtd");
$XML->startTag('tv', 'generator-info-url' => "http://www.xmltv.org/");

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

sub getchannels
{
	my $ua = shift;
	my $data;
	warn("Getting channel list from YourTV ...\n") if ($VERBOSE);
	my $url = "https://www.yourtv.com.au/api/regions/".$REGION."/channels";
	my $res = $ua->get($url);

	die("Unable to connect to FreeView.\n") if (!$res->is_success);

	$data = $res->content;
	my $tmpchanneldata = decode_json($data);
	for (my $count = 0; $count < @$tmpchanneldata; $count++)
	{
		$CHANNELDATA[$count]->{tv_id} = $tmpchanneldata->[$count]->{id};
		$CHANNELDATA[$count]->{name} = $tmpchanneldata->[$count]->{description};
		$CHANNELDATA[$count]->{id} = $tmpchanneldata->[$count]->{number}.".yourtv.com.au";
		$CHANNELDATA[$count]->{lcn} = $tmpchanneldata->[$count]->{number};
		$CHANNELDATA[$count]->{icon} = $tmpchanneldata->[$count]->{logo}->{url};
		warn("Got channel $CHANNELDATA[$count]->{id} - $CHANNELDATA[$count]->{name} ...\n") if ($VERBOSE);
	}
}

sub getepg
{
	my $ua = shift;
	my $showcount = 0;
	#foreach my $channel (@CHANNELDATA)
	#{
	#	my $id = $channel->{id};
	#	warn("Getting epg for $channel->{id} - $channel->{name} ...\n") if ($VERBOSE);
		my $now = time;
		$now = $now - 86400;
		my $offset;
		my $url;
		for(my $day = 0; $day < $NUMDAYS; $day++)
		{
			my $day = nextday($day);
			my $id;
			$url = "https://www.yourtv.com.au/api/guide/?format=html&day=today&region=" . $REGION;
			$url = "https://www.yourtv.com.au/api/guide/?day=" . $day . "&region=" . $REGION;
			warn("\tGetting programs for $REGION for day $url ...\n") if ($VERBOSE);
			my $res = $ua->get($url );
			die("Unable to connect to YourTV for $url.\n") if (!$res->is_success);
            my @data = split(/\n/,$res->content);
			foreach my $line (@data)
			{
				if ($line =~ /data-channel-number/) {
					$line =~ s/.*data-channel-number=\"(\d+)\"/$1/;
					$id = $line.".yourtv.com.au";
				}
				if ($line =~ /data-event-id/) {
					$line =~ s/.*data-event-id=\"(\d+)\">/$1/;
					my $showdata;
					$url = "https://www.yourtv.com.au/api/airings/" . $line;
					warn("\t\tGetting program data for $id from $url ...\n") if ($VERBOSE);
					my $res = $ua->get($url);
					die("Unable to connect to YourTV for $url\n") if (!$res->is_success);
					eval {
						$showdata = decode_json($res->content);
						1;
					};
					if (defined($showdata))
					{
						$GUIDEDATA[$showcount]->{id} = $id;
						$GUIDEDATA[$showcount]->{airing_tmp} = $line;
						$GUIDEDATA[$showcount]->{desc} = $showdata->{synopsis};
					 	$GUIDEDATA[$showcount]->{subtitle} = $showdata->{episodeTitle};
						$GUIDEDATA[$showcount]->{url} = $showdata->{program}->{image};
						$GUIDEDATA[$showcount]->{start} = toLocalTimeString($showdata->{date});
						$GUIDEDATA[$showcount]->{stop} = addTime($showdata->{duration},$GUIDEDATA[$showcount]->{start});
						$GUIDEDATA[$showcount]->{start} =~ s/[-T:]//g;
						$GUIDEDATA[$showcount]->{start} =~ s/\+/ \+/g;
						$GUIDEDATA[$showcount]->{stop} =~ s/[-T:]//g;
						$GUIDEDATA[$showcount]->{stop} =~ s/\+/ \+/g;
						$GUIDEDATA[$showcount]->{channel} = $showdata->{service}->{description};
						$GUIDEDATA[$showcount]->{title} = $showdata->{title};
						$GUIDEDATA[$showcount]->{rating} = $showdata->{classification};
						$GUIDEDATA[$showcount]->{episode} = $showdata->{episodeNumber} if (defined($showdata->{episodeNumber}));
						$GUIDEDATA[$showcount]->{season} = $showdata->{seriesNumber} if (defined($showdata->{episodeNumber}));
						$GUIDEDATA[$showcount]->{category} = $showdata->{genre}->{name};
						if (!defined($GUIDEDATA[$showcount]->{season}))
						{
							my $tmpseries = toLocalTimeString($showdata->{date});
							$tmpseries =~ s/(\d+)-(\d+)-(\d+)T(\d+):(\d+).*/S$1E$2$3$4$5/;
							$GUIDEDATA[$showcount]->{originalairdate} = "$1-$2-$3 $4:$5:00";
						}
						my $catcount = 0;
						$showcount++;
					}
				}
			}
		}
	#}
	warn("Processed a totol of $showcount shows ...\n") if ($VERBOSE);
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
		${$XMLRef}->dataElement('category', sanitizeText($items->{category})) if (defined($items->{category}));
		${$XMLRef}->emptyTag('icon', 'src' => $items->{url}) if (defined($items->{url}));
		if (defined($items->{season}) && defined($items->{episode}))
		{
			my $episodeseries = "S" . $items->{season} . "E" . $items->{episode};
			${$XMLRef}->dataElement('episode-num', $episodeseries, 'system' => 'SxxExx');
			my $series = $items->{season} - 1;
			my $episode = $items->{episode} - 1;
			$series = 0 if ($series < 0);
			$episode = 0 if ($episode < 0);
			$episodeseries = "$series.$episode.";
			${$XMLRef}->dataElement('episode-num', $episodeseries, 'system' => 'xmltv_ns') ;
		}
		if (defined($items->{rating}))
		{
			${$XMLRef}->startTag('rating');
			${$XMLRef}->dataElement('value', $items->{rating});
			${$XMLRef}->endTag('rating');
		}
		${$XMLRef}->dataElement('episode-num', $items->{originalairdate}, 'system' => 'original-air-date') if (defined($items->{originalairdate}));
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
	my $fulldate = shift;
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
	my $tz = DateTime::TimeZone::Local->TimeZone();
	my $localoffset = $tz->offset_for_datetime(DateTime->now());
	$localoffset = $localoffset/3600;
	if ($localoffset =~ /\./)
	{
		$localoffset =~ s/(.*)(\..*)/$1$2/;
		$localoffset = sprintf("+%0.2d:%0.2d", $1, ($2*60));
	} else {
		$localoffset = sprintf("+%0.2d:00", $localoffset);
	}
	$dt->set_time_zone( $tz );
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

	my $epochStartTime = $dt->epoch();
	my $epochendTime = $epochStartTime + ($duration*60);
	my $endTime = DateTime->from_epoch(epoch => $epochendTime);
	my $tz = DateTime::TimeZone::Local->TimeZone();
	my $localoffset = $tz->offset_for_datetime(DateTime->now());
	$localoffset = $localoffset/3600;
	if ($localoffset =~ /\./)
	{
		$localoffset =~ s/(.*)(\..*)/$1$2/;
		$localoffset = sprintf("+%0.2d:%0.2d", $1, ($2*60));
	} else {
		$localoffset = sprintf("+%0.2d:00", $localoffset);
	}
	$endTime->set_time_zone( $tz );
	my $ymd = $endTime->ymd;
	my $hms = $endTime->hms;
	my $returntime = $ymd . "T" . $hms . $localoffset;
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
    if ($daynumber < 8)
    {
        $returnday = $days[$daynumber-1];
    }
    else {
        $returnday = $days[$daynumber-7-1];
    }
    return $returnday;
}

sub usage
{
	return    "Usage:\n"
		. "\t$0 --region=<region> [--days=<days to collect>] [--pretty] [--output <filename>] [--VERBOSE] [--help|?]\n"
		. "\n\tWhere:\n\n"
		. "\t--region=<region>\tThis defines which tv guide to parse. It is mandatory. Refer below for a list of regions.\n"
		. "\t--days=<days to collect>\tThis defaults to 7 days and can be no more than 7.\n"
		. "\t--pretty\t\tOutput the XML with tabs and newlines to make human readable.\n"
		. "\t--output <filename>\tWrite to the location and file specified instead of standard output\n"
		. "\t--verbose\t\tVerbose Mode (prints processing steps to STDERR).\n"
		. "\t--help\t\t\tWill print this usage and exit!\n"
		. "\t  <region> is one of the following:\n\t\t"
		. join("\n\t\t", @REGIONS)
		. "\n\n";
}
