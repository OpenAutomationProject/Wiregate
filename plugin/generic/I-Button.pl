##########################################################
# Script zur Anwesenheits Steuerung per I-Buttons
# Version 0.3
#
# Allgemeine Hinweise:
# Begruessung per mpd Instanz
# die globale definition der I-Buttons (Farben) dient um das Plugin auf die GA anzumelden
# die merker definition dient dazu die telegram wiederholung alle 300s abzufangen und nicht jedesmal 
# begruesst zu werden.
# Die Audio Files zur Begruessung sind als "Besitzer" definiert. jeweils als "Besitzer".mp3 in der 
# Datenbank der mpd Instanz

## GA´s der mpd Instanz
my $schwarz= '13/2/1';
my $blau= '13/2/2';
my $gelb= '13/2/4';
my $rot = '13/2/3';
my $Anwesenheit = '13/2/0';
my $verstaerker = '13/1/2';

# mpd
my $IP = "192.168.178.33";
my $Port = "6602";
my $Lautstaerke = "70";

# subscribe plugin and call it only when necessary, script will be activated if telegrams to the deffined GA are send.
$plugin_subscribe{$schwarz}{$plugname} = 1;
$plugin_subscribe{$gelb}{$plugname} = 1;
$plugin_subscribe{$blau}{$plugname} = 1;
$plugin_subscribe{$rot}{$plugname} = 1;
$plugin_info{$plugname.'_cycle'} = 0;

# ein Array der Objecte mit definierten namen, und den dazugehörigen GA´s
# GA => GA des I-Buttons
# merker => merker GA des jeweiligen I-Buttons um die Telegram Wiederholung abzufangen
# besitzer => Name der mp3 (Begruessung) ohne Dateiendung
my @AlleButtons;
push @AlleButtons, {besitzer => "Elisa", name => "rot", GA => "13/2/3", merker => "13/2/7"};
push @AlleButtons, {besitzer => "Volker", name => "schwarz", GA => "13/2/1", merker => "13/2/10"};
push @AlleButtons, {besitzer => "Samuel", name => "blau", GA => "13/2/2", merker => "13/2/9"};
push @AlleButtons, {besitzer => "Christina", name => "gelb", GA => "13/2/4", merker => "13/2/8"};

#################################################################
# do not change anything below, all config stays above
#################################################################
 
 # Plugin für jedes oben definiertes Element ausführen
foreach my $element (@AlleButtons) {
#nur ausführen wenn das Ziel die definierte GA ist und das Telegram ein Write Telegram ist und kein Read oder Response Telegram. Der Status der Elemente wird unten im Plugin "gemerkt"
     if ($msg{'dst'} eq ($element->{GA}) && ($msg{'apci'} eq 'A_GroupValue_Write') )
     # && knx_read($msg{'dst'},0,1)  != $plugin_info{$plugname.'_' . ($element->{name}) })
     {
      ## Status der GA´s holen
     my $status = knx_read($Anwesenheit ,0,1);
     my $rot_stat = knx_read($rot,0,1);
     my $schwarz_stat = knx_read($schwarz,0,1);
     my $gelb_stat = knx_read($gelb,0,1);
     my $blau_stat = knx_read($blau,0,1);

     ## definierte if else anweisung die ausgeführt werden soll nach bestimmten zuständen
          if (($msg{'value'} == 1) && (knx_read($Anwesenheit ,0,1) == 0)) {
         knx_write($Anwesenheit ,1,1);
          plugin_log($plugname,"name: " . $status);
          }
         if (($msg{'value'} == 1) && (knx_read($element->{merker} ,0,1) == 0)) {
         knx_write($verstaerker, 1,1);
         knx_write($element->{merker}, 1,1);
         my $debug = `MPD_HOST=$IP MPD_PORT=$Port mpc clear && MPD_HOST=$IP MPD_PORT=$Port mpc add $element->{besitzer}.mp3 && MPD_HOST=$IP MPD_PORT=$Port mpc volume $Lautstaerke && MPD_HOST=$IP MPD_PORT=$Port mpc play`;
         }
         
         if (($msg{'value'} == 0) && (knx_read($element->{merker} ,0,1) == 1)) {
         knx_write($element->{merker}, 0,1);
         }
          
          elsif (($msg{'value'} == 0) && ($rot_stat == 0) && ($gelb_stat == 0) && ($schwarz_stat == 0) && ($blau_stat == 0)) {                 
           knx_write($Anwesenheit ,0,1);
           plugin_log($plugname,"name: " . $element->{name} . "; aus: ");
          }
          
    #merken der Zustände:
  #  $plugin_info{$plugname.'_' . ($element->{name}) } = knx_read($element->{GA} ,0,1);
    $plugin_info{$plugname.'_' . ($Anwesenheit) } = knx_read($Anwesenheit ,0,1);
  #  $plugin_info{$plugname.'_' . ($element->{merker}) } = knx_read($element->{merker} ,0,1);
    }
 # wenn keine der oben genannten bedingungen zutrifft dann das nächste Element abarbbeiten
   else {
          next;
     }
    
}