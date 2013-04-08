# return();
# schaltet anhand der Termine im Google-Kalender
# by NetFritz 03/2013
#

#
# muss ewtl angepasst werden
my $hole_gkalender = "./var/www/gCal/hole_gCal.php";
#
$plugin_info{$plugname.'_cycle'} = 20;
my $geschaltet = "";
#
# hole die Schaltzeiten aus der config
my $conf=$plugname; $conf=~s/\.pl$/.conf/;
$conf="/etc/wiregate/plugin/generic/conf.d/$conf";
open (CONFIG, "<$conf") || return "no config found";
     my @Schaltzeiten = <CONFIG>;
close CONFIG;
#
# in $iso steht Datum-Zeit = 'd.m.Y H:M'
my @dta = localtime(time);
my $iso=sprintf('%02d.',$dta[3]);
$iso.=sprintf('%02d.',$dta[4]+1);
$iso.=($dta[5]+1900)." ";
$iso.=sprintf('%02d:',$dta[2]);
$iso.=sprintf('%02d',$dta[1]);
#
my ($sek,$min,$std) = localtime(time);
      if ($min < 10 ){$min = "0".$min}
      if ($std < 10 ){$std = "0".$std}
#
# Schaltungen ausführen
foreach my $element (@Schaltzeiten) {
   # $element=~s/ //g; # Leerzeichen entfernen
   my ($schaltzeit,$name,$ga,$dpt,$wert) = split(/;/,$element); 
   $ga=~s/ //g; # Leerzeichen entfernen
   $dpt=~s/ //g;
   $wert=~s/ //g; 
   if(($plugin_info{$plugname.'_time'}+60) <= $plugin_info{$plugname.'_last'}){
      if($iso eq $schaltzeit){
        $geschaltet = "zeit=" . $schaltzeit . " name=" . $name . " ga=" . $ga . " dpt=" . $dpt . " wert=" .$wert;
        knx_write($ga,$wert,$dpt);
        $plugin_info{$plugname.'_time'} = time();
      }  
   }
}
#
# holt mit Hilfe des PHP-Scripts vom Google Kalender die Schaltzeiten
# und speichert sie in der plugin.conf ab
if(($plugin_info{$plugname.'_time'}+60) <= $plugin_info{$plugname.'_last'}){
   if($min == 00 or $min == 10 or $min == 20 or $min == 30 or $min == 40 or $min == 50){
      # Google-Kalender in config laden
      my $result = system($hole_gkalender);
     $plugin_info{$plugname.'_time'} = time();
   }
}
return($geschaltet);