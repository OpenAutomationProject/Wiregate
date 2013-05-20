#############################################################################
# Plugin: Aufzeichnung von Werten in RRDs
# V1.0 2013-05-19
# Copyright: Marcus Lichtenberger (marcus@lichtenbergers.at)
# License: GPL (v3)
#
#############################################################################
#
# Plugin zur Aufzeichnung von Werten (z.B. Temperaturen) die über GAs
# empfangen werden in RRDs.
#
#############################################################################
#
# Änderungshistorie:
# 20130519 - mclb - Erstellung
#
#############################################################################
#
# Offene Punkte:
# - dzt. keine bekannt
#
#############################################################################
#
# Abhängigkeiten:
# - keine
#
#############################################################################
#
# plugin_info-Werte
# - Für jeden aufzuzeichnenden Wert einen plugin_info-Wert damit der Wert gemerkt bleibt.
#
#############################################################################

# Konstanten für Aufrufart
use constant EVENT_RESTART => 'restart';
use constant EVENT_MODIFIED => 'modified';
use constant EVENT_BUS => 'bus';
use constant EVENT_SOCKET => 'socket';
use constant EVENT_CYCLE => 'cycle';

# Variablendefinitionen
my $show_debug = 1; # switches debug information that will be shown in the log
my $gs_wert;
my @gt_werte;

# Read config file in conf.d
my $confFile = '/etc/wiregate/plugin/generic/conf.d/'.basename($plugname,'.pl').'.conf';
if (! -f $confFile)
{
  plugin_log($plugname, " no conf file [$confFile] found."); 
  return "no conf file [$confFile] found.";
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

# Ruf mich auf, wenn ich einen der Werte erhalte
foreach $gs_wert (@gt_werte) {
 if ($gs_wert->{gaWert} ne "") {
  $plugin_subscribe{$gs_wert->{gaWert}}{$plugname} = 1;
 }
}
# Außerdem ruf mich alle 5 Minuten zum Wegschreiben der Werte auf
$plugin_info{$plugname.'_cycle'} = 300;

# Aus welchem Grund läuft das Plugin gerade
my $gv_event=undef;
if (!$plugin_initflag) {
 $gv_event = EVENT_RESTART;            # Restart des daemons / Reboot
} elsif ($plugin_info{$plugname.'_lastsaved'} > $plugin_info{$plugname.'_last'}) {
 $gv_event = EVENT_MODIFIED;        # Plugin modifiziert
} elsif (%msg) {
 $gv_event = EVENT_BUS;                # Bustraffic
} elsif ($fh) {
 $gv_event = EVENT_SOCKET;            # Netzwerktraffic
} else {
 $gv_event = EVENT_CYCLE;            # Zyklus
}

plugin_log($plugname, '0 - Aufrufgrund: '.$gv_event) if ($show_debug > 0);

if ($gv_event eq EVENT_RESTART) {
} elsif ($gv_event eq EVENT_MODIFIED) {
} elsif ($gv_event eq EVENT_BUS) {
 # Merke dir den aktuellen Wert
 foreach $gs_wert (@gt_werte) {
  if ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $gs_wert->{gaWert}) {
   plugin_log($plugname, '1 - GA: '.$gs_wert->{gaWert}.', Wert: '.$msg{'value'}) if ($show_debug > 0);
   $plugin_info{$plugname.'_'.$gs_wert->{id}} = $msg{'value'};
  }
 }
} elsif ($gv_event eq EVENT_SOCKET) {
} elsif ($gv_event eq EVENT_CYCLE) {
 # Schreibe die aktuellen Werte weg ins RRD (alle 5 Minuten)
 foreach $gs_wert (@gt_werte) {
  plugin_log($plugname, '2 - GA: '.$gs_wert->{gaWert}.', Wert: '.$plugin_info{$plugname.'_'.$gs_wert->{id}}) if ($show_debug > 0);
  update_rrd($gs_wert->{rrdName},"",$plugin_info{$plugname.'_'.$gs_wert->{id}});
 }
}

return 'Aufzeichnung erfolgreich erledigt!';