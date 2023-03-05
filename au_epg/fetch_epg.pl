#!/usr/bin/perl
use strict;
use warnings;
use DateTime;
use Gzip::Faster;
use URI::Escape;
#use JSON::Relaxed;



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
    my $res = geturl($ua,$url,1);
    my $channels = $res->content;
	my $tmpdata;
    my @channeldata;
    my $channelcount = 0;
	eval
	{
		$tmpdata = JSON->new->relaxed(1)->allow_nonref(1)->decode($channels);
		1;
	};    
    #filter out channels not dvb
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
    print Dumper @regionlist if ($debuglevel >=  2);

    foreach my $channel_id (@channelids) 
    {
        my $founddvb = 0;
        foreach my $source ($tmpdata->{channels}{$channel_id}->{sources}->[0])
        {
            if ($source->{type} eq "dvb")
            {
               print "$channel_id = ".$tmpdata->{channels}{$channel_id}->{description}."\n" if ($debuglevel >=  2);
               $channeldata[$channelcount]->{icon} = "https://www.fetchtv.com.au".$tmpdata->{channels}{$channel_id}->{image};
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
    my ($channellist, $region) = @_;
    my @epg_ids;

    foreach my $channel (@$channellist)
    {
        foreach my $channel_region (@{$channel->{regions}})
        {
            if ($channel_region eq $region)
            {
                push(@epg_ids, $channel->{epg_id});
            }
        }
    }
    return join(',', @epg_ids);
}

sub fetch_region_channels
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

sub fetch_programlist
{
    my ($debuglevel, $ua, $all_channels, $region, $numdays) = @_;

    my $epg_ids = fetch_region_epgids($all_channels, $region);
    $epg_ids =~ s/,/%2C/g;
    my $dt = DateTime->now();
    my $epoch_time_now = $dt->epoch;
    my $program_fields;
    my @guidedata;
    my $programcount = 0;

    for (my $blockcount = 0;$blockcount < $numdays*6 ; $blockcount++)
    {
        my $blocknum = int($epoch_time_now/86400*6) + $blockcount;
        my $block = "4-".$blocknum;
        my $url = "https://www.fetchtv.com.au/v2/epg/programslist?channel_ids=".$epg_ids."&block=".$block."&count=2&extended=1";
        my $res = geturl($ua,$url,1);
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
            foreach my $programdata (@{$tmpdata->{channels}{$channel_number}})
            {

               $guidedata[$programcount]->{title} = $programdata->[$program_fields->{title}];
               $guidedata[$programcount]->{epg_id} = $channel_number;
               $guidedata[$programcount]->{lcn} = fetch_epgid_to_lcn($all_channels, $channel_number);
               $guidedata[$programcount]->{start_seconds} = $programdata->[$program_fields->{start}] / 1000;
               $guidedata[$programcount]->{stop_seconds} = $programdata->[$program_fields->{end}] / 1000;
               if ( defined($program_fields->{sypnosis_id}) and ($program_fields->{sypnosis_id} ne "") and defined($tmpdata->{synopses}->{$programdata->[$program_fields->{sypnosis_id}]}) and ($tmpdata->{synopses}->{$programdata->[$program_fields->{sypnosis_id}]} ne "") )
               {
                   $guidedata[$programcount]->{desc} = $tmpdata->{synopses}->{$programdata->[$program_fields->{sypnosis_id}]};
               }
               $guidedata[$programcount]->{category} = $programdata->[$program_fields->{genre}];
               my $startdt = DateTime->from_epoch( epoch => $guidedata[$programcount]->{start_seconds}, time_zone => 'UTC' );
               my $stopdt = DateTime->from_epoch( epoch => $guidedata[$programcount]->{stop_seconds}, time_zone => 'UTC' );
               $guidedata[$programcount]->{start} = $startdt->ymd('').$startdt->hms('')." +0000";
               $guidedata[$programcount]->{stop} = $stopdt->ymd('').$stopdt->hms('')." +0000";

               if (defined($programdata->[$program_fields->{episode_no}]) and ($programdata->[$program_fields->{episode_no}] ne "") )
               {
                   $guidedata[$programcount]->{episode} = $programdata->[$program_fields->{episode_no}];
                   $guidedata[$programcount]->{originalairdate} = $startdt->ymd('-'); 
               }
               if (defined($programdata->[$program_fields->{series_no}]) and ($programdata->[$program_fields->{series_no}] ne "") )
               {
                   $guidedata[$programcount]->{season} = $programdata->[$program_fields->{series_no}];
               }
               if (($programdata->[$program_fields->{series_no}] eq "") and ($programdata->[$program_fields->{episode_no}] ne ""))
               {
                   $guidedata[$programcount]->{season} = $startdt->year();
               }
#            if ((defined($programdata->[$program_fields->{rating}])) and (($programdata->[$program_fields->{rating}]) ne ""))
#            {
#                $guidedata[$programcount]->{rating} = $programdata->[$program_fields->{rating}];
#            }        
                $guidedata[$programcount]->{icon} = "https://www.fetchtv.com.au/v2/epg/program/".$programdata->[$program_fields->{program_id}]."/image";
                $programcount++;
            }
        }
    }
    return \@guidedata;
}

return 1;