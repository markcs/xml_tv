#!/usr/bin/perl
use strict;
use warnings;

my %ABCRADIO;
$ABCRADIO{"200"}{name}			= "Double J";
$ABCRADIO{"200"}{iconurl}		= "https://www.abc.net.au/cm/lb/8811932/thumbnail/station-logo-thumbnail.jpg";
$ABCRADIO{"200"}{servicename}	= "doublej";
$ABCRADIO{"201"}{name}  		= "ABC Jazz";
$ABCRADIO{"201"}{iconurl}		= "https://www.abc.net.au/cm/lb/8785730/thumbnail/station-logo-thumbnail.png";
$ABCRADIO{"201"}{servicename} 	= "jazz";
$ABCRADIO{"202"}{name}			= "ABC Kids Listen";
$ABCRADIO{"202"}{iconurl}		= "https://raw.githubusercontent.com/mathewcallaghan/australian-tv-network-logo-icons/master/colour/abc%20kids%20listen.png";
$ABCRADIO{"202"}{servicename}	= "kidslisten";
$ABCRADIO{"203"}{name}			= "ABC Country";
$ABCRADIO{"203"}{iconurl}		= "https://www.abc.net.au/radio/images/service/2018/country_480.png";
$ABCRADIO{"203"}{servicename}	= "";
$ABCRADIO{"204"}{name}			= "ABC News Radio";
$ABCRADIO{"204"}{iconurl}		= "https://upload.wikimedia.org/wikipedia/commons/e/ee/ABC_News_Radio_2014.png";
$ABCRADIO{"204"}{servicename}	= "";

$ABCRADIO{"26"}{name}			= "ABC Radio National";
$ABCRADIO{"26"}{iconurl}		= "https://www.abc.net.au/news/image/8054480-3x2-940x627.jpg";
$ABCRADIO{"26"}{servicename}	= "RN";
$ABCRADIO{"27"}{name}			= "ABC Classic";
$ABCRADIO{"27"}{iconurl}		= "https://www.abc.net.au/cm/lb/9104270/thumbnail/station-logo-thumbnail.png";
$ABCRADIO{"27"}{servicename}	= "classic";
$ABCRADIO{"28"}{name}  			= "Triple J";
$ABCRADIO{"28"}{iconurl} 		= "https://www.abc.net.au/cm/lb/8541768/thumbnail/station-logo-thumbnail.png";
$ABCRADIO{"28"}{servicename}	= "triplej";
$ABCRADIO{"29"}{name}  			= "Triple J Unearthed";
$ABCRADIO{"29"}{iconurl} 		= "https://www.abc.net.au/cm/rimage/8869368-16x9-large.jpg?v=2";
$ABCRADIO{"29"}{servicename}	= "";

my %SBSRADIO;
$SBSRADIO{"36"}{name}   		= "SBS Arabic24";
$SBSRADIO{"36"}{iconurl}        = "https://raw.githubusercontent.com/mathewcallaghan/australian-tv-network-logo-icons/master/colour/sbs%20arabic24.png";
$SBSRADIO{"36"}{servicename}    = "poparaby";
$SBSRADIO{"37"}{name}   		= "SBS Radio 1";
$SBSRADIO{"37"}{iconurl}        = "https://raw.githubusercontent.com/mathewcallaghan/australian-tv-network-logo-icons/master/colour/sbs%20radio%201.png";
$SBSRADIO{"37"}{servicename}    = "sbs1";
$SBSRADIO{"38"}{name}   		= "SBS Radio 2";
$SBSRADIO{"38"}{iconurl}        = "https://raw.githubusercontent.com/mathewcallaghan/australian-tv-network-logo-icons/master/colour/sbs%20radio%202.png";
$SBSRADIO{"38"}{servicename}    = "sbs2";
$SBSRADIO{"39"}{name}   		= "SBS Chill";
$SBSRADIO{"39"}{iconurl}        = "https://raw.githubusercontent.com/mathewcallaghan/australian-tv-network-logo-icons/master/colour/sbs%20chill.png";
$SBSRADIO{"39"}{servicename}    = "chill";

$SBSRADIO{"301"}{name}  		= "SBS Radio 1";
$SBSRADIO{"301"}{iconurl}       = "https://raw.githubusercontent.com/mathewcallaghan/australian-tv-network-logo-icons/master/colour/sbs%20radio%201.png";
$SBSRADIO{"301"}{servicename}   = "sbs1";

$SBSRADIO{"302"}{name}  		= "SBS Radio 2";
$SBSRADIO{"302"}{iconurl}       = "https://raw.githubusercontent.com/mathewcallaghan/australian-tv-network-logo-icons/master/colour/sbs%20radio%202.png";
$SBSRADIO{"302"}{servicename}   = "sbs2";

$SBSRADIO{"303"}{name}  		= "SBS Radio 3";
$SBSRADIO{"303"}{iconurl}       = "https://raw.githubusercontent.com/mathewcallaghan/australian-tv-network-logo-icons/master/colour/sbs%20radio%203.png";
$SBSRADIO{"303"}{servicename}   = "sbs3";

$SBSRADIO{"304"}{name}  		= "SBS Arabic24";
$SBSRADIO{"304"}{iconurl}       = "https://raw.githubusercontent.com/mathewcallaghan/australian-tv-network-logo-icons/master/colour/sbs%20arabic24.png";
$SBSRADIO{"304"}{servicename}   = "poparaby";

$SBSRADIO{"305"}{name}  		= "SBS PopDesi";
$SBSRADIO{"305"}{iconurl}       = "https://raw.githubusercontent.com/mathewcallaghan/australian-tv-network-logo-icons/master/colour/sbs%20popdesi.png";
$SBSRADIO{"305"}{servicename}   = "popdesi";

$SBSRADIO{"306"}{name}  		= "SBS Chill";
$SBSRADIO{"306"}{iconurl}       = "https://raw.githubusercontent.com/mathewcallaghan/australian-tv-network-logo-icons/master/colour/sbs%20chill.png";
$SBSRADIO{"306"}{servicename}   = "chill";

$SBSRADIO{"307"}{name}  		= "SBS PopAsia";
$SBSRADIO{"307"}{iconurl}       = "https://raw.githubusercontent.com/mathewcallaghan/australian-tv-network-logo-icons/master/colour/sbs%20popasia.png";
$SBSRADIO{"307"}{servicename}   = "popasia";

my $VERBOSE = 0;

################# RADIO

sub define_ABC_local_radio
{
	my $state = shift;
	$state =~ s/.*_(.*)_.*/$1/;
	
	my %definedregions = (
		"wa"	=> "local_perth", #     =       Perth
		"sa"	=> "local_adelaide", #       Adelaide
		"tas" 	=>	"local_hobart", #      Hobart
		"vic"	=>	"local_melbourne",	#Melbourne
		"qld"	=>	"local_brisbane",
		"nsw"	=>	"local_sydney",
		"nt"	=> 	"local_darwin",
		"act"	=> 	"local_canberra",
	);
	my %icons = (
		"wa"	=> "http://www.abc.net.au/radio/images/service/ABC-Radio-Perth.png",
		"sa"	=> "http://www.abc.net.au/radio/images/service/ABC-Radio-Adelaide.png",
		"tas" 	=>	"http://www.abc.net.au/radio/images/service/ABC-Radio-Hobart.png",
		"vic"	=>	"http://www.abc.net.au/radio/images/service/ABC-Radio-Melbourne.png",
		"qld"	=>	"http://www.abc.net.au/radio/images/service/ABC-Radio-Brisbane.png",
		"nsw"	=>	"http://www.abc.net.au/radio/images/service/ABC-Radio-Sydney.png",
		"nt"	=> 	"http://www.abc.net.au/radio/images/service/ABC-Radio-Darwin.png",
		"act"	=> 	"http://www.abc.net.au/radio/images/service/ABC-Radio-Canberra.png",
	);
	$ABCRADIO{"25"}{name}  = "ABC Local Radio";
	$ABCRADIO{"25"}{iconurl}       = $icons{$state};
	$ABCRADIO{"25"}{servicename}   = $definedregions{$state};
}

sub radio_ABCgetchannels
{
	my $regioninfo = shift;
	define_ABC_local_radio($regioninfo->{fvregion});
	my $count = 0;
	my @tmpdata;
	foreach my $key (keys %ABCRADIO)
	{
		#next if ( ( grep( /^$key$/, @IGNORECHANNELS ) ) );
		#next if ( ( !( grep( /^$key$/, @INCLUDECHANNELS ) ) ) and ((@INCLUDECHANNELS > 0)));
		$tmpdata[$count]->{name} = $ABCRADIO{$key}{name};
		#$tmpdata[$count]->{id} = $key.".epg.com.au";
		$tmpdata[$count]->{lcn} = $key;
		$tmpdata[$count]->{icon} = $ABCRADIO{$key}{iconurl};
		$count++;
	}
	return @tmpdata;
}

sub radio_ABCgetepg
{
	my ($ua, $numdays) = @_;
	my $showcount = 0;
	my @tmpguidedata;
	warn("\nGetting epg for ABC Radio Stations ...\n") if ($VERBOSE);
	foreach my $key (keys %ABCRADIO)
	{
		#next if ( ( grep( /^$key$/, @IGNORECHANNELS ) ) );
		#next if ( ( !( grep( /^$key$/, @INCLUDECHANNELS ) ) ) and ((@INCLUDECHANNELS > 0)));
		my $id = $key;
		warn("$ABCRADIO{$key}{name} ...\n") if ($VERBOSE);
		next if ($ABCRADIO{$key}{servicename} eq "");
		my ($ssec,$smin,$shour,$smday,$smon,$syear,$swday,$syday,$sisdst) = localtime(time-86400);
		my ($esec,$emin,$ehour,$emday,$emon,$eyear,$ewday,$eyday,$eisdst) = localtime(time+(86400*$numdays));
		my $startdate = sprintf("%0.4d-%0.2d-%0.2dT%0.2d:%0.2d:%0.2d.000Z",($syear+1900),$smon+1,$smday,$shour,$smin,$ssec);
		my $enddate = sprintf("%0.4d-%0.2d-%0.2dT%0.2d:%0.2d:%0.2d.000Z",($eyear+1900),$emon+1,$emday,$ehour,$emin,$esec);
		my $url = URI->new( 'https://program.abcradio.net.au/api/v1/programitems/search.json' );
		$url->query_form(service => $ABCRADIO{$key}{servicename}, limit => '100', order => 'asc', order_by => 'ppe_date', from => $startdate, to => $enddate);
		my $res = geturl($ua,$url);
		if (!$res->is_success)
		{
			warn("Unable to connect to ABC radio schedule: URL: $url. [" . $res->status_line . "]\n");
			next;
		}
		my $tmpdata;
		eval {
			$tmpdata = JSON->new->relaxed(1)->allow_nonref(1)->decode($res->content);
			1;
		};
		$tmpdata = $tmpdata->{items};		
		if (defined($tmpdata))
		{
			for (my $count = 0; $count < @$tmpdata; $count++)
			{
				#$tmpguidedata[$showcount]->{id} = $key.".epg.com.au";
				$tmpguidedata[$showcount]->{lcn} = $key;
				$tmpguidedata[$showcount]->{start} = $tmpdata->[$count]->{live}[0]->{start};				
				if (defined($tmpdata->[$count]->{live}[1]) )
				{
				     $tmpguidedata[$showcount]->{start} = toLocalTimeString($tmpdata->[$count]->{live}[1]->{start},'UTC');
					 if (defined($tmpdata->[$count]->{live}[1]->{end}))
					 {
						$tmpguidedata[$showcount]->{stop} = toLocalTimeString($tmpdata->[$count]->{live}[1]->{end},'UTC');
					 }
					 else
					 {
						my $duration = $tmpdata->[$count]->{live}[1]->{duration_seconds}/60;
						$tmpguidedata[$showcount]->{stop} = addTime($duration,$tmpguidedata[$showcount]->{start});
					 }	 
				}
				else
				{
				     $tmpguidedata[$showcount]->{start} = toLocalTimeString($tmpdata->[$count]->{live}[0]->{start},'UTC');
					 if (defined($tmpdata->[$count]->{live}[0]->{end}))
					 {
						$tmpguidedata[$showcount]->{stop} = toLocalTimeString($tmpdata->[$count]->{live}[0]->{end},'UTC');
					 }
					 else
					 {
						my $duration = $tmpdata->[$count]->{live}[0]->{duration_seconds}/60;
						$tmpguidedata[$showcount]->{stop} = addTime($duration,$tmpguidedata[$showcount]->{start});
					 }					 
				} 
				$tmpguidedata[$showcount]->{start} =~ s/[-T:]//g;
				$tmpguidedata[$showcount]->{start} =~ s/\+/ \+/g;
				$tmpguidedata[$showcount]->{stop} =~ s/[-T:]//g;
				$tmpguidedata[$showcount]->{stop} =~ s/\+/ \+/g;
				$tmpguidedata[$showcount]->{channel} = $ABCRADIO{$key}{name};
				$tmpguidedata[$showcount]->{title} = $tmpdata->[$count]->{title};
				my $catcount = 0;
				$tmpguidedata[$showcount]->{category} = "Radio";
				if (defined($tmpdata->[$count]->{short_synopsis}))
				{
					$tmpguidedata[$showcount]->{desc} = $tmpdata->[$count]->{short_synopsis};
				}
				elsif (defined($tmpdata->[$count]->{mini_synopsis}))
				{
					$tmpguidedata[$showcount]->{desc} = $tmpdata->[$count]->{mini_synopsis};
				}
				$showcount++;
				}
			}
		}
	warn("Processed a total of $showcount shows ...\n") if ($VERBOSE);
	return @tmpguidedata;
}

sub radio_SBSgetchannels
{
	my @tmpdata;
	my $count = 0;
	foreach my $key (keys %SBSRADIO)
	{
		#next if ( ( grep( /^$key$/, @IGNORECHANNELS ) ) );
		#next if ( ( !( grep( /^$key$/, @INCLUDECHANNELS ) ) ) and ((@INCLUDECHANNELS > 0)));
		$tmpdata[$count]->{name} = $SBSRADIO{$key}{name};
		#$tmpdata[$count]->{id} = $key.".epg.com.au";
		$tmpdata[$count]->{lcn} = $key;
		$tmpdata[$count]->{icon} = $SBSRADIO{$key}{iconurl};
		$count++;
	}
	return @tmpdata;
}

sub radio_SBSgetepg
{
	my ($ua, $numdays) = @_;
	my $showcount = 0;
	my @tmpguidedata;
	warn("\nGetting epg for SBS Radio Stations ...\n") if ($VERBOSE);
	foreach my $key (keys %SBSRADIO)
	{
		#next if ( ( grep( /^$key$/, @IGNORECHANNELS ) ) );
		#next if ( ( !( grep( /^$key$/, @INCLUDECHANNELS ) ) ) and ((@INCLUDECHANNELS > 0)));
		my $id = $key;
		warn("$SBSRADIO{$key}{name} ...\n") if ($VERBOSE);
		my $now = time;;
		my ($ssec,$smin,$shour,$smday,$smon,$syear,$swday,$syday,$sisdst) = localtime(time);
		my ($esec,$emin,$ehour,$emday,$emon,$eyear,$ewday,$eyday,$eisdst) = localtime(time+(86400*$numdays));
		my $startdate = sprintf("%0.4d-%0.2d-%0.2dT%0.2d:%0.2d:%0.2dZ",($syear+1900),$smon+1,$smday,$shour,$smin,$ssec);
		my $enddate = sprintf("%0.4d-%0.2d-%0.2dT%0.2d:%0.2d:%0.2dZ",($eyear+1900),$emon+1,$emday,$ehour,$emin,$esec);

		my $url = "https://epgservice.c.aws.sbs.com.au/api/v1/radio-guide.json?channel=".$SBSRADIO{$key}{servicename}."&days=".$numdays;
		my $res = geturl($ua,$url);
		if (!$res->is_success)
		{
			warn("Unable to connect to SBS radio schedule: URL: $url.. [" . $res->status_line . "]\n");
			next;
		}
		my $tmpdata;
		eval
		{
			$tmpdata = JSON->new->relaxed(1)->allow_nonref(1)->decode($res->content);
			1;
		};
		$tmpdata = $tmpdata->{data};
		if (defined($tmpdata))
		{
			my $count = 0;
			for (my $count = 0; $count < @$tmpdata; $count++)
			{
				#$tmpguidedata[$showcount]->{id} = $id.".epg.com.au";
				$tmpguidedata[$showcount]->{lcn} = $id;
				$tmpguidedata[$showcount]->{start} = $tmpdata->[$count]->{start};
				$tmpguidedata[$showcount]->{start} =~ s/[-T:\s]//g;
				$tmpguidedata[$showcount]->{start} =~ s/(\+)/ +/;
				$tmpguidedata[$showcount]->{stop} = $tmpdata->[$count]->{end};
				$tmpguidedata[$showcount]->{stop} =~ s/[-T:\s]//g;
				$tmpguidedata[$showcount]->{stop} =~ s/(\+)/ +/;
				$tmpguidedata[$showcount]->{channel} = $SBSRADIO{$key}{name};
				$tmpguidedata[$showcount]->{title} = $tmpdata->[$count]->{title};
				$tmpguidedata[$showcount]->{category} = "Radio";
				$tmpguidedata[$showcount]->{desc} = $tmpdata->[$count]->{description};# if (!(ref $desc eq ref {}));
				$showcount++;
			}
		}
	}	
	warn("Processed a total of $showcount shows ...\n") if ($VERBOSE);
	return @tmpguidedata;
}

return 1;