#!/usr/bin/perl
use strict;
use warnings;

use IO::Socket::SSL;
use JSON;
use JSON::Parse 'valid_json';
use LWP::UserAgent;
use Getopt::Long; 
use XML::Writer;
use DateTime::Format::Strptime;
use Data::Dumper;
use String::Similarity;
use Config::Tiny;
use Storable qw(dclone); 
use Cwd;
use File::Basename;
use Term::ProgressBar;
use IO::Compress::Gzip;

my $dirname = dirname(__FILE__);
require "$dirname/abc_epg.pl";
require "$dirname/tt_epg.pl";
require "$dirname/au_radio.pl";

my $identifier = "auepg.com.au";
my %duplicate_channels = ();
my $duplicated_channels = ();
my %extra_channels = ();
my $extra_channels = ();
my @exclude_channels = ();
my $Config;


my $ua = LWP::UserAgent->new;
$ua->agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:67.0) Gecko/20100101 Firefox/67.0");
$ua->default_header( 'Accept-Charset' => 'utf-8');

my ($configfile, $debuglevel, $log, $pretty, $fvregion, $postcode, $numdays, $outputfile, $apikey, $help) = (undef, 0, undef, 1, undef, undef, 7, undef, undef, undef);
GetOptions
(
	'config=s'			=> \$configfile,
	'debuglevel=s'		=> \$debuglevel,
	'log=s'				=> \$log,
	'pretty'			=> \$pretty,
	'region=s'			=> \$fvregion,
	'postcode=s'		=> \$postcode,
	'numdays=s'			=> \$numdays,
	'file=s'			=> \$outputfile,
    'api=s'				=> \$apikey,
	'help'				=> \$help,

) or die ("Syntax Error!  Try $0 --help");

UsageAndHelp($debuglevel, $ua) if ($help);

if (defined($configfile)) {
	$Config = Config::Tiny->read( $configfile );
	die($Config::Tiny::errstr."\n") if ($Config::Tiny::errstr ne "");
	$log = $Config->{main}->{log} if (defined($Config->{main}->{log}));
	$debuglevel = $Config->{main}->{debuglevel} if (defined($Config->{main}->{debuglevel}));	
	$pretty = ToBoolean($Config->{main}->{pretty}) if (defined($Config->{main}->{pretty}));	
	$numdays = $Config->{main}->{days} if (defined($Config->{main}->{days}));
	$fvregion = $Config->{main}->{region} if (defined($Config->{main}->{region}));
	$postcode = $Config->{main}->{postcode} if (defined($Config->{main}->{postcode}));
	$outputfile = $Config->{main}->{output} if (defined($Config->{main}->{output}));
	$apikey = $Config->{main}->{apikey} if (defined($Config->{main}->{apikey}));
    if ((defined($Config->{duplicate})) and ((keys %{$Config->{duplicate}}) > 0))
	{
		%duplicate_channels = %{$Config->{duplicate}};
		while (my ($key, $value) = each %duplicate_channels)
		{
			if (defined($duplicated_channels->{$value}))
			{
				$duplicated_channels->{$value} = $duplicated_channels->{$value}.",".$key;	
			}
			else {
				$duplicated_channels->{$value} = $key;
			}
		}
	}
    if ((defined($Config->{extrachannels})) and ((keys %{$Config->{extrachannels}}) > 0))
	{
		%extra_channels = %{$Config->{extrachannels}};
		while (my ($key, $value) = each %extra_channels)
		{
			$value =~ s/(.*)\s+#.*/$1/;
			$extra_channels->{$key} = $value;		
		}
	}
	if (defined($Config->{main}->{excludechannels}))
	{
		my $excludechannels = $Config->{main}->{excludechannels};
		@exclude_channels = split(/,/,$excludechannels);
	}
}

if ( (!defined($apikey)) or (!defined($fvregion)) or (!defined($outputfile)) )
{
	print "Incorrect options given\n";
	UsageAndHelp($debuglevel, $ua);
}

if (defined($log))
{
    my $logfile;
	$log =~ s/\/$//;
	if (-d $log) 
	{
		$logfile = $log.'/'.$fvregion.".log"; 
	}
	else 
	{
		$logfile = $log;
	}  
	open (my $LOG, '>', $logfile)  || die "can't open $logfile.  Does $logfile exist?";
	open (STDERR, ">>&=", $LOG)         || die "can't redirect STDERR";
	select $LOG;
}

warn("\nOptions...\n\tregion=$fvregion\n\tpostcode=$postcode\n\toutput=$outputfile\n\tdays = $numdays\n\tdebuglevel = $debuglevel\n\tapi=$apikey\n\tpretty = $pretty\n") if ($debuglevel == 2);

warn("\tlog=$log\n") if (defined($log) and ($debuglevel == 2));

warn("Getting Region Mapping...\n") if ($debuglevel == 2);
my $regioninfo = ABC_Get_Regions($debuglevel, $ua,$fvregion);

warn("Getting EPG from abc.net.au ...\n") if ($debuglevel == 2);

my @ABC_epg = ABC_Get_EPG($ua,$regioninfo,$numdays);
warn("Getting FV and TTV channel list...\n") if ($debuglevel == 2);

warn("Getting TTV EPG...\n") if ($debuglevel == 2);
#my @TTV_epg = TTV_Get_EPG($ua, $combined_triplets, $numdays);
#my ($TTV_channels, $TTV_epg) = TTV_Get_EPG_web($ua, 'postcode', $postcode, $numdays);
my ($TTV_channels, $TTV_epg) = TTV_Get_EPG($ua, $apikey, 'postcode', $postcode, $numdays);

warn("Got ".scalar(@$TTV_channels)." channels and ".scalar(@$TTV_epg)." shows ..\n");
#my ($TTV_channels, $TTV_epg) = TTV_Get_EPG_web($ua, 'postcode', $postcode, $numdays);
my @FV_channels =  getFVInfo($ua, $fvregion);

warn("Getting missing channels end EPG...\n") if ($debuglevel == 2);
#my ($missing_channels, $missing_epg) = get_missing_channels_epg(\@FV_channels, $TTV_channels, $numdays);
my ($missing_channels, $missing_epg) = get_missing_channels_epg(\@FV_channels, $TTV_channels, $numdays);
my @complete_channels = ( @$TTV_channels, @$missing_channels );
my @complete_epg = ( @$TTV_epg, @$missing_epg );

warn("Got ".scalar(@complete_channels)." channels and ".scalar(@complete_epg)." shows ..\n");

warn("Adding extra channels from config file.. \n") if ($debuglevel == 2);
my ($extra_added_channels, $extra_added_epg) = add_extra_channels($extra_channels, \@complete_channels, $numdays);

@complete_channels = ( @complete_channels, @$extra_added_channels );
@complete_epg = ( @complete_epg, @$extra_added_epg );

warn("Got ".scalar(@complete_channels)." channels and ".scalar(@complete_epg)." shows ..\n");

warn("Combining ABC and TTV EPG... (this may take some time)\n") if ($debuglevel == 2);
my @combined_epg = Combine_epg(\@complete_channels, \@complete_epg, \@ABC_epg);

warn("Got ".scalar(@complete_channels)." channels and ".scalar(@combined_epg)." shows ..\n");

warn("Getting radio channels and EPG ... \n") if ($debuglevel == 2);
#push(@complete_channels,radio_SBSgetchannels());
#push(@complete_channels,radio_ABCgetchannels($regioninfo));

#push(@combined_epg,radio_ABCgetepg($ua,$numdays));
#push(@combined_epg,radio_SBSgetepg($ua,$numdays));

warn("Duplicating Channels...\n") if ($debuglevel == 2);
my @duplicated_channels = duplicate_channels(\@complete_channels,$duplicated_channels);
my @duplicated_epg = duplicate_epg(\@combined_epg,$duplicated_channels);

warn("Got ".scalar(@duplicated_channels)." channels and ".scalar(@duplicated_epg)." shows ..\n");

warn("Removing excluded channels and EPG..\n") if ($debuglevel == 2);
my ($final_channels, $final_epg) = remove_exclude_channels(\@duplicated_channels, \@duplicated_epg, \@exclude_channels);

warn("Got ".scalar(@$final_channels)." channels and ".scalar(@$final_epg)." shows ..\n");

warn("Build EPG and exit..\n") if ($debuglevel == 2);
#buildXML(\@duplicated_channels, \@duplicated_epg, $identifier, $pretty);
buildXML($final_channels, $final_epg, $identifier, $pretty);


sub Combine_epg
{
	my ($epg1channels, $epg1, $epg2) = @_;
	my @combinedepg;
	my $epgcount = 0;
	my $buffer = 600;
	my $matchedprograms = 0;
	my $unmatchedprograms = 0;
	my @newepg;

	for (my $ttv_show_count = 0; $ttv_show_count < @$epg1; $ttv_show_count++)
	{
		my $programmatch = 0;		
		for (my $abc_show_count = 0; $abc_show_count < @$epg2; $abc_show_count++)
		{
			#print Dumper $epg1->[$ttv_show_count];
			my $shownamecomparison = similarity $epg1->[$ttv_show_count]->{title}, $epg2->[$abc_show_count]->{title};
			#print "$epg1->[$ttv_show_count]->{title} eq $epg2->[$abc_show_count]->{title} ($shownamecomparison)\n";
			if ((abs($epg1->[$ttv_show_count]->{start_seconds} - $epg2->[$abc_show_count]->{start_seconds}) < 900) ) #and ($shownamecomparison > 0.6) )
			{ 
				if ($shownamecomparison > 0.6)
				{
					print "MATCHED (channel $epg1->[$ttv_show_count]->{lcn}) $epg1->[$ttv_show_count]->{title} eq $epg2->[$abc_show_count]->{title} ($shownamecomparison)\n" if ($debuglevel);
					$epg1->[$ttv_show_count]->{repeat} = $epg2->[$abc_show_count]->{repeat} if (defined($epg2->[$abc_show_count]->{repeat}));
					$epg1->[$ttv_show_count]->{subtitle} = $epg2->[$abc_show_count]->{subtitle} if (defined($epg2->[$abc_show_count]->{subtitle}));
					$epg1->[$ttv_show_count]->{originalairdate} = $epg2->[$abc_show_count]->{originalairdate} if (defined($epg2->[$abc_show_count]->{originalairdate}));
					if ( (defined($epg2->[$abc_show_count]->{episode})) and (!defined($epg1->[$ttv_show_count]->{episode})))
					{
						$epg1->[$ttv_show_count]->{episode} = $epg2->[$abc_show_count]->{episode};
						if (defined($epg2->[$abc_show_count]->{series}))
						{
							$epg1->[$ttv_show_count]->{season} = $epg2->[$abc_show_count]->{season};
						}
						else
						{							
							my $year = DateTime->from_epoch( epoch => $epg1->[$ttv_show_count]->{start_seconds})->year;
							$epg1->[$ttv_show_count]->{season} = $year;
						}
						if ( (defined($epg2->[$abc_show_count]->{rating})) and (!defined($epg1->[$ttv_show_count]->{rating})))
						{
							$epg1->[$ttv_show_count]->{rating} = $epg2->[$abc_show_count]->{rating};
						}
				}
				splice @$epg2, $abc_show_count, 1;
				$programmatch = 1;
				$matchedprograms++;
			}}
		}
		if (!$programmatch)
		{
				print "NOT MATCHED to ABC EPG -> channel $epg1->[$ttv_show_count]->{lcn} show = $epg1->[$ttv_show_count]->{title} \t\tat $epg1->[$ttv_show_count]->{start}\n" if ($debuglevel);;
				$unmatchedprograms++;
				#print Dumper $epg1->[$ttv_show_count];
				#<STDIN>;
		}
		push(@newepg, @$epg1[$ttv_show_count]);
	}
	print "$matchedprograms MATCHED.  $unmatchedprograms UNMATCHED.\n" if ($debuglevel);
	return @newepg;
}

sub geturl
{
	my ($ua,$url,$max_retries,@lwp_headers) = @_;
	if (!@lwp_headers )
	{
		@lwp_headers = (
   		'User-Agent' => 'Mozilla/4.76 [en] (Win98; U)',
   		'Accept-Language' => 'en-US'
  		);
	}
	
	$max_retries = 3 if (!(defined($max_retries)));
	my $res;
	my $retry = 1;
	my $success = 0;
	my $calling_sub = (caller(1))[3];
	while (($retry <= $max_retries) and (!$success)) 
	{
		$res = $ua->get($url, @lwp_headers);
		if (!$res->is_success)
		{
			warn("($calling_sub) Try $retry: Unable to connect to $url (".$res->code.")\n") if ($debuglevel == 2);
		}
		else 
		{
			warn("($calling_sub) Try $retry: Success for $url...\n") if ((($debuglevel == 2) and ($retry > 1)) or ($debuglevel));
			return $res;
		}
		$retry++;
	}
	return $res;
}

sub buildXML
{
	my ($channels, $epg, $identifier, $pretty) = @_;
	warn("Starting to build the XML...\n") if ($debuglevel == 2);
	my $message = "http://xmltv.net";

	my $XML = XML::Writer->new( OUTPUT => 'self', DATA_MODE => ($pretty ? 1 : 0), DATA_INDENT => ($pretty ? 8 : 0) );
	$XML->xmlDecl("UTF-8");
	$XML->doctype("tv", undef, "xmltv.dtd");
	$XML->startTag('tv', 'source-info-name' => $message, 'generator-info-url' => "http://www.xmltv.org/");

	warn("Building the channel list...\n") if ($debuglevel == 2);
	printchannels($channels, $identifier, \$XML);
	printepg($epg, $identifier, \$XML);
	warn("Finishing the XML...\n") if ($debuglevel == 2);
	$XML->endTag('tv');
	warn("Writing xmltv guide to $outputfile...\n") if ($debuglevel == 2);
	open FILE, ">$outputfile" or die("Unable to open $outputfile file for writing: $!\n");
	print FILE $XML;
	close FILE;
	warn("Writing xmltv guide to $outputfile.gz...\n") if ($debuglevel == 2);	
	my $fh_gzip = IO::Compress::Gzip->new($outputfile.".gz");
	print $fh_gzip $XML;
	close $fh_gzip;	
}

sub printchannels
{
	my ($channels, $identifier, $XMLRef) = @_;
	my $id;
	foreach my $channel (@$channels)
	{
		#next if (($channel->{lcn} ne "1") and ($channel->{lcn} ne "2") and ($channel->{lcn} ne "20")  and ($channel->{lcn} ne "25") and ($channel->{lcn} ne "21"));
		$id = $channel->{lcn}.$identifier;		
		${$XMLRef}->startTag('channel', 'id' => $id);
		${$XMLRef}->dataElement('display-name', $channel->{name});
		${$XMLRef}->dataElement('lcn', $channel->{lcn});
		${$XMLRef}->emptyTag('icon', 'src' => $channel->{icon}) if (defined($channel->{icon}));
		${$XMLRef}->endTag('channel');
	}
	return;
}

sub printepg
{
	my ($epg, $identifier, $XMLRef) = @_;
	foreach my $items (@$epg)
	{
		#next if (($items->{lcn} ne "1") and ($items->{lcn} ne "2") and ($items->{lcn} ne "20") and ($items->{lcn} ne "25") and ($items->{lcn} ne "21"));
		my $movie = 0;
		my $originalairdate = "";
		#print Dumper $items;
		${$XMLRef}->startTag('programme', 'start' => "$items->{start}", 'stop' => "$items->{stop}", 'channel' => $items->{lcn}.$identifier);
		${$XMLRef}->dataElement('title', sanitizeText($items->{title}));
		${$XMLRef}->dataElement('sub-title', sanitizeText($items->{subtitle})) if (defined($items->{subtitle}));
		${$XMLRef}->dataElement('desc', sanitizeText($items->{desc})) if (defined($items->{desc}));
		${$XMLRef}->dataElement('category', sanitizeText($items->{category}));

		#foreach my $category (@{$items->{category}}) {
		#	${$XMLRef}->dataElement('category', sanitizeText($category));
		#}
		my $iconurl = $items->{icon};
		if (defined $iconurl)
		{
			$iconurl =~ s/\s/\%20/g;
			${$XMLRef}->emptyTag('icon', 'src' => $iconurl);
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
#		${$XMLRef}->emptyTag('previously-shown') if (defined($items->{previouslyshown}));
		if (defined($items->{quality}))
		{
			${$XMLRef}->startTag('video');
			${$XMLRef}->dataElement('quality', sanitizeText($items->{quality}));
			${$XMLRef}->endTag('video');
		}

		${$XMLRef}->emptyTag('previously-shown') if (defined($items->{repeat}) and ($items->{repeat})) ;
		
		${$XMLRef}->emptyTag('premiere', "") if (defined($items->{premiere}));

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
	my %map = (
		'&' => 'and',
	);
	my $chars = join '', keys %map;
	$t =~ s/([$chars])/$map{$1}/g;
	$t =~ s/[^\040-\176]/ /g;
	$t =~ s/\s$//g;
	$t =~ s/^\s//g;
	return $t;
}


sub getFVInfo
{
    my ($ua, $region) = @_;
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
	my $triplets;
    my @fvtriplets;
	my $data;
		
	my $url = "https://fvau-api-prod.switch.tv/content/v1/channels/region/" . $region . "?limit=100&offset=0&include_related=1&expand_related=full&related_entity_types=images";
	my $res = geturl($ua,$url);
	die("Unable to connect to FreeView (fvregion).\n") if (!$res->is_success);
	$data = $res->content;
	my $tmpchanneldata = JSON->new->relaxed(1)->allow_nonref(1)->decode($data);
	$tmpchanneldata = $tmpchanneldata->{data};
	for (my $count = 0; $count < @$tmpchanneldata; $count++)
	{
		my $tmptriplet = $tmpchanneldata->[$count]->{'dvb_triplet'};
		$tmptriplet =~ s/([0-9]+)/0x$1/g;
		$tmptriplet =~ s/:/\./g;
		$fvtriplets[$count]->{triplet} = $tmptriplet;
		$fvtriplets[$count]->{lcn} = $tmpchanneldata->[$count]->{'lcn'};
		#$fvtriplets[$count]->{id} = $tmpchanneldata->[$count]->{'lcn'}.".epg.com.au";
		$fvtriplets[$count]->{name} = $tmpchanneldata->[$count]->{'channel_name'};
		$fvtriplets[$count]->{icon} = $tmpchanneldata->[$count]->{related}->{images}[0]->{url};
    }
	return @fvtriplets;
}

sub get_missing_channels_epg
{
	my ($fv_channels, $ttv_channels, $numdays) = @_;
	my @combined_channels;
	my $missing_triplets = "";
	for (my $fv_count = 0; $fv_count < @$fv_channels; $fv_count++)
	{
		my $lcnfound = 0;
		for (my $ttv_count = 0; $ttv_count < @$ttv_channels; $ttv_count++)
		{			
			if (@$fv_channels[$fv_count]->{lcn} eq @$ttv_channels[$ttv_count]->{lcn})
			{
				$lcnfound = 1;
			}
		}
		if (!$lcnfound)
		{
			print "Channel @$fv_channels[$fv_count]->{lcn} (@$fv_channels[$fv_count]->{name}) @$fv_channels[$fv_count]->{triplet} not found. Adding .....\n" if ($debuglevel);
			$missing_triplets = $missing_triplets.@$fv_channels[$fv_count]->{triplet}.",";
		}
	}
	$missing_triplets =~ s/,$//;
	
	#my ($TTV_channels, $TTV_epg) = TTV_Get_EPG_web($ua, 'triplets', $missing_triplets, $numdays);
	my ($TTV_channels, $TTV_epg) = TTV_Get_EPG($ua, $apikey, 'triplets', $missing_triplets, $numdays) if ($missing_triplets ne "");
	return $TTV_channels, $TTV_epg;
}

sub remove_exclude_channels
{
	my ($channels, $epg, $excludedchannels) = @_;
	my @final_channels;
	my @final_epg;
	for (my $channelcount = 0; $channelcount < @$channels; $channelcount++)
	{
		next if ( grep( /^$channels->[$channelcount]->{lcn}$/, @$excludedchannels ) );
		push(@final_channels, $channels->[$channelcount]);		
	}
	for (my $epgcount = 0; $epgcount < @$epg; $epgcount++)
	{
		next if ( grep( /^$epg->[$epgcount]->{lcn}$/, @$excludedchannels ) );
		push(@final_epg, $epg->[$epgcount]);		
	}	
	return \@final_channels, \@final_epg;
}

sub add_extra_channels
{
	my ($extra_channels, $ttv_channels, $numdays) = @_;
	my @combined_channels = ();
	my @combined_epg = ();
	my $missing_triplets = "";
	my ($TTV_channels, $TTV_epg);
	while (my ($lcn, $value) = each %$extra_channels)
	{

		my $lcnfound = 0;
		for (my $ttv_count = 0; $ttv_count < @$ttv_channels; $ttv_count++)
		{			
			if ($lcn eq @$ttv_channels[$ttv_count]->{lcn})
			{
				$lcnfound = 1;
				print "Clash in adding extra channel $lcn.  Will not add this channel .......\n";
			}
		}
		if (!$lcnfound)
		{
			print "Extra channel $lcn added\n" if ($debuglevel);
			($TTV_channels, $TTV_epg) = TTV_Get_EPG($ua, $apikey, 'triplets', $value, $numdays, $lcn) ;
			@combined_channels = ( @combined_channels, @$TTV_channels );
			@combined_epg = ( @combined_epg, @$TTV_epg );
			$missing_triplets = $missing_triplets.$value.",";
		}
	}
	$missing_triplets =~ s/,$//;
	
	#my ($TTV_channels, $TTV_epg) = TTV_Get_EPG_web($ua, 'triplets', $missing_triplets, $numdays);
	#my ($TTV_channels, $TTV_epg) = TTV_Get_EPG($ua, 'triplets', $missing_triplets, $numdays, $forcedlcn) if ($missing_triplets ne "");
	#return $TTV_channels, $TTV_epg;
	return \@combined_channels, \@combined_epg;
}

sub merge_triplets
{
	my ($fv_channels, $ttv_channels) = @_;
	my @combined_channels;

	for (my $fv_count = 0; $fv_count < @$fv_channels; $fv_count++)
	#for (my $ttv_count = 0; $ttv_count < @$ttv_channels; $ttv_count++)
	{
		my $lcnfound = 0;
		for (my $ttv_count = 0; $ttv_count < @$ttv_channels; $ttv_count++)
		#for (my $fv_count = 0; $fv_count < @$fv_channels; $fv_count++)
		{
			if (@$fv_channels[$fv_count]->{lcn} eq @$ttv_channels[$ttv_count]->{lcn})
			{
				push(@combined_channels,@$ttv_channels[$ttv_count]);
				#print "@$fv_channels[$fv_count]->{name} @$ttv_channels[$ttv_count]->{name}\n";
				$lcnfound = 1;
			}
		}
		if (!$lcnfound)
		{
			push(@combined_channels,@$fv_channels[$fv_count]);
		}

	}
	return @combined_channels;
}

sub duplicate_channels
{
	use Storable qw(dclone); 

	my ($channels, $duplicate_channels) = @_;
	my @combined_channels;
	for (my $chancount = 0; $chancount < @$channels; $chancount++)
	{
		push(@combined_channels,@$channels[$chancount]);
		if (defined($duplicate_channels->{@$channels[$chancount]->{lcn}}) )
		{
			my @dup_channels = split(/,/,$duplicate_channels->{@$channels[$chancount]->{lcn}});
			foreach my $duplcn (@dup_channels)
			{
				my $tmpchannel;
				$tmpchannel = dclone(@$channels[$chancount]);

				#$tmpchannel->{id} =  $duplcn.".epg.com.au";
				$tmpchannel->{lcn} = $duplcn;
				#$tmpchannel->{id} =  $duplicate_channels->{@$channels[$chancount]->{lcn}}.".epg.com.au";
				#$tmpchannel->{lcn} = $duplicate_channels->{@$channels[$chancount]->{lcn}};

				push(@combined_channels,$tmpchannel);
			}
		}
	}
	return @combined_channels;
}

sub duplicate_epg
{

	my ($epg, $duplicate_channels) = @_;
	my @duplicate_epg;
	for (my $epgcount = 0; $epgcount < @$epg; $epgcount++)
	{
		push(@duplicate_epg,@$epg[$epgcount]);
		if (defined($duplicate_channels->{@$epg[$epgcount]->{lcn}}) )
		{
			my @dup_channels = split(/,/,$duplicate_channels->{@$epg[$epgcount]->{lcn}});
			foreach my $duplcn (@dup_channels)
			{
				my $tmpchannel;

				$tmpchannel = dclone(@$epg[$epgcount]);
			
				#$tmpchannel->{id} =  $duplcn.".epg.com.au";
				$tmpchannel->{lcn} = $duplcn;
				push(@duplicate_epg,$tmpchannel);
			}
		}
	}
	return @duplicate_epg;
}

sub get_combined_triplets
{
	my ($channels) = @_;
	my $triplets = "";
	for (my $tripcount = 0; $tripcount < @$channels; $tripcount++)
	{
		$triplets = $triplets.$channels->[$tripcount]->{triplet}."," if defined($channels->[$tripcount]->{triplet});
	}
	$triplets =~ s/,$//;
	return $triplets;
}

sub ToBoolean
{
	my $value = shift;
	if (($value eq 1) or ($value =~ /^true$/i))
	{
		return 1;
	}
	return 0;
}

sub UsageAndHelp
{
	my ($debuglevel, $ua) = @_;
	my $regioninfo = ABC_Get_Regions($debuglevel, $ua,'help');
	my $configurl = "https://raw.githubusercontent.com/markcs/xml_tv/markcs-testing/au_epg/configs/Melbourne_auepg.conf";
	my $result = geturl($ua,$configurl);
	my $configdefinition = $result->content;
	$configdefinition =~ s/\n/\n\t/g;
	for (my $count = 0; $count < @$regioninfo; $count++)
	{
		#print "$regioninfo->[$count]->{fvregion}\n";
	}
	my $text = "==================================================\nUsage:\n"
                . "\t$0 --config=<configuration filename> [--help|?] ]\n"
                . "\t--config=<config filename>\n"
				. "\n\n\tThe format of the configuration file is\n"
                . "\n\n";
	print $text;
	print "\t$configdefinition";
	print "\n==================================================\n";
	print "region is one of the following text values:\n";
	for (my $count = 0; $count < @$regioninfo; $count++)
	{
		print "\t$regioninfo->[$count]->{fvregion}\n";
	}
	exit();
}
