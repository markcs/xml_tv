#!/usr/bin/perl
# <!#FT> 2023/04/10 22:09:19.301 </#FT> 

use strict;
use warnings;
use DateTime;
use URI::Escape;
use Time::HiRes qw(usleep);


sub fetch_authenticate
{
    my ($ua) = @_;
    my $url = 'https://www.fetchtv.com.au/v3/authenticate';
    my $form = [
        "activation_code" => "wwdwnkxev2",
    ];
    my $res = $ua->post( $url, Content => $form);
    return $ua;
}

sub fetch_channels
{
    my ($debuglevel, $ua) = @_;
    my $url = 'https://www.fetchtv.com.au/v4/epg/channels';
    my $res = geturl($debuglevel, $ua,$url,1);
    my $channels = $res->content;
	my $tmpdata;
    my @channeldata;
    my $channelcount = 0;
	eval
	{
		$tmpdata = JSON->new->relaxed(1)->allow_nonref(1)->decode($channels);
		1;
	};    
    my @channelids = @{$tmpdata->{channel_ids}};
    my @regionlist;
    my $region_count = 0;
    foreach my $region_number (keys %{$tmpdata->{region_details}} )
    {
        my $region_data = $tmpdata->{region_details}{$region_number};        
        $regionlist[$region_count]->{region_number} = $region_number;
        $regionlist[$region_count]->{region_name} = $tmpdata->{region_details}{$region_number}[1];
        $regionlist[$region_count]->{state} = $tmpdata->{region_details}{$region_number}[0];
        $region_count++;
    }

    foreach my $channel_id (@channelids) 
    {
        my $founddvb = 0;
        foreach my $source ($tmpdata->{channels}{$channel_id}->{sources}->[0])
        {
            if ($source->{type} eq "dvb")
            {               
               $channeldata[$channelcount]->{icon} = 'https://xmltv.net/icons/auepg/'.$tmpdata->{channels}{$channel_id}->{epg_id}.'.png';
               $channeldata[$channelcount]->{lcn} = $source->{lcn};
               $channeldata[$channelcount]->{name} = $tmpdata->{channels}{$channel_id}->{description};
               $channeldata[$channelcount]->{regions} = $tmpdata->{channels}{$channel_id}->{regions};
               $channeldata[$channelcount]->{epg_id} = $tmpdata->{channels}{$channel_id}->{epg_id};
               $founddvb = 1;
            }
        }
        $channelcount++ if ($founddvb);
    }
    return \@regionlist, \@channeldata;
}

sub fetch_region_epgids
{
    my ($channellist, $regions) = @_;
    my @epg_ids;

    foreach my $channel (@$channellist)
    {        
        foreach my $region (@$regions)
        {
            foreach my $channel_region (@{$channel->{regions}})
            {
                if ($channel_region eq $region)
                {
                    push(@epg_ids, $channel->{epg_id});
                }
            }
        }
    }
    return \@epg_ids;
}

sub fetch_region_channels
{
    my ($channellist, $regions) = @_;
    my @returnchannels;
    my $channelhash;
    my %regionlcns;
    my %epgidnames;

    foreach my $channel (@$channellist)
    {
        my $epgid = $channel->{epg_id};
        my $lcn = $channel->{lcn};
        $epgidnames{$epgid} = $channel->{name};
        foreach my $region (@$regions)
        {
            foreach my $channel_region (@{$channel->{regions}})
            {                        
                if ($channel_region eq $region)
                {
                    $channelhash->{$epgid}->{$region} = 1;
                    my $found = 0;
                    foreach my $tmpchannel (@returnchannels)
                    {
                        $found = 1 if ($tmpchannel->{epg_id} eq $epgid)
                    }
                    push(@returnchannels, $channel) if (!$found);
                    if ((!defined($regionlcns{$region}{$lcn})) or ($regionlcns{$region}{$lcn} !~ /$epgid/))
                    {
                        if (!defined($regionlcns{$region}{$lcn}))
                        {
                            $regionlcns{$region}{$lcn} = $epgid;
                        }
                        else
                        {
                            $regionlcns{$region}{$lcn} = $regionlcns{$region}{$lcn}.",".$epgid;
                        }
                    }           
                }
            }
        }
    }
    my $founddups = 0;
    # warn if duplicate LCN's found for the region(s)
    while (my ($region, $lcnhash) = each %regionlcns)
    {
        while (my ($lcn, $epgids) = each %$lcnhash)
        {
            if ($epgids =~ /,/)
            { 
                my @epgidlist = split(/,/,$epgids);
                my $string = "";
                foreach my $id (@epgidlist)
                {                    
                    $epgidnames{$id} =~ s/,/ /g;
                    #$string = $string.",".$id.",".$epgidnames{$id};
                    $string = $string."\n\t".$id." = ".$epgidnames{$id};
                }
                warn("Region $region has duplicate LCN's = $lcn defined for channels with the following id's$string\n\n");
                #warn("$region,$lcn$string");
                $founddups = 1;
            }
        }
    }
    warn("This is a warning only.\nYou can exclude duplicate channels in the configuration file in the 'excludechannels' section to remove this warning\n\n") if ($founddups);
    return $channelhash, @returnchannels;
}

sub fetch_single_region_channels
{
    my ($channellist, $region) = @_;
    my @returnchannels;
    foreach my $channel (@$channellist)
    {
        foreach my $channel_region (@{$channel->{regions}})
        {                        
            if ($channel_region eq $region)
            {
                push(@returnchannels, $channel);
            }
        }

    }
    return @returnchannels;
}

sub fetch_filter_epg
{
    my ($channellist, $fullepg, $region) = @_;
    my @returnepg;
    my @channels = fetch_single_region_channels($channellist, $region);    
    foreach my $channelinfo (@channels)
    {            
            foreach my $programinfo (@{$fullepg->{$channelinfo->{epg_id}}})
            {
                push (@returnepg, $programinfo);
            }       
    }    
    return @returnepg;
}

sub fetch_epgid_to_lcn
{
    my ($channellist, $epgid) = @_;
    my $lcn;
    foreach my $channel (@$channellist)
    {           
        if ($channel->{epg_id} eq $epgid)
        {
            return $channel->{lcn};
        }        
    }
    return 0;    
}

sub uniq { my %seen; grep !$seen{$_}++, @_ }

sub fetch_programlist
{
    my ($debuglevel, $ua, $all_channels, $inputregions, $numdays) = @_;
    my $epg_all_list = fetch_region_epgids($all_channels, $inputregions);
    print Dumper $epg_all_list if ($debuglevel >= 2);
    my @epg_list = uniq(@$epg_all_list);
    my $dt = DateTime->now();
    my $epoch_time_now = $dt->epoch;
    my $program_fields;
    my $guidedata;
    my %channelprogramcounter;
    my $max_epgids = 50;
    my $totalprogramcount = 0;
    my %fetch_rating_scale = (
                    '20' => 'G',
                    '40' => 'PG',
                    '60' => 'M',
                    '65' => 'MA 15+',
                    );    
    for (my $epg_count = 0; $epg_count < scalar(@epg_list); $epg_count=$epg_count+$max_epgids)
    {        
        my $epg_list_start = $epg_count;
        my $epg_list_end = $epg_count+$max_epgids-1;
        if ( $epg_list_end > scalar(@epg_list))
        {
            $epg_list_end = scalar(@epg_list)-1;
        }
        my @epg_ids = @epg_list[$epg_list_start..$epg_list_end];
        my $epg_ids = join(',', @epg_ids);
        $epg_ids =~ s/,/%2C/g;        
        my $blocknum = int($epoch_time_now/86400);
        my $block = "24-".$blocknum;
        my $url = "https://www.fetchtv.com.au/v2/epg/programslist?channel_ids=".$epg_ids."&block=".$block."&count=".$numdays."&extended=1";
        my $res = geturl($debuglevel, $ua,$url,1);
        my $data = $res->content;
        my $tmpdata;
        eval
        {
            $tmpdata = JSON->new->relaxed(1)->allow_nonref(1)->decode($data);
            1;
        };
        print Dumper $tmpdata if ($debuglevel >= 3);
        for( my $fieldcount = 0; $fieldcount < @{$tmpdata->{__meta__}->{program_fields}}; $fieldcount++ )
        {
            $program_fields->{$tmpdata->{__meta__}->{program_fields}[$fieldcount]} = $fieldcount;
        }
        foreach my $channel_number (keys %{$tmpdata->{channels}} )
        {
            my $channeldata = $tmpdata->{channels}{$channel_number};
            if (!defined($channelprogramcounter{$channel_number}))
            {
                $channelprogramcounter{$channel_number} = 0;
            }
            my $programcount = $channelprogramcounter{$channel_number};

            foreach my $programdata (@{$tmpdata->{channels}{$channel_number}})
            {
                $guidedata->{$channel_number}->[$programcount]->{title} = $programdata->[$program_fields->{title}];
                $guidedata->{$channel_number}->[$programcount]->{epg_id} = $channel_number;
                $guidedata->{$channel_number}->[$programcount]->{lcn} = fetch_epgid_to_lcn($all_channels, $channel_number);
                $guidedata->{$channel_number}->[$programcount]->{start_seconds} = $programdata->[$program_fields->{start}] / 1000;
                $guidedata->{$channel_number}->[$programcount]->{stop_seconds} = $programdata->[$program_fields->{end}] / 1000;
                if ( (defined($tmpdata->{synopses}->{$programdata->[$program_fields->{synopsis_id}]}) ) and (defined($tmpdata->{synopses}->{$programdata->[$program_fields->{synopsis_id}]}  ) ))
                {
                    if ($tmpdata->{synopses}->{$programdata->[$program_fields->{synopsis_id}]}  ne "" )
                    {
                        $guidedata->{$channel_number}->[$programcount]->{desc} = $tmpdata->{synopses}->{$programdata->[$program_fields->{synopsis_id}]};
                    }
                }
                $guidedata->{$channel_number}->[$programcount]->{category} = $programdata->[$program_fields->{genre}] if (defined($programdata->[$program_fields->{genre}]) and ($programdata->[$program_fields->{genre}] ne ""));
                my $startdt = DateTime->from_epoch( epoch => $guidedata->{$channel_number}->[$programcount]->{start_seconds}, time_zone => 'UTC' );
                my $stopdt = DateTime->from_epoch( epoch => $guidedata->{$channel_number}->[$programcount]->{stop_seconds}, time_zone => 'UTC' );
                $guidedata->{$channel_number}->[$programcount]->{start} = $startdt->ymd('').$startdt->hms('')." +0000";
                $guidedata->{$channel_number}->[$programcount]->{stop} = $stopdt->ymd('').$stopdt->hms('')." +0000";
                if (defined($programdata->[$program_fields->{episode_no}]) and ($programdata->[$program_fields->{episode_no}] ne "") )
                {
                    $guidedata->{$channel_number}->[$programcount]->{episode} = $programdata->[$program_fields->{episode_no}];
                     $guidedata->{$channel_number}->[$programcount]->{originalairdate} = $startdt->ymd('-'); 
                }
                if (defined($programdata->[$program_fields->{series_no}]) and ($programdata->[$program_fields->{series_no}] ne "") )
                {
                    $guidedata->{$channel_number}->[$programcount]->{season} = $programdata->[$program_fields->{series_no}];
                }
                # A series is NOT defined, but an episode number is defined, give it a season number
                if (($programdata->[$program_fields->{series_no}] eq "") and ($programdata->[$program_fields->{episode_no}] ne ""))
                {
                    $guidedata->{$channel_number}->[$programcount]->{season} = $startdt->year();
                      $guidedata->{$channel_number}->[$programcount]->{originalairdate} = $startdt->ymd('-');
                }
                # A series is defined, but an episode number is NOT defined
                elsif (($programdata->[$program_fields->{series_no}] ne "") and ($programdata->[$program_fields->{episode_no}] eq ""))
                {
                    $guidedata->{$channel_number}->[$programcount]->{episode} = sprintf("%0.2d%0.2d",$startdt->month(),$startdt->day());
                      $guidedata->{$channel_number}->[$programcount]->{originalairdate} = $startdt->ymd('-');
                }
                # there is no series or episode info, but it is identified as a series by a series crid. Therefore give it info so Plex doesn't mark the show as a movie
                elsif (($programdata->[$program_fields->{series_no}] eq "") and ($programdata->[$program_fields->{episode_no}] eq "") and ($programdata->[$program_fields->{series_link}] ne ""))
                {
                    $guidedata->{$channel_number}->[$programcount]->{season} = $startdt->year();
                     $guidedata->{$channel_number}->[$programcount]->{originalairdate} = $startdt->ymd('-'); 
                    $guidedata->{$channel_number}->[$programcount]->{episode} = sprintf("%0.2d%0.2d",$startdt->month(),$startdt->day());
                }
                if ((defined($programdata->[$program_fields->{rating}])) and (($programdata->[$program_fields->{rating}]) ne "") and ($programdata->[$program_fields->{rating}] ne 0))
                {
                    if (defined($fetch_rating_scale{$programdata->[$program_fields->{rating}]}))
                    {
                        $guidedata->{$channel_number}->[$programcount]->{rating} = $fetch_rating_scale{$programdata->[$program_fields->{rating}]};
                    }
                    else
                    {
                        warn("Rating $programdata->[$program_fields->{rating}] not defined for $programdata->[$program_fields->{title}]\n");
                    }
                }        
                $guidedata->{$channel_number}->[$programcount]->{icon} = "https://www.fetchtv.com.au/v2/epg/program/".$programdata->[$program_fields->{program_id}]."/image";
                $programcount++;
                $totalprogramcount++;
                $channelprogramcounter{$channel_number}++
            }
            warn "(fetch_programlist) Got $programcount programs for $channel_number (total $totalprogramcount)\n" if ($debuglevel >= 2);
        }
        usleep (int(rand(250)) + 500);
    }
    return $guidedata;
}

return 1;