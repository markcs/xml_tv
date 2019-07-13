#!/usr/bin/perl
use strict;
use warnings;
use JSON;
use DateTime;
use Getopt::Long;
use LWP::UserAgent;
use XML::Writer;
use URI;

my %map = (
	 '&' => 'and',
);
my $chars = join '', keys %map;

my @CHANNELDATA;
my $FVICONS;
my @GUIDEDATA;
my $REGION_TIMEZONE;
my $ua = LWP::UserAgent->new;
$ua->agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:67.0) Gecko/20100101 Firefox/67.0");
$ua->default_header('Accept' => 'application/json');
my @REGIONS = buildregions();

my ($VERBOSE, $pretty, $usefreeviewicons, $NUMDAYS, $ignorechannels, $REGION, $outputfile, $help) = (0, 0, 0, 7, undef, undef, undef, undef);
GetOptions
(
	'verbose'	=> \$VERBOSE,
	'pretty'	=> \$pretty,
	'days=i'	=> \$NUMDAYS,
	'region=s'	=> \$REGION,
	'output=s'	=> \$outputfile,
	'ignore=s'	=> \$ignorechannels,
	'fvicons'   => \$usefreeviewicons,
	'help|?'	=> \$help,
) or die ("Syntax Error!  Try $0 --help");
die usage() if ($help);

die(usage() ) if (!defined($REGION));

my $validregion = 0;
for my $tmpregion ( @REGIONS )
{
	if ($tmpregion->{id} eq $REGION) {
        $validregion = 1;
        $REGION_TIMEZONE = $tmpregion->{timezone};
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
	for(my $day = 0; $day < $NUMDAYS; $day++)
	{
		my $day = nextday($day);
		my $id;
		my $url = URI->new( 'https://www.yourtv.com.au/api/guide/' );
		$url->query_form(day => $day, timezone => $REGION_TIMEZONE, format => 'json', region => $REGION);
		warn("\nGetting channel program listing for $REGION for $day ($url)...\n") if ($VERBOSE);
		my $res = $ua->get($url);
		die("Unable to connect to YourTV for $url.\n") if (!$res->is_success);
		my $data = $res->content;
		my $tmpdata;
		eval
		{
			$tmpdata = decode_json($data);
			1;
		};
		$tmpdata = $tmpdata->[0]->{channels};
		if (defined($tmpdata))
		{
			for (my $channelcount = 0; $channelcount < @$tmpdata; $channelcount++)
			{
				next if (!defined($tmpdata->[$channelcount]->{number}));
				next if ( ( grep( /^$tmpdata->[$channelcount]->{number}$/, @IGNORECHANNELS ) ) );

				$id = $tmpdata->[$channelcount]->{number}.".yourtv.com.au";
				my $blocks = $tmpdata->[$channelcount]->{blocks};
				for (my $blockcount = 0; $blockcount < @$blocks; $blockcount++)
				{
					my $subblocks = $blocks->[$blockcount]->{shows};
					for (my $airingcount = 0; $airingcount < @$subblocks; $airingcount++)
					{
						my $showdata;
						my $airing = $subblocks->[$airingcount]->{id};
						$url = "https://www.yourtv.com.au/api/airings/" . $airing;
						warn("\t\tGetting program data for $id on $day from $url ...\n") if ($VERBOSE);
						my $res = $ua->get($url);
						die("Unable to connect to YourTV for $url\n") if (!$res->is_success);
						eval
						{
							$showdata = decode_json($res->content);
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
							$GUIDEDATA[$showcount]->{episode} = $showdata->{episodeNumber} if (defined($showdata->{episodeNumber}));
							$GUIDEDATA[$showcount]->{season} = $showdata->{seriesNumber} if (defined($showdata->{episodeNumber}));
							$GUIDEDATA[$showcount]->{category} = $showdata->{genre}->{name};
							if (defined($showdata->{repeat} ) )
							{
								my $tmpseries = toLocalTimeString($showdata->{date},$REGION_TIMEZONE);
								$tmpseries =~ s/(\d+)-(\d+)-(\d+)T(\d+):(\d+).*/S$1E$2$3$4$5/;
								$GUIDEDATA[$showcount]->{originalairdate} = "$1-$2-$3";
								$GUIDEDATA[$showcount]->{previouslyshown} = "$1-$2-$3";
							}
							if (!defined($GUIDEDATA[$showcount]->{season}))
							{
								my $tmpseries = toLocalTimeString($showdata->{date},$REGION_TIMEZONE);
								$tmpseries =~ s/(\d+)-(\d+)-(\d+)T(\d+):(\d+).*/S$1E$2$3$4$5/;
								$GUIDEDATA[$showcount]->{originalairdate} = "$1-$2-$3";
							}
							#warn("\tGetting program data for $id on $day from $url - $GUIDEDATA[$showcount]->{title} at $GUIDEDATA[$showcount]->{start} $showdata->{date}...\n");
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
		${$XMLRef}->dataElement('category', sanitizeText($items->{category})) if (defined($items->{category}));
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
		${$XMLRef}->emptyTag('previously-shown', 'start' => $items->{originalairdate}) if (defined($items->{originalairdate}));
		if (defined($items->{rating}))
		{
			${$XMLRef}->startTag('rating');
			${$XMLRef}->dataElement('value', $items->{rating});
			${$XMLRef}->endTag('rating');
		}
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
		. "\t  <region> is one of the following:\n\t\t\t"
		. join("\n\t\t", (map { "$_->{id}\t=\t$_->{name}" } @REGIONS) )
		. "\n\n";
}
