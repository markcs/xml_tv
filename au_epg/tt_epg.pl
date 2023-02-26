#!/usr/bin/perl
use strict;
use warnings;
use DateTime;
use Gzip::Faster;
use URI::Escape;
#use JSON::Relaxed;




sub TTV_Get_Triplets
{
	my ($ua, $postcode) = @_;
    my $triplets;
	my $url = "https://cms.telstratv.com/ttv-app/postcode-mapping/";
	my $res = geturl($ua,$url);
    #my $res = $ua->get($url);
    my $TTV_postcodes;
	my $data = $res->content;
	if (!$res->is_success)
	{
		die("\n(getepg) FATAL: Unable to connect to TTV for $url (".$res->{code}.")\n");
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
	$tmpdata = $tmpdata->{data};
    for (my $count = 0; $count < @$tmpdata; $count++)
    {
        if ($tmpdata->[$count]->{postcode} eq $postcode)
        {
            $triplets = join ',', @{$tmpdata->[$count]->{triplets}};
        }
        
    }
	return $triplets;
}

sub TTV_Get_Channels
{
    my ($ua, $triplets, $forcedlcn) = @_;
    $forcedlcn = 0 if (!defined($forcedlcn));
    $triplets = uri_escape($triplets);
    my $url = "https://api.telstratv.com/v1/tuna-consumer/screens/channels?deviceType=android&triplets=".$triplets;
	my @headers = (
   		'User-Agent' => 'Telstra TV-Android-5.15.0',
   		'Accept-Language' => 'en-US',
        'x-api-key' => 'scW3Xiz3NJAwkNmMYIAd6XyiaNaFbOnD',
        'Host' => 'api.telstratv.com',
        'Accept-Encoding' => 'gzip',
        'Accept' => 'application/json; charset=utf-8',
  	);
    print "$url\n\n" ;
    my @channeldata;
	my $res = geturl($ua,$url,1,@headers);
	my $data = $res->content;
	if (!$res->is_success)
	{
		die("\n(getepg) FATAL: Unable to connect to TTV for $url (".$res->{code}.")\n");
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
    
    $tmpdata = $tmpdata->{channels};    
    for (my $count = 0; $count < @$tmpdata; $count++)
    {
        $channeldata[$count]->{name} = $tmpdata->[$count]->{providerName};
        #$channeldata[$count]->{id} = $tmpdata->[$count]->{lcn}.".epg.com.au";
        if ($forcedlcn == 0) 
        {
            $channeldata[$count]->{lcn} = $tmpdata->[$count]->{lcn};
        }
        else 
        {
            $channeldata[$count]->{lcn} = $forcedlcn;
        }
        $channeldata[$count]->{icon} = $tmpdata->[$count]->{channelLogo};
        $channeldata[$count]->{triplet} = $tmpdata->[$count]->{id};
    }
    return @channeldata;
}

sub TTV_Get_EPG
{
	my ($ua, $apikey, $datatype, $inputdata, $numdays, $forcedlcn) = @_;
    $forcedlcn = 0 if (!defined($forcedlcn));
    my $triplets;
    my @lcnlist = ();
    if ($datatype eq 'postcode')
    {
        $triplets =  TTV_Get_Triplets($ua, $inputdata);
    }
    elsif ($datatype eq 'triplets')
    {
        $triplets = $inputdata;
    }
    else
    {
        die();
    } 
    my @channeldata = TTV_Get_Channels($ua,$triplets, $forcedlcn);
    $triplets = uri_escape($triplets);
    
	my @headers = (
   		'User-Agent' => 'Telstra TV-Android-5.15.0',
   		'Accept-Language' => 'en-US',
        'x-api-key' => $apikey,
        'Host' => 'api.telstratv.com',
        'Accept-Encoding' => 'gzip',
        'Accept' => 'application/json; charset=utf-8',
  	);
    
    my @guidedata;
	
#    my $dt = DateTime->now;
 	my $dt = DateTime->today->add(days => 1 );
   
    my $epoch_time_now = $dt->epoch;
    my $programcount = 0;
    #my $duration = ((int($epoch_time_now/86400)+1)*86400) - $epoch_time_now;
    my $duration = 86400;
	my @epg;
	for (my $day = 0; $day < $numdays; $day++)
	{
        my $addseconds = $duration*$day;
        #$dt->add( seconds => $addseconds );
        $dt->add( seconds => $duration) if ($day > 0);        
        warn("Getting data for day = $day .... \n");
        $epoch_time_now = $dt->epoch;
        my $url = "https://api.telstratv.com/v1/tuna-consumer/screens/epg?triplets=".$triplets."&startTime=".$epoch_time_now."&duration=".$duration."&deviceType=android";				   
        my $res = geturl($ua,$url,3,@headers);
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
        $tmpdata = $tmpdata->{channels};
        #print "TTEPG\n";print Dumper $tmpdata;
        for (my $channels = 0; $channels < @$tmpdata; $channels++)
        {
    	    my $programdata = $tmpdata->[$channels]->{programs};
            #print Dumper $programdata;
            my $lcn;
            if ($forcedlcn == 0) 
            {
                $lcn = $tmpdata->[$channels]->{lcn};
            }
            else 
            {
                $lcn = $forcedlcn;
            }
            #next if ( grep( /^$tmpdata->[$channels]->{lcn}$/, @lcnlist ) );
            #push(@lcnlist, $tmpdata->[$channels]->{lcn});
            print "\tGot ".scalar(@$programdata)." programs for day $day\n";
            for (my $programs = 0; $programs < @$programdata; $programs++)
            {
                $guidedata[$programcount]->{lcn} = $lcn;
                #$guidedata[$programcount]->{id} = $lcn.".epg.com.au";
    	    	$guidedata[$programcount]->{desc} = $programdata->[$programs]->{description} if (defined($programdata->[$programs]->{description}));
                $guidedata[$programcount]->{title} = $programdata->[$programs]->{title};
        		#$guidedata[$programcount]->{subtitle} = $showdata->{episodeTitle}; 20220926231500 +1000
                $guidedata[$programcount]->{start_seconds} = $programdata->[$programs]->{roundedStartTime};
                $guidedata[$programcount]->{stop_seconds} = $programdata->[$programs]->{roundedEndTime};
                my $actual_startdt = DateTime->from_epoch( epoch => $programdata->[$programs]->{startTime}, time_zone => 'UTC' );
                my $startdt = DateTime->from_epoch( epoch => $programdata->[$programs]->{roundedStartTime}, time_zone => 'UTC' );
                my $stopdt = DateTime->from_epoch( epoch => $programdata->[$programs]->{roundedEndTime}, time_zone => 'UTC' );
                $guidedata[$programcount]->{date} = $startdt->ymd();
                $guidedata[$programcount]->{actualstart} = $actual_startdt->ymd('').$actual_startdt->hms('')." +0000";
                $guidedata[$programcount]->{start} = $startdt->ymd('').$startdt->hms('')." +0000";
                $guidedata[$programcount]->{stop} = $stopdt->ymd('').$stopdt->hms('')." +0000";
                $guidedata[$programcount]->{category} = $programdata->[$programs]->{category};# if (defined($programdata->[$programs]->{genres}));
                
                if (defined($programdata->[$programs]->{episode}))
                {
                    $guidedata[$programcount]->{episode} = $programdata->[$programs]->{episode};
                    $guidedata[$programcount]->{originalairdate} = $startdt->ymd('-'); #." ".$startdt->hms(':');
                }
                if (defined($programdata->[$programs]->{season}))
                {
                    $guidedata[$programcount]->{season} = $programdata->[$programs]->{season};
                }
                if ((!defined($programdata->[$programs]->{season})) and (defined($programdata->[$programs]->{episode})))
                {
                    $guidedata[$programcount]->{season} = $startdt->year();
                }
                if ((defined($programdata->[$programs]->{classification})) and (($programdata->[$programs]->{classification}) ne ""))
                {
                    $guidedata[$programcount]->{rating} = $programdata->[$programs]->{classification};
                }        
                $guidedata[$programcount]->{icon} = $programdata->[$programs]->{imageList}->[0]->{url};
				$guidedata[$programcount]->{quality} = "SDTV";
				if ($programdata->[$programs]->{isHD})
				{
					$guidedata[$programs]->{quality} = "HDTV";
				}                
        		#$guidedata[$programcount]->{title} = $showdata->{title};
    	    	#$guidedata[$programcount]->{rating} = $showdata->{classification};
    		    #$guidedata[$programcount]->{quality} = "SDTV";
                $programcount++;
                
            }
        
        }       
	};
	return \@channeldata, \@guidedata;
}

sub TTV_Get_EPG_web
{
	my ($ua, $apikey, $datatype, $inputdata, $numdays) = @_;
	my @headers = (
   		'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/104.0.5112.126 Safari/537.36',
   		'Accept-Language' => 'en-US',
        'x-api-key' => $apikey,
        'Accept' => 'application/json; charset=utf-8',
  	);
    my @guidedata;
	my $url;
    my $dt = DateTime->now;
    my $epoch_time_now = $dt->epoch;
    #my $duration = ((int($epoch_time_now/86400)+1)*86400) - $epoch_time_now;
    my $duration = $numdays*86400;
	my @epg;
    my @channeldata;
    my @lcnlist = ();
    my $foundchannelcounter = 0;
    my $programcount = 0;

    if ($datatype eq 'postcode')
    {
        $url = "https://api.telstratv.com/v1/tuna-consumer/screens/epg?duration=".$duration."&deviceType=TTV&postcode=".$inputdata;
    }
    elsif ($datatype eq 'triplets')
    {
        $url = "https://api.telstratv.com/v1/tuna-consumer/screens/epg?duration=".$duration."&deviceType=TTV&triplets=".$inputdata;
    }
    my $res = geturl($ua,$url,3,@headers);
	my $data = $res->content;
    my $tmpdata;

	if (!$res->is_success)
	{
		die("\n(getepg) FATAL: Unable to connect to ABC for $url (".$res->{code}.")\n");
	}
	eval
	{
		$tmpdata = JSON->new->relaxed(1)->allow_nonref(1)->decode($data);
		1;
	};
    $tmpdata = $tmpdata->{channels};
   #print "TTEPG\n";print Dumper $tmpdata;
    for (my $channelcount = 0; $channelcount < @$tmpdata; $channelcount++)
    { 
        next if ( grep( /^$tmpdata->[$channelcount]->{lcn}$/, @lcnlist ) );

        push(@lcnlist, $tmpdata->[$channelcount]->{lcn});
        $channeldata[$foundchannelcounter]->{name} = $tmpdata->[$channelcount]->{providerName};
        #$channeldata[$foundchannelcounter]->{id} = $tmpdata->[$channelcount]->{lcn}.".epg.com.au";
        $channeldata[$foundchannelcounter]->{lcn} = $tmpdata->[$channelcount]->{lcn};
        $channeldata[$foundchannelcounter]->{icon} = $tmpdata->[$channelcount]->{channelLogo};
        $channeldata[$foundchannelcounter]->{triplet} = $tmpdata->[$channelcount]->{id};
        my $programdata = $tmpdata->[$channelcount]->{programs};
            for (my $programs = 0; $programs < @$programdata; $programs++)
            {
                $guidedata[$programcount]->{lcn} = $tmpdata->[$channelcount]->{lcn};
                #$guidedata[$programcount]->{id} = $tmpdata->[$channelcount]->{lcn}.".epg.com.au";
    	    	$guidedata[$programcount]->{desc} = $programdata->[$programs]->{description} if (defined($programdata->[$programs]->{description}));
                $guidedata[$programcount]->{title} = $programdata->[$programs]->{title};
        		#$guidedata[$programcount]->{subtitle} = $showdata->{episodeTitle}; 20220926231500 +1000
                $guidedata[$programcount]->{start_seconds} = $programdata->[$programs]->{roundedStartTime};
                $guidedata[$programcount]->{stop_seconds} = $programdata->[$programs]->{roundedEndTime};
                my $actual_startdt = DateTime->from_epoch( epoch => $programdata->[$programs]->{startTime}, time_zone => 'UTC' );
                my $startdt = DateTime->from_epoch( epoch => $programdata->[$programs]->{roundedStartTime}, time_zone => 'UTC' );
                my $stopdt = DateTime->from_epoch( epoch => $programdata->[$programs]->{roundedEndTime}, time_zone => 'UTC' );
                $guidedata[$programcount]->{date} = $startdt->ymd();
                $guidedata[$programcount]->{actualstart} = $actual_startdt->ymd('').$actual_startdt->hms('')." +0000";
                $guidedata[$programcount]->{start} = $startdt->ymd('').$startdt->hms('')." +0000";
                $guidedata[$programcount]->{stop} = $stopdt->ymd('').$stopdt->hms('')." +0000";
                $guidedata[$programcount]->{category} = $programdata->[$programs]->{category};# if (defined($programdata->[$programs]->{genres}));
                if (defined($programdata->[$programs]->{episode}))
                {
                    $guidedata[$programcount]->{episode} = $programdata->[$programs]->{episode};
                }
                if (defined($programdata->[$programs]->{season}))
                {
                    $guidedata[$programcount]->{season} = $programdata->[$programs]->{season};
                }
                if ((!defined($programdata->[$programs]->{season})) and (defined($programdata->[$programs]->{episode})))
                {
                    $guidedata[$programcount]->{season} = $startdt->year();
                }
                if ((defined($programdata->[$programs]->{classification})) and (($programdata->[$programs]->{classification}) ne ""))
                {
                    $guidedata[$programcount]->{rating} = $programdata->[$programs]->{classification};
                }                
                $guidedata[$programcount]->{originalairdate} = $startdt->ymd('-');#." ".$startdt->hms(':');
                $guidedata[$programcount]->{icon} = $programdata->[$programs]->{imageList}->[0]->{url};
				$guidedata[$programcount]->{quality} = "SDTV";
				if ($programdata->[$programs]->{isHD})
				{
					$guidedata[$programs]->{quality} = "HDTV";
				}                
        		#$guidedata[$programcount]->{title} = $showdata->{title};
    	    	#$guidedata[$programcount]->{rating} = $showdata->{classification};
    		    #$guidedata[$programcount]->{quality} = "SDTV";
                #print "$programcount $guidedata[$programcount]->{title}  $guidedata[$programcount]->{start} $programdata->[$programs]->{startTime}\n";
                $programcount++;               
            }
        $foundchannelcounter++;
    }
    return \@channeldata, \@guidedata;
}

return 1;