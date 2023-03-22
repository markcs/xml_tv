#!/usr/bin/perl
# xmltv.net Australian xmltv epg creater
# <!#FT> 2023/03/22 23:29:26.008 </#FT> 

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

main: 
{
	my $dirname = dirname(__FILE__);
	require "$dirname/abc_epg.pl";
	require "$dirname/fetch_epg.pl";

	my $identifier = "auepg.com.au";
	my %duplicate_channels = ();
	my $duplicated_channels = ();
	my %extra_channels = ();
	my $extra_channels = ();
	my @exclude_channels = ();
	my $Config;
	my @getregions;
	my @fetchtv_regions; 

	my $ua = LWP::UserAgent->new;
	$ua->agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:67.0) Gecko/20100101 Firefox/67.0");
	$ua->default_header( 'Accept-Charset' => 'utf-8');
	$ua->cookie_jar( {} );

	my ($configfile, $debuglevel, $log, $pretty, $fetchtv_region, $numdays, $output, $help) = (undef, 0, undef, 1, 0, 7, undef, undef);
	GetOptions
	(
		'config=s'			=> \$configfile,
		'debuglevel=s'		=> \$debuglevel,
		'log=s'				=> \$log,
		'pretty'			=> \$pretty,
		'region=s'			=> \$fetchtv_region,
		'numdays=s'			=> \$numdays,
		'output=s'			=> \$output,
		'help'				=> \$help,

	) or die ("Syntax Error!  Try $0 --help");

	my $fua = fetch_authenticate($ua);

	UsageAndHelp($debuglevel, $fua) if ($help);

	my ($fetch_regions, $fetch_all_channels) = fetch_channels($debuglevel, $fua);

	if (defined($configfile)) {
		$Config = Config::Tiny->read( $configfile );
		die($Config::Tiny::errstr."\n") if ($Config::Tiny::errstr ne "");
		$log = $Config->{main}->{log} if (defined($Config->{main}->{log}));
		$debuglevel = $Config->{main}->{debuglevel} if (defined($Config->{main}->{debuglevel}));	
		$pretty = ToBoolean($Config->{main}->{pretty}) if (defined($Config->{main}->{pretty}));	
		$numdays = $Config->{main}->{days} if (defined($Config->{main}->{days}));
		$output = $Config->{main}->{output} if (defined($Config->{main}->{output}));
		$fetchtv_region = $Config->{main}->{region} if (defined($Config->{main}->{region}));	
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

		if ($fetchtv_region =~ /all/i) 
		{
			foreach my $region (@$fetch_regions)
			{
				$fetchtv_region = "ALL";
				push(@fetchtv_regions, $region->{region_number})
			}
		}
		else
		{
			@fetchtv_regions = split(/,/,$fetchtv_region);
		}	
		foreach my $region (@fetchtv_regions)
		{
			#duplicate channels section
			my $sectionname = "$region-duplicate";
			if ((defined($Config->{$sectionname})) and ((keys %{$Config->{$sectionname}}) > 0))
			{
				%duplicate_channels = %{$Config->{$sectionname}};
				while (my ($key, $value) = each %duplicate_channels)
				{
					if (defined($duplicated_channels->{$region}->{$value}))
					{
						$duplicated_channels->{$region}->{$value} = $duplicated_channels->{$region}->{$value}.",".$key;	
					}
					else 
					{
						$duplicated_channels->{$region}->{$value} = $key;
					}
				}			
			}
		}
	}

	# check input options
	if (not -w $output)
	{
		die "Couldn't write to $output\n";
	}
	
	if ($fetchtv_region =~ /all/i) 
	{
		foreach my $region (@$fetch_regions)
		{
			push(@fetchtv_regions, $region->{region_number})
		}
	}
	else
	{
		@fetchtv_regions = split(/,/,$fetchtv_region);
	}

	my $found;
	foreach my $regionlist (@fetchtv_regions)
	{
		$found = 0;
		foreach my $region (@$fetch_regions)		
		{
			if ($region->{region_number} eq $regionlist)
			{
				$found = 1;
				last;
			}
		}
		last if ($found eq 0);
	}	

	if ( ($fetchtv_region eq 0) or (!defined($output)) or (!$found) )
	{
		print "=====================================\n\n";
		print "Incorrect options given\n";
		print "A region number was not found: $fetchtv_region \n" if (!$found);
		print "\n\n=====================================\n\n";
		UsageAndHelp($debuglevel, $fua);
	}
       
	######################

	if ( defined($log) and ($debuglevel > 0) )
	{
		my $logfile;
		$log =~ s/\/$//;
		if (-d $log) 
		{
			$logfile = $log.'/'.$fetchtv_region.".log"; 
		}
		else 
		{
			$logfile = $log;
		}  
		open (my $LOG, '>', $logfile)  || die "can't open $logfile.  Does $logfile exist?";
		open (STDERR, ">>&=", $LOG)         || die "can't redirect STDERR";
		select $LOG;
	}



	warn("\nOptions...\n\tfetchtv_region=$fetchtv_region\n\toutput=$output\n\tdays=$numdays\n\tdebuglevel=$debuglevel\n\tpretty=$pretty\n") if ($debuglevel >= 1);

	warn("\tlog=$log\n") if (defined($log) and ($debuglevel >= 1));

	print Dumper $fetch_regions if ($debuglevel >= 2);
	print Dumper $fetch_all_channels if ($debuglevel >= 2);

	my ($fetch_epgid_region_map, @fetch_channels) = fetch_region_channels($fetch_all_channels, \@fetchtv_regions);
	print Dumper $fetch_epgid_region_map if ($debuglevel >= 2);
	print Dumper @fetch_channels if ($debuglevel >= 2);

	warn("Getting Fetch TV EPG...\n") if ($debuglevel >= 1);

	my $fetch_epg = fetch_programlist($debuglevel, $fua, $fetch_all_channels, \@fetchtv_regions, $numdays);

	print Dumper $fetch_epg if ($debuglevel >= 2);

	warn("Getting Region Mapping...\n") if ($debuglevel >= 2);
	my ($abc_id_region_map, $abc_region_info) = ABC_Get_Regions($debuglevel, $ua, $fetch_regions,  \@fetchtv_regions);

	print Dumper $abc_id_region_map if ($debuglevel >= 2);
	print Dumper $abc_region_info if ($debuglevel >= 2);
	my %mappedregions = merge_regions($debuglevel, \@fetch_channels, $abc_region_info);

	warn("Getting ABC EPG...\n") if ($debuglevel >= 1);
	my $ABC_epg = ABC_Get_EPG($debuglevel, $ua, $abc_region_info, $numdays);

	warn("Combining the two EPG's... (this may take some time)\n") if ($debuglevel >= 1);

	my $combined_epg = Combine_epg($debuglevel, \@fetchtv_regions, \%mappedregions, $fetch_epg, $ABC_epg, $abc_id_region_map);
	print Dumper $combined_epg if ($debuglevel >= 2);

	PrebuildXML($debuglevel, \@fetchtv_regions, $fetch_regions, \@fetch_channels, $combined_epg, $duplicated_channels, $identifier, $pretty, $output);
};

sub merge_regions
{
	my ($debuglevel, $fetchmapping, $abcmapping) = @_;
	my %mapped;
	foreach my $channelkey (@$fetchmapping)
	{
		foreach my $fetchregion (@{$channelkey->{regions}})
		{
			
			foreach my $abckey (@$abcmapping)
			{
				foreach my $abcregion (@{$abckey->{region_number}})
				{
					if ($fetchregion eq $abcregion)
					{					
						push (@{$mapped{$channelkey->{epg_id}}}, $abckey->{id});
					}
				}
			}
		}
	}
	return %mapped;
}

sub Combine_epg
{
	my ($debuglevel, $fetch_regions, $region_mapping, $epg1, $epg2, $abc_mapping) = @_;
	my @combinedepg;
	my $unmatchedprograms = 0;
	my $matchedprograms = 0;
	# create a hash table to store the titles and their indices
	my %title_index;
	foreach my $id1 (keys %$epg1) {
    	foreach my $index1 (0..$#{$epg1->{$id1}}) {
        	my $title1 = $epg1->{$id1}->[$index1]->{title};
        	$title_index{$title1}->{$id1}->{$index1} = 1;
    	}
	}

	# iterate over the second array and check for matching titles
	foreach my $id2 (keys %$epg2) 
	{
    	foreach my $index2 (0..$#{$epg2->{$id2}}) 
		{
	        my $title2 = $epg2->{$id2}->[$index2]->{title};
			my $programmatch = 0;
        	LOOP: foreach my $title1 (keys %title_index) 
			{
    	        my $similarity = similarity($title1, $title2);
	            if ($similarity >= 0.8) 
				{
            	    # get the indices of the matching titles from the hash table
        	        foreach my $id1 (keys %{$title_index{$title1}}) 
					{
    	                foreach my $index1 (keys %{$title_index{$title1}->{$id1}}) 
						{
	                        # do something with the matching titles
							if ((abs($epg1->{$id1}->[$index1]->{start_seconds} - $epg2->{$id2}->[$index2]->{start_seconds}) < 900) )
                        	{
								warn("MATCHED: $title1 (at index $index1 in $id1) and $title2 (at index $index2 in $id2) at $epg1->{$id1}->[$index1]->{start_seconds}\n") if ($debuglevel >= 2);
								$epg1->{$id1}->[$index1]->{repeat} = $epg2->{$id2}->[$index2]->{repeat} if (defined($epg2->{$id2}->[$index2]->{repeat}));
								$epg1->{$id1}->[$index1]->{subtitle} = $epg2->{$id2}->[$index2]->{subtitle} if (defined($epg2->{$id2}->[$index2]->{subtitle}));
								$epg1->{$id1}->[$index1]->{originalairdate} = $epg2->{$id2}->[$index2]->{originalairdate} if (defined($epg2->{$id2}->[$index2]->{originalairdate}));
								if ( (defined($epg2->{$id2}->[$index2]->{episode})) and (!defined($epg1->{$id1}->[$index1]->{episode})))
								{
									$epg1->{$id1}->[$index1]->{episode} = $epg2->{$id2}->[$index2]->{episode};
									warn ("\t added episode info\n") if ($debuglevel >= 2);
									if (defined($epg2->{$id2}->[$index2]->{series}))
									{
										$epg1->{$id1}->[$index1]->{season} = $epg2->{$id2}->[$index2]->{season};
										print "\t added season info\n" if ($debuglevel >= 2);
									}
									else
									{							
										my $year = DateTime->from_epoch( epoch => $epg1->{$id1}->[$index1]->{start_seconds})->year;
										$epg1->{$id1}->[$index1]->{season} = $year;
										warn ("\t added season info for this year\n") if ($debuglevel >= 2);
									}
									if ( (defined($epg2->{$id2}->[$index2]->{rating})) and (!defined($epg1->{$id1}->[$index1]->{rating})))
									{
										$epg1->{$id1}->[$index1]->{rating} = $epg2->{$id2}->[$index2]->{rating};
										warn ( "\t added rating\n" ) if ($debuglevel >= 2);
									}
								}
								$programmatch = 1;
								$matchedprograms++;
								last LOOP;
							}
                    	}
                	}
            	}
        	}
			if (!$programmatch)
			{
				warn ("NOT MATCHED to ABC EPG -> channel $title2 (at index $index2 in $id2)\n") if ($debuglevel >= 2);
				$unmatchedprograms++;
			}			
    	}
		warn ("Update... $matchedprograms MATCHED.  $unmatchedprograms UNMATCHED.\n") if ($debuglevel >= 1);
	}
	warn ("TOTAL.... $matchedprograms MATCHED.  $unmatchedprograms UNMATCHED.\n") if ($debuglevel >= 1);
	return $epg1;
}


sub geturl
{
	my ($debuglevel, $ua,$url,$max_retries,@lwp_headers) = @_;
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
			warn("($calling_sub) Try $retry: Unable to connect to $url (".$res->code.")\n") if ($debuglevel >= 1);
		}
		else 
		{
			warn("($calling_sub) Try $retry: Success for $url...\n") if ((($debuglevel >= 1) and ($retry > 1)) or ($debuglevel >= 1));
			return $res;
		}
		$retry++;
	}
	return $res;
}

sub PrebuildXML
{
	my ($debuglevel, $fetchtv_region_list, $fetchtv_regions, $channels, $epg, $duplicated_channels, $identifier, $pretty, $outputfile) = @_;
	warn("Starting to build the XML...\n") if ($debuglevel >= 1);
	my $message = "http://xmltv.net";
	my $regionname;
	foreach my $fetchtv_region (@$fetchtv_region_list)
	{
		foreach my $region (@$fetchtv_regions)
		{			
			if ($region->{region_number} eq $fetchtv_region)
			{
				$regionname = $region->{region_name};
			}
		}
		print "Region ".$fetchtv_region." - ".$regionname." Num Regions: ".scalar(@$fetchtv_region_list)."\n" if ($debuglevel >= 2);
		my @fetch_channels = fetch_single_region_channels($channels, $fetchtv_region);
		my @fetch_epg = fetch_filter_epg(\@fetch_channels, $epg, $fetchtv_region);

		warn("Duplicating channels and EPG\n") if ($debuglevel >= 1);
		my $dup_channels = duplicate($debuglevel, \@fetch_channels, $duplicated_channels, $fetchtv_region);
		my $dup_epg = duplicate($debuglevel, \@fetch_epg, $duplicated_channels, $fetchtv_region);

		$regionname =~ s/[\/\s]/_/g;
		my($filename, $dirs, $suffix) = fileparse($outputfile, qr"\..[^.]*$");
		$suffix = ".xml" if ($suffix eq "");
		$filename = $regionname if ((scalar(@$fetchtv_region_list) > 1) or ($filename eq "") );
		$outputfile = $dirs.$filename.$suffix;
		warn("Setting outputfile to  $outputfile\n") if ($debuglevel >= 1);

		buildXML($debuglevel, $dup_channels, $dup_epg, $identifier, $pretty, $outputfile);
	}	
}

sub buildXML
{
	my ($debuglevel, $channels, $epg, $identifier, $pretty, $outputfile) = @_;
	my $message = "http://xmltv.net";
	my $XML = XML::Writer->new( OUTPUT => 'self', DATA_MODE => ($pretty ? 1 : 0), DATA_INDENT => ($pretty ? 8 : 0) );
	$XML->xmlDecl("UTF-8");
	$XML->doctype("tv", undef, "xmltv.dtd");
	$XML->startTag('tv', 'source-info-name' => $message, 'generator-info-url' => "http://www.xmltv.org/");

	warn("Building the channel list...\n") if ($debuglevel >= 1);
	printchannels($channels, $identifier, \$XML);
	printepg($epg, $identifier, \$XML);
	warn("Finishing the XML...\n") if ($debuglevel >= 1);
	$XML->endTag('tv');
	warn("Writing xmltv guide to $outputfile...\n") if ($debuglevel >= 1);
	open FILE, ">$outputfile" or die("Unable to open $outputfile file for writing: $!\n");
	print FILE $XML;
	close FILE;
	if ($outputfile =~ /gz$/)
	{
		warn("Writing xmltv guide to $outputfile.gz...\n") if ($debuglevel == 1);
		my $fh_gzip = IO::Compress::Gzip->new($outputfile.".gz");
		print $fh_gzip $XML;
		close $fh_gzip;
	}
}

sub printchannels
{
	my ($channels, $identifier, $XMLRef) = @_;
	my $id;
	foreach my $channel (@$channels)
	{

		$id = $channel->{epg_id}.$identifier;	
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
		my $movie = 0;
		my $originalairdate = "";
		${$XMLRef}->startTag('programme', 'start' => "$items->{start}", 'stop' => "$items->{stop}", 'channel' => $items->{epg_id}.$identifier);
		${$XMLRef}->dataElement('title', sanitizeText($items->{title}));
		${$XMLRef}->dataElement('sub-title', sanitizeText($items->{subtitle})) if (defined($items->{subtitle}));
		${$XMLRef}->dataElement('desc', sanitizeText($items->{desc})) if (defined($items->{desc}));
		${$XMLRef}->dataElement('category', sanitizeText($items->{category})) if (defined($items->{category}));
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

sub duplicate
{
	my ($debuglevel, $data, $duplicate_channels, $region) = @_;
	my @combined_data;

	foreach my $id1 (keys %$duplicate_channels) {
		my $duplicates = $duplicate_channels->{$id1};
		foreach my $lcn_to_find (keys %$duplicates) {
			my @duplcns = split(/,/,$duplicates->{$lcn_to_find});
			foreach my $duplcn (@duplcns)
			{
				my @dupexists = grep { $_->{'lcn'} eq $duplcn } @{$data};
				if (scalar(@dupexists) eq 0)
				{
					my @matching_elements = grep { $_->{'lcn'} eq $lcn_to_find } @{$data};
					warn("Duplicating lcn $lcn_to_find to $duplcn\n") if ($debuglevel >= 1);
					foreach my $data_to_clone (@matching_elements)
					{
						my $newref = { %$data_to_clone};
						$newref->{lcn} = $duplcn;
						$newref->{epg_id} = $duplcn."-".$newref->{epg_id};
						push @$data, $newref;
			
					}
				}
				else
				{
					warn("Skipping duplicating data found for LCN = $duplcn. Duplicate defintion found or data already exists for $duplcn\n");
				}
			}

    	}		
	}
	return $data;
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
	my ($fetch_regioninfo, $dummy) = fetch_channels($debuglevel, $ua);
	my $configurl = "https://raw.githubusercontent.com/markcs/xml_tv/markcs-testing/au_epg/configs/epg.conf";
	my $result = geturl($debuglevel, $ua, $configurl);
	my $configdefinition = $result->content;
	$configdefinition =~ s/\n/\n\t/g;

	my $text = "==================================================\nUsage:\n"
                . "\t$0 --config=<configuration filename> [--help|?] ]\n"
				. "\n\n\tThe format of the configuration file is\n"
                . "\n\n";
	print $text;
	print "\t$configdefinition";
	print "\n==================================================\n";
	print "<region> is one of the following values:\n";
	for (my $count = 0; $count < @$fetch_regioninfo; $count++)
	{
		print "\t$fetch_regioninfo->[$count]->{region_number} = $fetch_regioninfo->[$count]->{region_name}, $fetch_regioninfo->[$count]->{state}\n";
	}
	exit();
}
