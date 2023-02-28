#!/usr/bin/perl
use strict;
use warnings;
use DateTime;
use Gzip::Faster;

sub ABC_Get_Regions
{
	my ($debuglevel, $ua, $fvregion) = @_;
	my @fvregions = ();
	my $return_json;
	my %state_mapping =  ( 
		'TAS' => 'Tasmania',
		'QLD' => 'Queensland',
		'NSW' => 'New South Wales',
		'SA' => 'South Australia',
		'NT' => 'Northern Territory',
		'WA' => 'Western Australia',
		'ACT' => 'Canberra',
		'VIC' => 'Victoria',
	);
	#get region list from Freeview
	my $fvurl = "https://freeview.com.au/tv-guide";
	my $res = geturl($ua,$fvurl);
	die("Unable to connect to FreeView to get regions (ABC_Get_Regions).\n") if (!$res->is_success);

	my $data = $res->content;
	$data =~ s/[\n\r]//g;
	$data =~ s/.*__data=(.*);\s+window.prismi.*/$1/;
	my $fvchannelinfo = JSON->new->relaxed(1)->allow_nonref(1)->decode($data);

	my $url = "https://www.abc.net.au/tv/gateway/release/js/core.min.js";
	$res = geturl($ua,$url,3);
	die("Unable to connect to ABC (buildregions).\n") if (!$res->is_success);
	$data = $res->content;
	$data =~ s/\R//g;
	$data =~ s/.*constant\(\"tvSettings\",(.*)\),angular.module\(\"tvGuideApp\"\).*/$1/;	
	$data =~ s/,is_state:\!.}/}/g;
	$data =~ s/\W(\w)\W/\"$1\"/g;
	$data =~ s/([^\s\"A-Za-z0-9\!])([A-Za-z0-9_\!]+)([^\s\"A-Za-z0-9\!])/$1\"$2\"$3/g;
	my $abc_region_json = JSON->new->relaxed(1)->allow_nonref(1)->decode($data);

	if ($fvregion eq 'help')
	{
		for (my $fv_count = 0; $fv_count < @{$fvchannelinfo->{regions}->{list}->{items}}; $fv_count++)
		{
			$return_json->[$fv_count]->{fvregion} = $fvchannelinfo->{regions}->{list}->{items}->[$fv_count]->{id};			
		}
	}
	else
	{
		for (my $fv_count = 0; $fv_count < @{$fvchannelinfo->{regions}->{list}->{items}}; $fv_count++)
		{
			my $found = 0;
			my $region_json;
			print "$fvchannelinfo->{regions}->{list}->{items}->[$fv_count]->{id} <> $fvregion\n" if ($debuglevel == 2);
			if ($fvchannelinfo->{regions}->{list}->{items}->[$fv_count]->{id} eq $fvregion)
			{
				$return_json->{timezone} = $fvchannelinfo->{regions}->{list}->{items}->[$fv_count]->{timezone};
				$return_json->{fvregion} = $fvchannelinfo->{regions}->{list}->{items}->[$fv_count]->{id};
				$return_json->{label} = $fvchannelinfo->{regions}->{list}->{items}->[$fv_count]->{label};
				my $state = uc($fvregion);
				$state =~ s/REGION_(.*?)_(.*)/$1/;
				my $city = $2;
				print "state = $state city = $city\n" if ($debuglevel == 2);
				for (my $abc_region_count = 0; $abc_region_count < scalar(@{$abc_region_json->{regions}}); $abc_region_count++)
				{
					print uc($abc_region_json->{regions}->[$abc_region_count]->{id})." = ".$city."\n" if ($debuglevel == 2);
					if (uc($abc_region_json->{regions}->[$abc_region_count]->{id}) eq $city)
					{
						$return_json->{id} = $abc_region_json->{regions}->[$abc_region_count]->{id};
						$found = 1;
					}
				}
				if (!$found)
				{
					$return_json->{id} = $state_mapping{$state};
				}
			}
		}
	}
	print Dumper $return_json if ($debuglevel == 2);
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
			die("\n(getepg) FATAL: Unable to connect to ABC for $url (".$res->{code}.")\n");
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