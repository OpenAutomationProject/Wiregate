#############################################################################
# Licht nachts nach dem einschalten auf einen definierten Dimmwert stellen
# V1.0 2012-08-21
# Copyright: Marcus Lichtenberger (marcus@lichtenbergers.at)
# License: GPL (v3)
#
#############################################################################
#
# Wenn nachts ein Licht eingeschaltet wird das hier definiert wurde,
# soll es nur auf einen bestimmten Dimmwert gefahren werden.
# Das heißt, es wird sofort nach dem Einschalt-Telegramm ein Dimmwert-Telegramm
# nachgeschickt, das den Einschaltvorgang beim Dimmwert beendet.
# Ob es Nacht ist, oder nicht, kann mittels einer externen GA für jedes
# Licht einzeln definiert werden.
#
#############################################################################
#
# Änderungshistorie:
# 20120821 - mclb - Erstellung des Plugins
# 20121009 - mclb - Es kann nun auf beliebige Werte getriggert werden.
#                   Z.B. bei Szene Nr. 5 die Lichter nachdimmen.
#
#############################################################################
#
# Offene Punkte:
# - dzt. keine bekannt
#
#############################################################################
#
# Abhängigkeiten:
# - Time::Local
#
#############################################################################
#
# plugin_info-Werte
# - nachtEin: Hier wird für jedes Licht hinterlegt, ob für dieses Licht Tag oder Nacht ist
#
#############################################################################

# Konstanten
use constant TAG => 'T';
use constant NACHT => 'N';
# Konstanten für Aufrufart
use constant EVENT_RESTART => 'restart';
use constant EVENT_MODIFIED => 'modified';
use constant EVENT_BUS => 'bus';
use constant EVENT_SOCKET => 'socket';
use constant EVENT_CYCLE => 'cycle';
# Konstanten für die Trennung der dynamischen Freigabe-Werte
use constant SEPARATOR1 => ';';
use constant SEPARATOR2 => '->';

### Variablen Einlesen/Deklarieren

use Time::Local;
my ($sec, $min, $hour, $day, $mon, $year, $wday, $yday) = localtime();
my $now = sprintf ("%02d:%02d",$hour,$min);
my ($sh,$sm,$eh,$em);
my ($su, $eu, $time);
my $debug = 0;
my $gs_licht;
my @gt_lichter;
my $gv_freigabe_dyn;
my @gt_freigabe_dyn;
my $gv_index;
my ($gv_id, $gv_tagNacht);
my $gv_valueEin;
&readConf;

# Kein zyklischer Aufruf, wird nur aktiv bei entsprechendem Telegramm
$plugin_info{$plugname.'_cycle'} = 0;

# Plugin an Gruppenadresse "anmelden"
foreach my $gs_licht (@gt_lichter) {
 $plugin_subscribe{$gs_licht->{gaEin}}{$plugname} = 1;
 $plugin_subscribe{$gs_licht->{gaNacht}}{$plugname} = 1;
}

# Dynamische Werte aus plugin_info lesen.
@gt_freigabe_dyn = split(SEPARATOR1, $plugin_info{$plugname.'_gt_freigabe_dyn'});
foreach $gv_freigabe_dyn (@gt_freigabe_dyn) {
 ($gv_id, $gv_tagNacht) = split(SEPARATOR2, $gv_freigabe_dyn);
 
 # Wegen Update auf gt_lichter hier eine for-Schleife
 for ($gv_index=0; $gv_index<@gt_lichter; $gv_index++) {
  $gs_licht = $gt_lichter[$gv_index];
  if ($gs_licht->{id} eq $gv_id) {
   $gs_licht->{tagNacht} = $gv_tagNacht;
   $gt_lichter[$gv_index] = $gs_licht;
   last();
  }
 }
}

# Aus welchem Grund läuft das Plugin gerade
my $gv_event=undef;
if (!$plugin_initflag) {
 $gv_event = EVENT_RESTART;           # Restart des daemons / Reboot
} elsif ($plugin_info{$plugname.'_lastsaved'} > $plugin_info{$plugname.'_last'}) {
 $gv_event = EVENT_MODIFIED;          # Plugin modifiziert
} elsif (%msg) {
 $gv_event = EVENT_BUS;               # Bustraffic
} elsif ($fh) {
 $gv_event = EVENT_SOCKET;            # Netzwerktraffic
} else {
 $gv_event = EVENT_CYCLE;             # Zyklus
}

# Abarbeiten der Telegramme
if ($gv_event eq EVENT_BUS) {
 # Wegen Update auf gt_lichter hier eine for-Schleife
 for ($gv_index=0; $gv_index<@gt_lichter; $gv_index++) {
  $gs_licht = $gt_lichter[$gv_index];

  if ($debug == 1) { plugin_log($plugname, "1: ".$msg{'dst'}.", ".$gs_licht->{gaEin}.", ".$msg{'value'}); }
  
  if (exists $gs_licht->{valueEin}) {
   $gv_valueEin = $gs_licht->{valueEin};
  } else {
   $gv_valueEin = 1;
  }

  if ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $gs_licht->{gaEin} and $msg{'value'} == $gv_valueEin) {
   plugin_log($plugname, "2: ".$gs_licht->{tagNacht});
   # Abarbeiten der Telegramme auf gaEin
   if ($gs_licht->{tagNacht} eq NACHT) {
    knx_write($gs_licht->{gaDimm}, $gs_licht->{valueDimm}, $gs_licht->{dptDimm});
    if ($debug == 1) { plugin_log($plugname,"$gs_licht->{name} gedimmt auf $gs_licht->{valueDimm}% um $now Uhr ($gs_licht->{dptDimm})"); }
   }
  } elsif ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $gs_licht->{gaNacht}) {
   # Abarbeiten der Telegramme auf gaNacht
   if ($msg{'value'} == $gs_licht->{nachtEin}) {
    $gs_licht->{tagNacht} = NACHT;
   } elsif ($msg{'value'} == $gs_licht->{nachtAus}) {
    $gs_licht->{tagNacht} = TAG;
   }
  }

  $gt_lichter[$gv_index] = $gs_licht;
 }
}

# Dynamische Werte nach plugin_info schreiben
@gt_freigabe_dyn = ();
foreach $gs_licht (@gt_lichter) {
 unshift(@gt_freigabe_dyn, join(SEPARATOR2, $gs_licht->{id}, $gs_licht->{tagNacht}));
}
$gv_freigabe_dyn = join(SEPARATOR1, @gt_freigabe_dyn);
$plugin_info{$plugname.'_gt_freigabe_dyn'} = $gv_freigabe_dyn;

return;

### READ CONF ###
sub readConf {
 my $confFile = '/etc/wiregate/plugin/generic/conf.d/'.basename($plugname,'.pl').'.conf';
 if (! -f $confFile) {
  plugin_log($plugname, "no conf file [$confFile] found."); 
 } else {
  #plugin_log($plugname, "reading conf file [$confFile]."); 
  open(CONF, $confFile);
  my @lines = <CONF>;
  close($confFile);
  my $result = eval("@lines");
  #($result) and plugin_log($plugname, "conf file [$confFile] returned result[$result]");
  if ($@) {
   plugin_log($plugname, "ERR: conf file [$confFile] returned:");
   my @parts = split(/\n/, $@);
   plugin_log($plugname, "--> $_") foreach (@parts);
  }
 }
}