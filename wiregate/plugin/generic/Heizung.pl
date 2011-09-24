# Plugin zum Erfassen des Gesamt-Fenster-Status
# Version 0.1 / 18.05.2011
# Copyright: JNK (http://knx-user-forum.de/members/jnk.html)
# License: GPL (v2)
#

####################
###Einstellungen:###
####################

my $schritt_ga = '4/1/3';  # Gruppenadresse Sollwert Auf = 1 / Ab = 0
my $sollwert_ga  = '4/2/3';   # Gruppenadresse Sollwert
my $sollwert = 15;
my $sollwertmin = 10; # Sollwert Minimum
my $sollwertmax = 25; # Sollwert Maximum


######################
##ENDE Einstellungen##
######################

# Eigenen Aufruf-Zyklus auf 1x stündlich setzen, hört ja auf GA
$plugin_info{$plugname.'_cycle'} = 3600;
$sollwert = $plugin_info{$plugname.'_sollwert'};

# Plugin an Gruppenadresse "anmelden"
$plugin_subscribe{$schritt_ga}{$plugname} = 1;
$plugin_subscribe{$sollwert_ga}{$plugname} = 1;

# 1=auf, 0=ab
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $schritt_ga && defined $msg{'value'} && $msg{'value'} == "0" ) {
   if($sollwert>$sollwertmin) { 
      $sollwert -= 0.5;
      knx_write($sollwert_ga,$sollwert,9);
      $plugin_info{$plugname.'_sollwert'} = $sollwert;
      return 1;
   }
}

if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $schritt_ga && defined $msg{'value'} && $msg{'value'} == "1" ) {
   if($sollwert<$sollwertmax) { 
      $sollwert += 0.5;
      knx_write($sollwert_ga,$sollwert,9);
      $plugin_info{$plugname.'_sollwert'} = $sollwert;
      return 1;
   }
}

#Sollwert vom Bus lesen, wenn von dort gesendet
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $sollwert_ga ) {
      $msg{'value'} = decode_dpt9($msg{'data'}); 
   $plugin_info{$plugname.'_sollwert'} = $msg{'value'};
   return 2;
}

knx_write($sollwert_ga,$sollwert,9);

return 0;
