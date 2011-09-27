# Plugin um eine mpd Instanz mit mehreren Outputs zu steuern, inkl. verschiedener Playlists
# und verschiedenen lautstärken der unterschiedlichen Ausgängen von Tastern oder sonstigen EIB Geraeten zu kontrollieren
# Version 0.3    25.11.2011
# Copyright: vlamers (http://knx-user-forum.de/members/vlamers.html)
# License: GPL (v2)
# Aufbau m&#65533;glichst so, dass man unterhalb der Einstellungen nichts ver&#65533;ndern muss!

#################################
##########Einstellungen##########
#################################
# Aktuelle Einstellungen arbeiten mit einer gesplitteten 7.1 USB Soundkarte
# Sehr viele Einstellungen, die aber nötig sind :-)
# Alsa Sound
my $vol_alsa = "100%";	# Volume for amixer (alsa volume)
my $Kanal = "Front";	# Channel of 7.1 soundcard
my $Kanal2 = "Rear";	# Channel of the second speaker pair
my $volkanal2 = "40%";	# The volume of the 2nd Speaker
my $cardnum = "1";		# Hardware Number of the Sound card
my $Speaker = "Speaker,1";	# Name of the output ( My soundcard is defined as following: Speaker,1 Front; Speaker,1 Rear
## mpd 
my $mpdname = "mpd2";		# the name of the mpd instance
my $IP = "192.168.178.33";    # The IP where the mpd Instanz is running
my $Port = "6601";        # Port of the mpd Instanz
my $volume_anfang = "35";     # This Volume will be set for mpd
# Aus wenn Fernseher an
my $Fernseher = '3/0/0';	# Fernseher
# Verstaerker
my $verstaerker = '13/1/2';	# Verstaerker on/off GA
#Radio GA
my $knx_addr_player2 = '13/1/0';# mpd Player on/off GA
#Volume
## Vol Receive
my $Vol_addr = '13/1/7'; # knx_address for volume up/down (receive)
my $volumestep = "3";    # The stepsize for volume
my $vol_up_data = "9";	# Data that ETS Busmonitor shows when you send a telegram from a switch to this GA
my $vol_down_data = "1";
#Vol send (brightness-value / helligkeitswert)
my $knx_addr_vol = '13/1/22'; # The Volume will be send here from the plugin
my $laut_GA = '13/1/23';    #the volume can be send here as brightness-value
# GA for recorded message
my $info_wz = '3/1/2';        # Info Switch wz
# Partymodus
my $Partymodus = '13/1/21';	# GA for Partymodus
my $vol_party = "100%"; 	# With % Symbol
# Quellen
my $kueche = '13/1/5';		# küche enable/disable	
my $kueche_nr = "1";		# mpd output number
my $wohnz = '13/1/8';		# Wohnzimmer enable/disable
my $wohnz_nr = "3";	# number of mpd output
my $Bad = '13/1/15';		# enable/disable bathroom output
my $Bad_nr = "2";		# mpd output number
# Prev / next
my $addr_pn= '13/1/14';	# Prev / Next
# Playlist
my $playlist = '13/1/24';	# the playlist number will be send here (value 1 - 255)
my $playlist1 = "Antenne";
my $playlist2 = "Christina";
my $playlist3 = "Volker";
my $playlist4 = "Kinderlieder";


##################################################
################Ende Einstellungen################
##################################################

#######################################################
# do not change anything below, all config stays above#
#######################################################

# subscribe plugins and call it only when necessary
$plugin_subscribe{$knx_addr_player2}{$plugname} = 1;
$plugin_subscribe{$Fernseher}{$plugname} = 1;
$plugin_subscribe{$Vol_addr}{$plugname} = 1;
$plugin_subscribe{$Partymodus}{$plugname} = 1;
$plugin_subscribe{$addr_pn}{$plugname} = 1;
$plugin_subscribe{$laut_GA}{$plugname} = 1;
$plugin_subscribe{$knx_addr_vol}{$plugname} = 1;
$plugin_subscribe{$wohnz}{$plugname} = 1;
$plugin_subscribe{$kueche}{$plugname} = 1;
$plugin_subscribe{$Bad}{$plugname} = 1;
$plugin_subscribe{$playlist}{$plugname} = 1;
$plugin_info{$plugname.'_cycle'} = 0;

# Radio on/off
if ($msg{'dst'} eq ($knx_addr_player2))
{ if ($msg{'apci'} eq 'A_GroupValue_Write') # change volume
{ if ($msg{'value'} == 01) {
	knx_write($verstaerker,1,1);
	knx_write($Bad,0,1);
	knx_write($wohnz,1,1);
	knx_write($kueche,1,1);
	my $debug = `/etc/init.d/$mpdname restart`;
        my $debug = `amixer -c $cardnum set $Speaker $Kanal $vol_alsa && amixer -c $cardnum set $Speaker $Kanal2 $volkanal2`;
        knx_write($playlist,1,1);
        knx_write($knx_addr_vol ,$volume_anfang,5);
        return "Player 2 läuft";
}
if ($msg{'value'} == 00) {
	knx_write($verstaerker,0,1);  # Verstaerker aus
    my $debug = `MPD_HOST=$IP MPD_PORT=$Port mpc stop`;
    return "Player 2 aus";}}}
# Aus wenn Fernseher an
if ($msg{'dst'} eq ($Fernseher) && ($msg{'apci'} eq 'A_GroupValue_Write') && ($msg{'value'} == 1))	{
	knx_write( $knx_addr_player2, 0,1 );
    return "Player 2 aus Fernseher";    }
#################### Volume step ################################
if ($msg{'dst'} eq ($Vol_addr))
{ if ($msg{'apci'} eq 'A_GroupValue_Write')  # change volume
{ if ($msg{'data'} == $vol_up_data) {
    my $debug = `MPD_PORT=$Port MPD_HOST=$IP mpc volume +$volumestep`;
    return; }

if ($msg{'data'} == $vol_down_data) {
    my $debug = `MPD_PORT=$Port MPD_HOST=$IP mpc volume -$volumestep`;
    return;}}}
###################### Vol receive ####################################
if ($msg{'dst'} eq ($laut_GA) && ($msg{'apci'} eq 'A_GroupValue_Write'))
{   my $vol1 = decode_dpt5($msg{'data'});
    my $vol = round($vol1);
    my $debug = `MPD_PORT=$Port MPD_IP=$IP mpc volume $vol`; 
    my $debug = `MPD_PORT=$Port MPD_IP=$IP mpc volume > /tmp/test.txt`;
    knx_write($knx_addr_vol,$vol,5);
    return $vol1;}
###################### Partymodus ##########################################
if ($msg{'dst'} eq ($Partymodus) && ($msg{'apci'} eq 'A_GroupValue_Write'))
{ if ($msg{'data'} == 01) {
	knx_write($kueche,00,1);
	knx_write($wohnz,1,1);
	 my $debug = `amixer -c $cardnum set $Speaker $Kanal2 $vol_party`;
    return "Party"; }

if ($msg{'value'} == 00) {
   my $debug = `amixer -c $cardnum set $Speaker $Kanal2 $volume_anfang%`;
   knx_write($kueche,01,1);
    return "Party ende"; }
else{
return;}}
######################### prev / next #####################################################
if ($msg{'dst'} eq ($addr_pn))
{ if ($msg{'apci'} eq 'A_GroupValue_Write') # change volume
{ if ($msg{'value'} == 1) {
    my $debug = `MPD_PORT=$Port MPD_HOST=$IP mpc next`;
    return "next"; }

if ($msg{'value'} == 0) {
    my $debug = `MPD_PORT=$Port MPD_HOST=$IP mpc prev`;
    return "prev";}}}
####################### Quellen ########################################
# wohnz
     if ($msg{'dst'} eq $wohnz && ($msg{'apci'} eq 'A_GroupValue_Write'))
     {  if (($msg{'value'} == 01)) {
        my $debug = `MPD_HOST=$IP MPD_PORT=$Port mpc enable $wohnz_nr`;
        return; }
        
        if (($msg{'value'} == 00)) {
        my $debug = `MPD_HOST=$IP MPD_PORT=$Port mpc disable $wohnz_nr`;
        return; }}
  
    # kueche
      if ($msg{'dst'} eq $kueche && ($msg{'apci'} eq 'A_GroupValue_Write'))
     {  if (($msg{'data'} == 01)) {
        my $debug = `MPD_HOST=$IP MPD_PORT=$Port mpc enable $kueche_nr`;
        return "OK"; }
        if (($msg{'data'} == 00)) {
        my $debug = `MPD_HOST=$IP MPD_PORT=$Port mpc disable $kueche_nr`;
        return "nOK";}else {return 0;}}
   
    # Bad
     if ($msg{'dst'} eq $Bad && ($msg{'apci'} eq 'A_GroupValue_Write'))
     {
        if (($msg{'value'} == 01)) {
        my $debug = `MPD_HOST=$IP MPD_PORT=$Port mpc enable $Bad_nr`;
        return; }
          if (($msg{'value'} == 00)) {
        my $debug = `MPD_HOST=$IP MPD_PORT=$Port mpc disable $Bad_nr`;
        return; }
          else {return;}}
###################### Playlist #########################################

if ($msg{'dst'} eq ($playlist) && ($msg{'apci'} eq 'A_GroupValue_Write'))
{	if ($msg{'data'} == 01){
	my $playlist = $playlist1;
	my $debug = `MPD_PORT=$Port MPD_IP=$IP mpc clear`; 
	my $debug = `MPD_PORT=$Port MPD_IP=$IP mpc load $playlist`;
	my $debug = `MPD_PORT=$Port MPD_IP=$IP mpc play`; 
	return "1";}
if ($msg{'data'} == 02){
	my $playlist = $playlist2;
	my $debug = `MPD_PORT=$Port MPD_IP=$IP mpc clear`; 
	my $debug = `MPD_PORT=$Port MPD_IP=$IP mpc load $playlist`;
	my $debug = `MPD_PORT=$Port MPD_IP=$IP mpc play`; 
	return "2";}
if ($msg{'data'} == 03){
	my $playlist = $playlist3;
	my $debug = `MPD_PORT=$Port MPD_IP=$IP mpc clear`; 
	my $debug = `MPD_PORT=$Port MPD_IP=$IP mpc load $playlist`;
	my $debug = `MPD_PORT=$Port MPD_IP=$IP mpc play`; 
	return "3";}
if ($msg{'data'} == 04){
	my $playlist = $playlist4;
	my $debug = `MPD_PORT=$Port MPD_IP=$IP mpc clear`; 
	my $debug = `MPD_PORT=$Port MPD_IP=$IP mpc load $playlist`;
	my $debug = `MPD_PORT=$Port MPD_IP=$IP mpc play`; 
	return "4";}
else {
my $pl = ($msg{'data'});
return $pl;
}}