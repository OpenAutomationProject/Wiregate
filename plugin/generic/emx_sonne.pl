# Plugin zur Berechnung von Sonnenauf- und -untergang. 
# Die Berechnungsgrundlagen stammen nach einer Anregung aus dem 
# knx-user-forum.de von der Seite: 
# http://austernkommunikation.wordpress.com/2008/05/31/sonnenaufgang-berechnen-mit-perl/
#
# Die Werte werden in %plugin_info abgelegt:
# $plugin_info{emx_sonne.pl.auf} : Sonnenaufgang dezimal, z.B: 5,8 Uhr = 5:48 Uhr
# $plugin_info{emx_sonne.pl.unt} : Sonnenuntergang dezimal, dto.
# $plugin_info{emx_sonne.pl.aufHH} : Sonnenaufgang, Stunde, z.B. 5 
# $plugin_info{emx_sonne.pl.aufMM} : Sonnenaufgang, Minute, z.B. 48 
# $plugin_info{emx_sonne.pl.untHH} : Sonnenuntergang, Stunde dto.
# $plugin_info{emx_sonne.pl.untMM} : Sonnenuntergang, Minute dto.
#
# Die ...HH und ..MM Zeiten dienen zur Verwendung im emx_uhr.pl Plugin.
#
# Die Ausfuehrung erfolgt beim der ersten Ausfuehrung sofort, danach immer 
# einmal taeglich gegen 1:00 Uhr morgens.
#
# $Id$
#
# Copyright: Edgar (emax) Hermanns, forum at hermanns punkt net
#--------------------------------------------------------------------
#  CHANGE LOG:
#  ##  who  yyyymmdd   bug#  description
#  --  ---  --------  -----  ----------------------------------------
#   .  ...  ........  .....  vorlage 
#   1  edh  20120326  .....  Berechnungszeitpunkt auf 3:xx Uhr verlegt,
#                             weil die Zeiten sonst vor der 
#                             Umstellungsuhrzeit errechnet werden, und
#                             das am Umstellungstag Winter->Sommer zu 
#                             zu Fehlern führt: An diesem Tag wären
#                             dann die Sommerzeit noch nicht berück-
#                             sichtigt.                            
#   0  edh  20111023  -----  erste Version

use Math::Trig;
use POSIX;

# Default: Berlin
my $Breite     = 52.5167;
my $Laenge     = 13.4;

# updateUhrzeit 3:11:13, ungerade Zeit um Rechenstaus zu vermeiden
my $updateZeit = 11473; #  HH*3600 + MM*60 + SS = 3*3600 + 11*60 + 13 = 11473;
my $einTag     = 86400; # 24*3600;

sub calculateSun()
{
    my ($yddd, $timezone) = @_;
    ++$yddd;
    
    my $RAD                          = pi/180.0;
    my $B                            = $Breite * $RAD;
    my $zeitgleichung                = -0.171 * sin(0.0337 * $yddd + 0.465) - 0.1299 * sin(0.01787 * $yddd - 0.168);
    my $deklination                  = 0.4095 * sin(0.016906 * ($yddd - 80.086));
    my $timediff                     = 12* acos( (sin(-0.0145) - (sin($B) * sin($deklination))) / (cos($B) * cos($deklination)) )/pi;
    my $sAuf                         = 12 - $timediff - $zeitgleichung + (15-$Laenge)*4/60 + $timezone;
    my $sUnt                         = 12 + $timediff - $zeitgleichung + (15-$Laenge)*4/60 + $timezone;
    my $sAufHH                       = int($sAuf);
    my $sUntHH                       = int($sUnt);

    $plugin_info{"$plugname.tag"}    = $yddd-1;
    $plugin_info{"$plugname.laenge"} = $Laenge;
    $plugin_info{"$plugname.breite"} = $Breite;
    $plugin_info{"$plugname.auf"}    = $sAuf;
    $plugin_info{"$plugname.unt"}    = $sUnt;
    $plugin_info{"$plugname.aufHH"}  = $sAufHH;
    $plugin_info{"$plugname.aufMM"}  = int(($sAuf - $sAufHH) * 60);
    $plugin_info{"$plugname.untHH"}  = $sUntHH;
    $plugin_info{"$plugname.untMM"}  = int(($sUnt - $sUntHH) * 60);
    plugin_log($plugname, " calculated sunrise[$sAuf], sunset[$sUnt], LAT[$Breite], LON[$Laenge]");
}

sub readConf
{
    my $confFile = '/etc/wiregate/plugin/generic/conf.d/'.basename($plugname,'.pl').'.conf';
    if (! -f $confFile)
    {
        plugin_log($plugname, " no conf file [$confFile] found."); 
    }
    else
    {
        plugin_log($plugname, " reading conf file [$confFile]."); 
        open(CONF, $confFile);
        my @lines = <CONF>;
        close($confFile);
        my $result = eval("@lines");
        ($result) and plugin_log($plugname, "conf file [$confFile] returned result[$result]");
        if ($@) 
        {
            plugin_log($plugname, " conf file [$confFile] returned:");
            my @parts = split(/\n/, $@);
            plugin_log($plugname, " --> $_") foreach (@parts);
        }
    }
} # readConf

#     0    1    2     3     4    5     6     7     8
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$timezone) = localtime(time);
&readConf();

(!defined $plugin_info{"$plugname.tag"}) and $plugin_info{"$plugname.tag"} = -1;

($plugin_info{"$plugname.tag"}    != $yday   ||
 $plugin_info{"$plugname.laenge"} != $Laenge ||
 $plugin_info{"$plugname.breite"} != $Breite) and &calculateSun($yday, $timezone);

# bis updateZeit warten, dann neu rechnen
$plugin_info{$plugname.'_cycle'} = $einTag - ($hour*3600 + $min*60 + $sec) + $updateZeit;
