#!/usr/bin/perl
# <!#FT> 2023/04/05 23:16:41.785 </#FT> 

use strict;
use warnings;
use DateTime;
use Gzip::Faster;

sub ABC_Get_Regions
{
	my ($debuglevel, $ua, $region, $fetchtv_regions) = @_;
	my @fvregions = ();
	my $return_hash;
	my @return_regions = ();
	my %state_mapping =  ( 
		'TAS' => {'full_state_name' => 'Tasmania', 'timezone' => 'Australia/Hobart'},
		'QLD' => {'full_state_name' => 'Queensland', 'timezone' => 'Australia/Brisbane'},
		'NSW' => {'full_state_name' => 'New South Wales', 'timezone' => 'Australia/Sydney'},
		'SA' => {'full_state_name' => 'South Australia', 'timezone' => 'Australia/Adelaide'},
		'NT' => {'full_state_name' => 'Northern Territory', 'timezone' => 'Australia/Darwin'},
		'WA' => {'full_state_name' => 'Western Australia', 'timezone' => 'Australia/Perth'},
		'ACT' => {'full_state_name' => 'Canberra', 'timezone' => 'Australia/Canberra'},
		'VIC' => {'full_state_name' => 'Victoria', 'timezone' => 'Australia/Melbourne'},
	);

	my $url = "https://www.abc.net.au/tv/gateway/release/js/core.min.js";
	my $res = geturl($debuglevel, $ua,$url,3);
	die("Unable to connect to ABC (buildregions).\n") if (!$res->is_success);
	my $data = $res->content;
	$data =~ s/\R//g;
	$data =~ s/.*constant\(\"tvSettings\",(.*)\),angular.module\(\"tvGuideApp\"\).*/$1/;	
	$data =~ s/,is_state:\!.}/}/g;
	$data =~ s/\W(\w)\W/\"$1\"/g;
	
	$data =~ s/([^\s\"A-Za-z0-9\!])([A-Za-z0-9_\!]+)([^\s\"A-Za-z0-9\!])/$1\"$2\"$3/g;
	my $abc_region_json = JSON->new->relaxed(1)->allow_nonref(1)->decode($data);

	foreach my $fetch_region_data (@$region)
	{	
		foreach my $fetchtv_region (@$fetchtv_regions)
		{		
			my $found = 0;
			
			foreach my $abc_region_data (@{$abc_region_json->{regions}})
			{
				my $tmpname = $fetch_region_data->{region_name};
				$tmpname =~ s/\s//g;
				if  ( ($tmpname eq $abc_region_data->{id}) and ($fetch_region_data->{region_number} eq $fetchtv_region)) 
				{
					$found = 1;
					my $regiondefined = 0;
					my $counter = 0;
					foreach my $tmpregion (@return_regions)
					{
						if ( (defined($return_regions[$counter]->{id})) and ($return_regions[$counter]->{id} eq $fetchtv_region))
						{
							push(@{$return_regions[$counter]->{region_number}}, $fetchtv_region);
							$regiondefined = 1;
							$return_hash->{$abc_region_data->{id}}->{$fetchtv_region} = 1;
						}
						$counter++;
					}
					if (!$regiondefined)
					{
						$return_regions[$counter]->{id} = $abc_region_data->{id};
						$return_regions[$counter]->{timezone} = $state_mapping{$fetch_region_data->{state}}->{timezone};	
						push(@{$return_regions[$counter]->{region_number}}, $fetchtv_region);
						$return_hash->{$abc_region_data->{id}}->{$fetchtv_region} = 1;
					} 
				}			
			}	
			if ( ($fetch_region_data->{region_number} eq $fetchtv_region) and !$found) 
			{
				my $regiondefined = 0;
				my $counter = 0;
					foreach my $tmpregion (@return_regions)
					{
						if ((defined($return_regions[$counter]->{id})) and ($return_regions[$counter]->{id} eq $state_mapping{$fetch_region_data->{state}}->{full_state_name}))
						{
							push(@{$return_regions[$counter]->{region_number}}, $fetchtv_region);
							$return_hash->{$state_mapping{$fetch_region_data->{state}}->{full_state_name}}->{$fetchtv_region} = 1;
							$regiondefined = 1;
						}
						$counter++;
					}					
					if (!$regiondefined)
					{
						$return_regions[$counter]->{id} = $state_mapping{$fetch_region_data->{state}}->{full_state_name};
						$return_regions[$counter]->{timezone} = $state_mapping{$fetch_region_data->{state}}->{timezone};	
						push(@{$return_regions[$counter]->{region_number}}, $fetchtv_region);
						$return_hash->{$state_mapping{$fetch_region_data->{state}}->{full_state_name}}->{$fetchtv_region} = 1;

					} 
			}
		}
	}
	return $return_hash, \@return_regions;
}

sub ABC_Get_EPG
{
	my ($debuglevel, $ua, $regiondata, $numdays) = @_;
	my @guidedata;
	my $guidedata;
	foreach my $regioninfo (@$regiondata)
	{
		my $dt = DateTime->today; #->add(days => 1 );	
		$dt->set_time_zone('Australia/Sydney');
		my $region = $regioninfo->{id};
		my $abc_region_tz = $regioninfo->{timezone};
		my @epg;
		my $programcount = 0;
		for (my $day = 0; $day <= $numdays; $day++)
		{
			my $date = $dt->ymd;
			my $url = "https://epg.abctv.net.au/processed/".$region."_".$date.".json";
			my $res = geturl($debuglevel, $ua,$url,3);
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
		for (my $epgdays = 0; $epgdays < @epg; $epgdays++)
		{
			my $Tformat = DateTime::Format::Strptime->new( pattern => '%Y-%m-%dT%H:%M:%S', time_zone => $abc_region_tz);

			for (my $schedule = 0; $schedule < scalar(@{$epg[$epgdays]->{schedule}}); $schedule++)
			{
				for (my $listing = 0; $listing < scalar(@{$epg[$epgdays]->{schedule}->[$schedule]->{listing}}); $listing++)
				{
					my $tmplisting = $epg[$epgdays]->{schedule}->[$schedule]->{listing}->[$listing];
					$guidedata->{$region}->[$programcount]->{channelname} = $epg[$epgdays]->{schedule}->[$schedule]->{channel};
					$guidedata->{$region}->[$programcount]->{desc} = $tmplisting->{description};
					$guidedata->{$region}->[$programcount]->{title} = $tmplisting->{title};
					$guidedata->{$region}->[$programcount]->{repeat} = $tmplisting->{repeat};				
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
					$guidedata->{$region}->[$programcount]->{start_seconds} = $start_seconds;				
					$guidedata->{$region}->[$programcount]->{stop_seconds} = $end_seconds;
					$guidedata->{$region}->[$programcount]->{start} = $startdt->ymd('').$startdt->hms('')." +0000";
					$guidedata->{$region}->[$programcount]->{stop} = $enddt->ymd('').$enddt->hms('')." +0000";
					$guidedata->{$region}->[$programcount]->{subtitle} = $tmplisting->{episode_title} if defined ($tmplisting->{episode_title});
					$guidedata->{$region}->[$programcount]->{show_type} = $tmplisting->{show_type};

					if (defined($tmplisting->{rating}))
					{
						$guidedata->{$region}->[$programcount]->{rating} = $tmplisting->{rating};
					}

					if (defined($tmplisting->{series_num}))
					{
						$guidedata->{$region}->[$programcount]->{season} = $tmplisting->{series_num};
					}
					elsif (defined($tmplisting->{series}))
					{
						$guidedata->{$region}->[$programcount]->{season} = $tmplisting->{series_num};
					}
					if (defined($tmplisting->{episode_num}))
					{
						$guidedata->{$region}->[$programcount]->{episode} = $tmplisting->{episode_num};
					}
					elsif (defined($tmplisting->{episode}))
					{
						$guidedata->{$region}->[$programcount]->{episode} = $tmplisting->{episode_num};
					}
						
					if (defined($tmplisting->{genres}))
					{
						foreach my $tmpcat (@{$tmplisting->{genres}})
						{
							push(@{$guidedata->{$region}->[$programcount]->{category}}, $tmpcat);
						}
					}
					$programcount++;
				}
			}	
		}
	}

	return $guidedata;
}

return 1;