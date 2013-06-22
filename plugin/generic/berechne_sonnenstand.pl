#############################################################################
# Plugin: Berechnung Azimuth und Elevation per Standort
# V1.0 2013-05-06
# Copyright: Marcus Lichtenberger (marcus@lichtenbergers.at)
# License: GPL (v3)
#
# Das Ergebnis dieses Plugins kann in mehreren anderen Plugins verwendet werden.
#
#############################################################################
#
# Änderungshistorie:
# 20130506 - mclb - Erstellung
# 20130617 - mclb - Azimuth und Elevation werden nun zusätzlich auf GAs geschrieben.
#
#############################################################################
#
# Offene Punkte:
# - Dzt. keine bekannt
#
#############################################################################
#
# Abhängigkeiten:
# - Paket libastro-satpass-perl
#   - Astro::Coord::ECI;
#   - Astro::Coord::ECI::Sun;
#   - Astro::Coord::ECI::TLE;
#   - Astro::Coord::ECI::Utils qw{rad2deg deg2rad};
#   - Installation:
#     - Wiregate Web-IF unter Updates Paket installieren libastro-satpass-perl oder
#     - in der Konsole apt-get -install libastro-satpass-perl
#
#############################################################################
#
# plugin_info-Werte
# - azimuth: Azimuth-Wert
# - elevation: Elevation-Wert
#
#############################################################################

# Module laden
use Astro::Coord::ECI;
use Astro::Coord::ECI::Sun;
use Astro::Coord::ECI::TLE;
use Astro::Coord::ECI::Utils qw{rad2deg deg2rad};

my $gv_lat;
my $gv_lon;
my $gv_elev;
my $show_debug;

my $gv_azimuth;
my $gv_elevation;
my $gv_gaAzimuth;
my $gv_gaElevation;

# Read config file in conf.d
my $confFile = '/etc/wiregate/plugin/generic/conf.d/'.basename($plugname,'.pl').'.conf';
if (! -f $confFile)
{
  plugin_log($plugname, "0.1 - no conf file [$confFile] found.") if ($show_debug > 0); 
  return "no conf file [$confFile] found.";
}
else
{
  plugin_log($plugname, "0.2 - reading conf file [$confFile].") if ($show_debug > 0); 
  open(CONF, $confFile);
  my @lines = <CONF>;
  close($confFile);
  my $result = eval("@lines");
  if( $show_debug > 1 )
  {
    ($result) and plugin_log($plugname, "0.3 - conf file [$confFile] returned result[$result]");
  }
  if ($@) 
  {
    plugin_log($plugname, "0.4 - conf file [$confFile] returned:") if ($show_debug > 0);
    my @parts = split(/\n/, $@);
    if( $show_debug > 1 )
    {
      plugin_log($plugname, "0.5 - --> $_") foreach (@parts);
    }
  }
}

# Ruf mich alle 5 Minuten selbst auf und berechne Azimuth und Elevation neu
$plugin_info{$plugname.'_cycle'} = 300;

($gv_azimuth, $gv_elevation) = berechneSonnenstand($gv_lat, $gv_lon, $gv_elev);

plugin_log($plugname, '1 - Azimuth alt: '.$plugin_info{'azimuth'}.', Azimuth neu: '.$gv_azimuth) if ($show_debug > 0);
plugin_log($plugname, '2 - Elevation alt: '.$plugin_info{'elevation'}.', Elevation neu: '.$gv_elevation) if ($show_debug > 0);

if ($gv_azimuth ne $plugin_info{'azimuth'} or $gv_elevation ne $plugin_info{'elevation'}) {
  $plugin_info{'azimuth'} = $gv_azimuth;
  $plugin_info{'elevation'} = $gv_elevation;

  if ($gv_gaAzimuth ne '') { knx_write($gv_gaAzimuth, $gv_azimuth); }
  if ($gv_gaElevation ne '') { knx_write($gv_gaElevation, $gv_elevation); }
}

return 'Sonnenstand erfolgreich berechnet!';

####################################################
# Aufruf mit berechneSonnenstand($lat, $lon, $elev);
####################################################
sub berechneSonnenstand {
 # Aktuelle Zeit
 my $lv_time = time ();
 # Die eigenen Koordinaten
 my $lv_loc = Astro::Coord::ECI->geodetic(deg2rad(shift), deg2rad(shift), shift);
 # Sonne instanzieren
 my $lv_sun = Astro::Coord::ECI::Sun->universal($lv_time);
 # Feststellen wo die Sonne gerade ist
 my ($lv_azimuth, $lv_elevation, $lv_range) = $lv_loc->azel($lv_sun);
 $lv_azimuth = rad2deg($lv_azimuth);
 $lv_elevation = rad2deg($lv_elevation);
 return ($lv_azimuth, $lv_elevation);
}