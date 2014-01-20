################################ Plugin für die Zigbee Light Link Steuerung ########################
# Thomas Willi, Version 0.4
# Ermöglicht die Steuerung von Philips HUE Lampen, etc. über IP Telegramme an ZLL Bridge

# Die benötigten Gruppenadressen müssen im Wiregate eingetragen sein.

### Definitionen -----------------------------------------------------------------------

# Perl Module 
use utf8;
use HTTP::Request::Common;
use LWP;
use Time::HiRes qw( usleep );

# Basis Link zur ZLL Bridge
# Um den Zugriff auf die Bridge zu bekommen muss ein neuer Benutzer angelegt werden.
# Anleitung siehe z.B. http://developers.meethue.com/gettingstarted.html
my $Bridge = 'http://192.168.178.31:8080/api/newdeveloper/lights/';

# Gesamtanzahl aller HUE-Lampen 
my $anzahl=4;

#########################################################################################
# Gruppenadressen
# Um Lampen hinzuzufügen Block kopieren und anschließen nur Index ändern
my %adresse=(
# Dresden FLS-PP Nr. 1+++++++++++++++++++++++++++++++++++++++++++++++++++++
# Bridge light: 1
# Name						Gruppenadresse	Funktion
"1_Schalten"=>				"1/6/0",		#Ein/Aus
"1_Status_Schalten"=>		"1/6/1",		#Rückmeldung Ein/Aus
"1_Helligkeit"=>			"1/6/2", 		#Helligkeit
"1_Status_Helligkeit"=>		"1/6/3", 		#Rückmeldung Helligkeit
"1_Rot"=>					"1/6/4", 		#RGB: Rot
"1_Gruen"=>					"1/6/5", 		#RGB: Grün
"1_Blau"=>					"1/6/6", 		#RGB: Blau
"1_Status_Rot"=>			"1/6/7", 		#Rückmeldung RGB: Rot
"1_Status_Gruen"=>			"1/6/8", 		#Rückmeldung RGB: Grün
"1_Status_Blau"=>			"1/6/9", 		#Rückmeldung RGB: Blau

# Philips HUE Lampe Nr. 1+++++++++++++++++++++++++++++++++++++++++++++++++++
# Bridge light: 2
# Name						Gruppenadresse	Funktion
"2_Schalten"=>				"1/6/10",		#Ein/Aus
"2_Status_Schalten"=>		"1/6/11",		#Rückmeldung Ein/Aus
"2_Helligkeit"=>			"1/6/12", 		#Helligkeit
"2_Status_Helligkeit"=>		"1/6/13", 		#Rückmeldung Helligkeit
"2_Rot"=>					"1/6/14", 		#RGB: Rot
"2_Gruen"=>					"1/6/15", 		#RGB: Grün
"2_Blau"=>					"1/6/16", 		#RGB: Blau
"2_Status_Rot"=>			"1/6/17", 		#Rückmeldung RGB: Rot
"2_Status_Gruen"=>			"1/6/18", 		#Rückmeldung RGB: Grün
"2_Status_Blau"=>			"1/6/19", 		#Rückmeldung RGB: Blau

# Philips HUE Lampe Nr. 2+++++++++++++++++++++++++++++++++++++++++++++++++++
# Bridge light: 3
# Name						Gruppenadresse	Funktion
"3_Schalten"=>				"1/6/20",		#Ein/Aus
"3_Status_Schalten"=>		"1/6/21",		#Rückmeldung Ein/Aus
"3_Helligkeit"=>			"1/6/22", 		#Helligkeit
"3_Status_Helligkeit"=>		"1/6/23", 		#Rückmeldung Helligkeit
"3_Rot"=>					"1/6/24", 		#RGB: Rot
"3_Gruen"=>					"1/6/25", 		#RGB: Grün
"3_Blau"=>					"1/6/26", 		#RGB: Blau
"3_Status_Rot"=>			"1/6/27", 		#Rückmeldung RGB: Rot
"3_Status_Gruen"=>			"1/6/28", 		#Rückmeldung RGB: Grün
"3_Status_Blau"=>			"1/6/29", 		#Rückmeldung RGB: Blau

# Philips HUE Lampe Nr. 3+++++++++++++++++++++++++++++++++++++++++++++++++++
# Bridge light: 4
# Name						Gruppenadresse	Funktion
"4_Schalten"=>				"1/6/30",		#Ein/Aus
"4_Status_Schalten"=>		"1/6/31",		#Rückmeldung Ein/Aus
"4_Helligkeit"=>			"1/6/32", 		#Helligkeit
"4_Status_Helligkeit"=>		"1/6/33", 		#Rückmeldung Helligkeit
"4_Rot"=>					"1/6/34", 		#RGB: Rot
"4_Gruen"=>					"1/6/35", 		#RGB: Grün
"4_Blau"=>					"1/6/36", 		#RGB: Blau
"4_Status_Rot"=>			"1/6/37", 		#Rückmeldung RGB: Rot
"4_Status_Gruen"=>			"1/6/38", 		#Rückmeldung RGB: Grün
"4_Status_Blau"=>			"1/6/39"		#Rückmeldung RGB: Blau
);
#########################################################################################

#Variablen
my $Helligkeit;
my $Status_Helligkeit;
my $Rot;
my $Gruen;
my $Blau;
my $Status_Rot;
my $Status_Gruen;
my $Status_Blau;
my $hue;			# Farbe als hsv Wert
my $bri;			# Helligkeit
my $sat;			# Sättigung
my $on_off;			# on/off
my $light=1; 		# Startwert Index für Gruppenadressen (1_xxx)

# Liste Standard Befehle an Bride+++++++++++++++++++++++++++++++++++++++++++++
my %befehl=(
# Name			Bridge-Kommando
"ein"=>			'{"on":true}',
"aus"=>			'{"on":false}',
);

### Ende Definitionen -------------------------------------------------------------------

# Eigenen Aufruf-Zyklus setzen
$plugin_info{$plugname.'_cycle'} = 60; #Aufruf alle 60 Sekunden

# Anmeldung Gruppenadressen
while (my($key,$ga) = each %adresse){
	#my $Name_GA=$adresse{$key};
	my $muster='Status';
	if ($key !~m/$muster/i){
		$plugin_subscribe{$adresse{$key}}{$plugname} = 1;
	} # Ende if
}

############################### HAUPTPROGRAMM ############################################
$anzahl=$anzahl+1;

while ($light<$anzahl){
	my $key_Schalten=$light.'_Schalten';
	my $key_Status_Schalten=$light.'_Status_Schalten';
	my $key_Helligkeit=$light.'_Helligkeit';
	my $key_Status_Helligkeit=$light.'_Status_Helligkeit';
	my $key_Rot=$light.'_Rot';
	my $key_Gruen=$light.'_Gruen';
	my $key_Blau=$light.'_Blau';
	my $key_Status_Rot=$light.'_Status_Rot';
	my $key_Status_Gruen=$light.'_Status_Gruen';
	my $key_Status_Blau=$light.'_Status_Blau';

# Ein/Aus
	if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $adresse{$key_Schalten}) {
		if ($msg{'value'} eq "0") {
		my $HTTP=Sende_Befehl($light, $befehl{'aus'});
		usleep(300);
		Sende_KNX_Status($light);
		}

		elsif ($msg{'value'} eq "1") {
		my $HTTP=Sende_Befehl($light, $befehl{'ein'});
		usleep(300);
		Sende_KNX_Status($light);	
		}
		return 0;
	} # Ende Ein/Aus
	
# Dimmen
	if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $adresse{$key_Helligkeit}) {
		$Helligkeit=decode_dpt5($msg{'data'});
		if($Helligkeit==0){
			my $HTTP=Sende_Befehl($light, $befehl{'aus'});
			usleep(300);
			Sende_KNX_Status($light);
			} else {
			$bri=int($Helligkeit/100*255);
			my $command='{"on":true,"bri":'.$bri.',"hue":14964,"sat":144}';
			my $HTTP=Sende_Befehl($light, $command);
			usleep(300);
			Sende_KNX_Status($light);
			return 0;
			}
		return 0;
	} # Ende Dimmen

# RGB Wert senden
	if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $adresse{$key_Rot}) {
		$Rot=decode_dpt5($msg{'data'});
		usleep(300);
		$Gruen=knx_read($adresse{$key_Gruen},100,5);
		usleep(300);
		$Blau=knx_read($adresse{$key_Blau},100,5);
		usleep(300);
		if(($Rot==0&&$Gruen==0&&$Blau==0)){
			my $HTTP=Sende_Befehl($light, $befehl{'aus'});
			usleep(300);
			knx_write($adresse{$key_Status_Helligkeit},0,5);
			knx_write($adresse{$key_Status_Schalten},0,1);
			} else {
			($hue, $sat, $bri)=RGBtoHSV($Rot, $Gruen, $Blau);
			my $command='{"on":true,"bri":'.$bri.',"hue":'.$hue.',"sat":'.$sat.'}';
			my $HTTP=Sende_Befehl($light, $command);
			usleep(300);
			Sende_KNX_Status($light);
			return 0;
			}
		return 0;
	} # Ende RGB Wert senden
	
	# Status Update aller Lampen
	Sende_KNX_Status($light);
	# Ende Status Update
	
	$light=$light+1;
} # Ende while

$light=1;



############################### ENDE HAUPTPROGRAMM ########################################

# ------------------------------- Unterprogramme  -----------------------------------------

###################### RGBtoHSV #####################
sub RGBtoHSV {
  my ($r, $g, $b2) = @_; 
  my ($h, $s, $v, $delta, $min); 
  ($r, $g, $b2)= map{$_ *=  1/100 }($r, $g, $b2);	#Umrechung RGB Werte in 0-1
 
  $min = [sort {$a <=> $b} ($r, $g, $b2)] -> [0]; 	# Minimum
  $v   = [sort {$b <=> $a} ($r, $g, $b2)] -> [0]; 	# Maximum
  $delta = $v - $min; 					# Maximum - Minimum
 
  if (($v == 0 || $delta == 0)) { $s = 0; $h = 0; } 	# falls Min = 0 oder Max=Min, dann h=0, s=0
  else { 
    if    ($r == $v)  { $h =       60 * ($g  - $b2) / $delta; }	# Max=R 
    elsif ($g == $v)  { $h = 120 + 60 * ($b2 - $r) / $delta; } 	# Max=G
    else              { $h = 240 + 60 * ($r  - $g) / $delta; } 	# Max=B
    $h = $h + 360 if ($h < 0); 				# falls h<0° dann h=h+360°
  } 
  $s=$delta/$v;

  $h=int($h*65535/360);
  $s=int($s*255);
  $v=int($v*255);
  return ($h,$s,$v);
}
########## Ende HSVto RGB ########################

###################### HSVtoRGB ##################
sub HSVtoRGB { 
  my ($h, $s, $v) = @_; 
  my ($r, $g, $b); 
  my ($f, $i, $h_temp, $p, $q, $t); 
  
  $h=int($h/65535*360);	# Umrechnen 0-655355 in 0-360°	
  $s=$s/255;			# Umrechnen 0-255 in 0-1
  $v=$v/255;			# Umrechnen 0-255 in 0-1
  
 
  if ($s == 0) { 	# falls s=0, dann R=G=B=V
    $r = $g = $b = $v; 
  } else { 
    if ($h == 360) { $h_temp = 0; } else { $h_temp = $h; } # h=0° identisch h=360°
    $h_temp /= 60; 	# Berechne hi=H/60°
 
    $i = int($h_temp);
    $f = $h_temp - $i; 
    $p = $v * (1 - $s); 
    $q = $v * (1 - ($s * $f)); 
    $t = $v * (1 - ($s * (1 - $f))); 
 
    if ($i == 0) {$r = $v; $g = $t; $b = $p;} 
    if ($i == 1) {$r = $q; $g = $v; $b = $p;} 
    if ($i == 2) {$r = $p; $g = $v; $b = $t;} 
    if ($i == 3) {$r = $p; $g = $q; $b = $v;} 
    if ($i == 4) {$r = $t; $g = $p; $b = $v;} 
    if ($i > 4) {$r = $v; $g = $p; $b = $q;} 
  } 
  $r=int($r*100);
  $g=int($g*100);
  $b=int($b*100);
  return ($r,$g,$b); 
} 
############### Ende HSVtoRGB #####################

######### Sende KNX Status ########################
sub Sende_KNX_Status {
	my ($light)=@_;
	my $key_Status_Schalten=$light.'_Status_Schalten';
	my $key_Status_Helligkeit=$light.'_Status_Helligkeit';
	my $key_Status_Rot=$light.'_Status_Rot';
	my $key_Status_Gruen=$light.'_Status_Gruen';
	my $key_Status_Blau=$light.'_Status_Blau';
	($on_off,$hue,$sat,$bri)=Abfrage_Status($light);
	$Helligkeit=int($bri/255*100);
	knx_write($adresse{$key_Status_Schalten},$on_off,1);
	knx_write($adresse{$key_Status_Helligkeit},$Helligkeit,5);
	#($Status_Rot, $Status_Gruen, $Status_Blau)=HSVtoRGB($hue, $sat, $bri);
	#knx_write($adresse{$key_Status_Rot},$Status_Rot,5);
	#knx_write($adresse{$key_Status_Gruen},$Status_Rot,5);
	#knx_write($adresse{$key_Status_Blau},$Status_Rot,5);
	return 0;
}

###### Ende Sende KNX Status ######################


######### Abfrage Routine #########################
sub Abfrage_Status {

my($LNr)=@_;
my $Adresse=$Bridge.$LNr;
my $req=HTTP::Request->new( 'GET', $Adresse );
	my $lwp=LWP::UserAgent->new;
	my $response= $lwp->request( $req )->content;
	my ($response_hue, $response_sat, $response_bri);
	my ($response_string, $response_on_off);
	($response_hue)=$response=~m/"hue":(\d+)/g;
	($response_sat)=$response=~m/"sat":(\d+)/g;
	($response_bri)=$response=~m/"bri":(\d+)/g;
	($response_string)=$response=~m/"on":(\w+)/g;
	if ($response_string eq 'false'){
		$response_on_off=0;
		} 
		else {$response_on_off=1;};
	return ($response_on_off,$response_hue,$response_sat,$response_bri);
		
}
########## Ende Abfrage Routine ####################


########## Sende Routine #########################
sub Sende_Befehl {

my($LNr, $Bef)=@_;
my $Adresse=$Bridge.$LNr.'/state';
my $req=HTTP::Request->new( 'PUT', $Adresse );
	$req->header( 'Content-Type' => 'application/json' );
	$req->content( $Bef );
	my $lwp=LWP::UserAgent->new;
	$lwp->request( $req );
}
########## Ende Sende Routine #####################

# ----------------------------- Ende Unterprogramme  ---------------------------------------
