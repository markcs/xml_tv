#!/usr/bin/perl
use strict;
use warnings;
use DateTime;
use Gzip::Faster;
#use JSON::Relaxed;




sub ABC_Get_Regions
{
	my ($ua, $fvregion) = @_;
	my %tzmapping =  ( 
		'Sydney' => 'Australia/Sydney',
		'New South Wales' => 'Australia/Sydney',
    	'Melbourne' => 'Australia/Melbourne',
		'Victoria' => 'Australia/Victoria',
        'Brisbane' => 'Australia/Brisbane',
        'Townsville' => 'Australia/Brisbane',
        'GoldCoast' => 'Australia/Brisbane',
        'Queensland' => 'Australia/Brisbane',
        'Perth' => 'Australia/Perth',
        'Western Australia' => 'Australia/Perth',
        'Adelaide' => 'Australia/Adelaide',
        'South Australia' => 'Australia/Adelaide',					
        'Hobart' => 'Australia/Hobart',
        'Tasmania' => 'Australia/Hobart',
        'Darwin' => 'Australia/Darwin',
        'Northern Territory' => 'Australia/Darwin',
        'Canberra' => 'Australia/Canberra',
	);

	my %fvregionmapping1 = 
	(
		"region_nsw_sydney" => 'Sydney',
		"region_nsw_newcastle" => 	'New South Wales',
		"region_nsw_taree" => 	'New South Wales',
		"region_nsw_tamworth" => 	'New South Wales',
		"region_nsw_orange_dubbo_wagga" => 	'New South Wales',
		"region_nsw_northern_rivers" => 	'New South Wales',
		"region_nsw_wollongong" => 	'New South Wales',
		"region_nsw_canberra" => 	'Canberra',
		"region_nt_regional" => 	'Northern Territory',
		"region_vic_albury" => 	'Victoria',
		"region_vic_shepparton" => 	'Victoria',
		"region_vic_bendigo" => 	'Victoria',
		"region_vic_melbourne" => 	'Melbourne',
		"region_vic_ballarat" => 	'Victoria',
		"region_vic_gippsland" => 	'Victoria',
		"region_qld_brisbane" => 	'Brisbane',
		"region_qld_goldcoast" => 	'GoldCoast',
		"region_qld_toowoomba" => 	'Queensland',
		"region_qld_maryborough" => 	'Queensland',
		"region_qld_widebay" => 	'Queensland',
		"region_qld_rockhampton" => 	'Queensland',
		"region_qld_mackay" => 	'Queensland',
		"region_qld_townsville" => 	'Townsville',
		"region_qld_cairns" => 	'Queensland',
		"region_sa_adelaide" => 	'Adelaide',
		"region_sa_regional" => 	'South Australia',
		"region_wa_perth" => 	'Perth',
		"region_wa_regional_wa" => 	'Western Australia',
		"region_tas_hobart" => 	'Hobart',
		"region_tas_launceston" => 	'Tasmania',

	);

	my $url = "https://www.abc.net.au/tv/gateway/release/js/core.min.js";
	my $res = geturl($ua,$url,3);
	die("Unable to connect to ABC (buildregions).\n") if (!$res->is_success);
	my $data = $res->content;
	$data =~ s/\R//g;
	$data =~ s/.*constant\(\"tvSettings\",(.*)\),angular.module\(\"tvGuideApp\"\).*/$1/;	
	$data =~ s/,is_state:\!.}/}/g;
	$data =~ s/\W(\w)\W/\"$1\"/g;
	$data =~ s/([^\s\"A-Za-z0-9\!])([A-Za-z0-9_\!]+)([^\s\"A-Za-z0-9\!])/$1\"$2\"$3/g;
	my $region_json = JSON->new->relaxed(1)->allow_nonref(1)->decode($data);
	#print Dumper $region_json;
	$region_json = $region_json->{regions};
	my $return_json;
	my $regioncount = 0;
	while (my ($region, $state) = each %fvregionmapping1)
	{
		if ($fvregion eq $region)
		{
			$return_json->{id} = $state;
			$return_json->{fvregion} = $region;
			for (my $count = 0; $count < @$region_json; $count++)
			{
				if ($region_json->[$count]->{id} eq $state )
				{
					$return_json->{timezone} = $tzmapping{$region_json->[$count]->{id}};			
					$return_json->{title} = $region_json->[$count]->{title};
				}
			}
		}
		elsif ($fvregion eq 'help')
		{
			$return_json->[$regioncount]->{id} = $state;
			$return_json->[$regioncount]->{fvregion} = $region;
			for (my $count = 0; $count < @$region_json; $count++)
			{
				if ($region_json->[$count]->{id} eq $state )
				{
					$return_json->[$regioncount]->{timezone} = $tzmapping{$region_json->[$count]->{id}};			
					$return_json->[$regioncount]->{title} = $region_json->[$count]->{title};
				}
			}			
		}
		$regioncount++;
	}
	return $return_json;
}

sub ABC_Get_EPG
{
	my ($ua, $regioninfo, $numdays) = @_;
	
	#use from midnight tomorrow as ABC doesn't get the whole of EPG today which results in some unmatched entries/repeats not recognised.
	my $dt = DateTime->today->add(days => 1 );
	
	$dt->set_time_zone('Australia/Sydney');
	my $region = $regioninfo->{id};
	my $abc_region_tz = $regioninfo->{timezone};
	
	my @epg;
	for (my $day = 0; $day < $numdays; $day++)
	{
		my $date = $dt->ymd;
		my $url = "https://epg.abctv.net.au/processed/".$region."_".$date.".json";
		my $res = geturl($ua,$url,3);
		my $data = $res->content;
		if (!$res->is_success)
		{
			die("\n(getepg) FATAL: Unable to connect to YourTV for $url (".$res->{code}.")\n");
		}
		my $content_encoding = $res->header ('Content-Encoding');
		if ($content_encoding eq 'gzip')
		{
			$data = gunzip ($res->content);
		}		
		my $tmpdata;
		eval
		{
			$tmpdata = JSON->new->relaxed(1)->allow_nonref(1)->decode($data);
			1;
		};
		push(@epg,$tmpdata);
		$dt->add( days => 1 );
	}
	my $programcount = 0;
	my @guidedata;
	#print "ABCEPG\n";print Dumper @epg;
    for (my $epgdays = 0; $epgdays < @epg; $epgdays++)
    {
		my $Tformat = DateTime::Format::Strptime->new( pattern => '%Y-%m-%dT%H:%M:%S', time_zone => $abc_region_tz);

		for (my $schedule = 0; $schedule < scalar(@{$epg[$epgdays]->{schedule}}); $schedule++)
		{
			#print $epg[$epgdays]->{schedule}->[$schedule]->{channel};
			for (my $listing = 0; $listing < scalar(@{$epg[$epgdays]->{schedule}->[$schedule]->{listing}}); $listing++)
			{
				#print Dumper $epg[$epgdays]->{schedule}->[$schedule]->{listing}->[$listing];
				my $tmplisting = $epg[$epgdays]->{schedule}->[$schedule]->{listing}->[$listing];
                $guidedata[$programcount]->{channelname} = $epg[$epgdays]->{schedule}->[$schedule]->{channel};
                #$guidedata[$programcount]->{id} = $lcn.".epg.com.au";
    	    	$guidedata[$programcount]->{desc} = $tmplisting->{description};
                $guidedata[$programcount]->{title} = $tmplisting->{title};
				$guidedata[$programcount]->{repeat} = $tmplisting->{repeat};
				my $end_seconds=0; my $start_seconds=0;
				eval
				{
					$start_seconds = $Tformat->parse_datetime( $tmplisting->{start_time} )->epoch;					
					1;
				};
				eval
				{
					$end_seconds = $Tformat->parse_datetime( $tmplisting->{end_time} )->epoch;					
					1;
				};
				my $startdt = DateTime->from_epoch( epoch => $start_seconds, time_zone => 'UTC' );
				my $enddt = DateTime->from_epoch( epoch => $end_seconds, time_zone => 'UTC' );				
				$guidedata[$programcount]->{start_seconds} = $start_seconds;				
				$guidedata[$programcount]->{stop_seconds} = $end_seconds;
				$guidedata[$programcount]->{start} = $startdt->ymd('').$startdt->hms('')." +0000";
				$guidedata[$programcount]->{stop} = $enddt->ymd('').$enddt->hms('')." +0000";
				$guidedata[$programcount]->{subtitle} = $tmplisting->{episode_title} if defined ($tmplisting->{episode_title});
				my $originalairdate = $startdt;
				$originalairdate->set_time_zone($abc_region_tz);
				$guidedata[$programcount]->{originalairdate} = $originalairdate->ymd('-')." ".$originalairdate->hms(':');
				if (($tmplisting->{show_type} =~ /program/i) and (!$tmplisting->{repeat}))
				{
					$guidedata[$programcount]->{originalairdate} = $startdt->ymd('-')." ".$startdt->hms(':');
				}

				if (defined($tmplisting->{rating}))
                {
                    $guidedata[$programcount]->{rating} = $tmplisting->{rating};
                }

				if (defined($tmplisting->{series_num}))
                {
                    $guidedata[$programcount]->{season} = $tmplisting->{series_num};
                }
				elsif (defined($tmplisting->{series}))
                {
                    $guidedata[$programcount]->{season} = $tmplisting->{series_num};
                }
				if (defined($tmplisting->{episode_num}))
                {
                    $guidedata[$programcount]->{episode} = $tmplisting->{episode_num};
                }
				elsif (defined($tmplisting->{episode}))
                {
                    $guidedata[$programcount]->{episode} = $tmplisting->{episode_num};
                }
					
				if (defined($tmplisting->{genres}))
				{
					foreach my $tmpcat (@{$tmplisting->{genres}})
					{
						push(@{$guidedata[$programcount]->{category}}, $tmpcat);
					}
				}
				$programcount++;
			}
		}	
	}
	#print Dumper @guidedata;
	return @guidedata;
}

sub ABC_Get_EPGold1
{
	my ($ua, $region, $numdays) = @_;
	my $dt = DateTime->now;
	$dt->set_time_zone('Australia/Sydney');

	my @epg;
	for (my $day = 0; $day < $numdays; $day++)
	{
		my $date = $dt->ymd;
		my $url = "https://epg.abctv.net.au/processed/".$region."_".$date.".json";
		my $res = geturl($ua,$url,3);
		my $data = $res->content;
		if (!$res->is_success)
		{
			die("\n(getepg) FATAL: Unable to connect to YourTV for $url (".$res->{code}.")\n");
		}
		my $content_encoding = $res->header ('Content-Encoding');
		if ($content_encoding eq 'gzip')
		{
			$data = gunzip ($res->content);
		}		
		my $tmpdata;
		eval
		{
			$tmpdata = JSON->new->relaxed(1)->allow_nonref(1)->decode($data);
			1;
		};
		push(@epg,$tmpdata);
		$dt->add( days => 1 );
	}
	return @epg;
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

return 1;