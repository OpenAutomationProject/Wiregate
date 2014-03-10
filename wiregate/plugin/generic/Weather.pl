# Weather Plugin
# Version 0.01
# by ctr (http://knx-user-forum.de/members/ctr.html)
# based on
# - Plugin zum Abfragen von Google Weather (by jensgulow)
# - Wundergroundweather (by Bodo)
# Copyright: ctr
# License: GPL (v2)

my $provider;
my $city;
my $country;
my $lang;
my $api;

my $weather_update_ga;
my $weather_temp_ga;
my $weather_hum_ga;
my $weather_clouds_ga;
my $weather_wind_ga;
my $weather_wind_speed_ga;
my $weather_wind_dir_ga;

my $weather_current_temp;
my $weather_current_humidity;
my $weather_current_clouds;
my $weather_current_wind;
my $weather_current_windchill;
my $weather_current_wind_speed;
my $weather_current_wind_dir;
my $weather_current_sunrise;
my $weather_current_sunset;
my @weather_forecast_maxtemp;
my @weather_forecast_mintemp;
my @weather_forecast_clouds;
my @weather_forecast_day;
my @weather_forecast_pop;

my $show_debug = 0;

use Switch;

my $confFile = '/etc/wiregate/plugin/generic/conf.d/'.basename($plugname,'.pl').'.conf';
if (! -f $confFile)
{
  plugin_log($plugname, " no conf file [$confFile] found.");
  return("error");
}
else
{
  plugin_log($plugname, " reading conf file [$confFile].") if( $show_debug > 1);
  open(CONF, $confFile);
  my @lines = <CONF>;
  close($confFile);
  my $result = eval("@lines");
  if( $show_debug > 1 )
  {
    ($result) and plugin_log($plugname, "conf file [$confFile] returned result[$result]");
  }
  if ($@)
  {
    plugin_log($plugname, "conf file [$confFile] returned:") if( $show_debug > 1 );
    my @parts = split(/\n/, $@);
    if( $show_debug > 1 )
    {
      plugin_log($plugname, "--> $_") foreach (@parts);
    }
  }
}




if (not defined($plugin_info{$plugname.'_cycle'})) {
  $plugin_info{$plugname.'_cycle'} = 1800;    # Eigenen Aufruf-Zyklus setzen (Initialisierung/zyklisches pr&uuml;fen) 
                        # nicht zu klein, da die Daten sowieso in l&auml;ngeren Perioden refresht werden
                        # und das Plugin auf die CF schreibt.
}

sub Wunderground {
  my $wunderground_baseurl        = "http://api.wunderground.com/api/";
  use LWP::Simple;
  use XML::Simple;
  my $url = $wunderground_baseurl.$api."/conditions/forecast/astronomy/lang:".$lang."/q/".$country."\/".$city."\.xml";
  my $xml = get($url);
  return "Couldn't get it!" unless defined $xml;
  my $weather = XMLin($xml,SuppressEmpty => '');
  # current weather
  $weather_current_temp		=  $weather->{current_observation}->{temp_c};
  ($weather_current_humidity)	= ($weather->{current_observation}->{relative_humidity} =~ m/(\d{1,3})\D/);
# $weather_current_wind		=  $weather->{current_observation}->{wind_string};
  SELECT:{
    if ($weather->{current_observation}->{wind_kph}  <  1.08)	{ $weather_current_wind =  "0"; last SELECT; }
    if ($weather->{current_observation}->{wind_kph}  <  5.76)	{ $weather_current_wind =  "1"; last SELECT; }
    if ($weather->{current_observation}->{wind_kph}  <  12.24)	{ $weather_current_wind =  "2"; last SELECT; }
    if ($weather->{current_observation}->{wind_kph}  <  19.8)	{ $weather_current_wind =  "3"; last SELECT; }
    if ($weather->{current_observation}->{wind_kph}  <  28.8)	{ $weather_current_wind =  "4"; last SELECT; }
    if ($weather->{current_observation}->{wind_kph}  <  38.88)	{ $weather_current_wind =  "5"; last SELECT; }
    if ($weather->{current_observation}->{wind_kph}  <  50.04)	{ $weather_current_wind =  "6"; last SELECT; }
    if ($weather->{current_observation}->{wind_kph}  <  61.92)	{ $weather_current_wind =  "7"; last SELECT; }
    if ($weather->{current_observation}->{wind_kph}  <  74.88)	{ $weather_current_wind =  "8"; last SELECT; }
    if ($weather->{current_observation}->{wind_kph}  <  88.2)	{ $weather_current_wind =  "9"; last SELECT; }
    if ($weather->{current_observation}->{wind_kph}  < 102.6)	{ $weather_current_wind = "10"; last SELECT; }
    if ($weather->{current_observation}->{wind_kph}  < 117.72)	{ $weather_current_wind = "11"; last SELECT; }
    if ($weather->{current_observation}->{wind_kph} >= 117.72)	{ $weather_current_wind = "12"; last SELECT; }
  }
  $weather_current_wind_speed	=  $weather->{current_observation}->{wind_kph};
  $weather_current_wind_dir	=  $weather->{current_observation}->{wind_dir};
  if ($weather->{current_observation}->{weather}) {
    $weather_current_clouds	=  $weather->{current_observation}->{weather};
  } else {
    $weather_current_clouds	= "Klar";
  }
  $weather_current_windchill	= $weather->{current_observation}->{windchill_c};
  $weather_current_sunset	= $weather->{moon_phase}->{sunset}->{hour}.":".$weather->{moon_phase}->{sunset}->{minute};
  $weather_current_sunrise	= $weather->{moon_phase}->{sunrise}->{hour}.":".$weather->{moon_phase}->{sunrise}->{minute};
  #forecast
  for (my $i = 0; $i <= 3; $i++) {
    $weather_forecast_maxtemp[$i]	=  $weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$i]->{high}->{celsius};
    $weather_forecast_mintemp[$i]	=  $weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$i]->{low}->{celsius};
    $weather_forecast_clouds[$i]	=  $weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$i]->{conditions};
    $weather_forecast_day[$i]		=  $weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$i]->{date}->{weekday};
    $weather_forecast_pop[$i]		=  $weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$i]->{pop};
  }
} # Ende "sub Wunderground"


sub Results {
  $plugin_info{$plugname.'_current_temp'} = $weather_current_temp." °C";
  if ($weather_hum_ga) { knx_write($weather_hum_ga,$weather_current_humidity,9); }
  $plugin_info{$plugname.'_current_humidity'} = $weather_current_humidity." %";
  if ($weather_clouds_ga) { knx_write($weather_clouds_ga,$weather_current_clouds,16); }
  $plugin_info{$plugname.'_current_clouds'} = $weather_current_clouds;
  if ($weather_wind_ga) { knx_write($weather_wind_ga,$weather_current_wind,16); }
  $plugin_info{$plugname.'_current_wind'} = $weather_current_wind;
  if ($weather_wind_speed_ga) { knx_write($weather_wind_speed_ga,$weather_current_wind_speed,16); }
  $plugin_info{$plugname.'_current_wind_speed'} = $weather_current_wind_speed;
  if ($weather_wind_ga) { knx_write($weather_wind_dir_ga,$weather_current_wind_dir,16); }
  $plugin_info{$plugname.'_current_wind_dir'} = $weather_current_wind_dir;
  $plugin_info{$plugname.'_current_sunset'} = $weather_current_sunset;
  $plugin_info{$plugname.'_current_sunrise'} = $weather_current_sunrise;
  for (my $i = 0; $i <= 3; $i++) {
    $plugin_info{$plugname.'_forecast_maxtemp'.$i}	= $weather_forecast_maxtemp[$i]." °C";
    $plugin_info{$plugname.'_forecast_mintemp'.$i}	= $weather_forecast_mintemp[$i]." °C";
    $plugin_info{$plugname.'_forecast_clouds'.$i}	= $weather_forecast_clouds[$i];
    $plugin_info{$plugname.'_forecast_day'.$i}		= $weather_forecast_day[$i];
    $plugin_info{$plugname.'_forecast_pop'.$i}		= $weather_forecast_pop[$i]." %";
  }
  knx_write($weather_update_ga,1,1);
} # Ende "sub Results"


if (lc $provider eq "wunderground" ) {
  Wunderground();
  Results();
  return("Done");
} else {
  return("no valid provider defined");
}
