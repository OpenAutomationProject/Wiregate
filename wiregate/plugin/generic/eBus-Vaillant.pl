# Beta fŸr eBus-Anbindung von Heizungen/Waermepumpen
# Diese Beta bezieht sich auf eine Vaillant VWS 82-3 Waermepumpe
# FŸr jeden Befehl wurde vorher eine sub erstellt die die Daten an die richtige Stelle setzt und
# richtig codiert. Dies laesst sich bestimmt noch schlanker gestalten in dem man die Konfigurationszeilen erweitert.
# Der generelle Aufbau eines eBus-Telegramms: QQ ZZ PB SB NN DB1...DBx CRC
# QQ = Quelladresse, ZZ = Zieladresse, PB = Primaerbefehl, SB = Sekundarbefehl, NN = Anzahl der Datenbytes, DB1...DBx = Datenbytes, CRC = Checksummenbyte.
# Teils liegen die Daten die es zu senden gibt an unterschiedlichen Stellen, in der Konfiguration sind diese dann leer (z.B. DB2="").
#
# Wiregte-Socket-Einstellungen:
# Socket 1: "-" und "Socket: /dev/ttyUSB0" (hier eigenen Adapter) und "Optionen: raw,b2400,echo=0"
# Socket 1: "udp-datagram" und "Socket: localhost:50110  und "Optionen: bind=localhost:50111,reuseaddr"
# aktiviert und bidirektional
#
# Das Perl-Modul EBus.pm muss installiert sein, vergleiche hierzu:
# http://knx-user-forum.de/253728-post64.html
#
# 06.10.2012
# JuMi2006 (http://knx-user-forum.de)
# Version 0.1

use warnings;
use strict;
use EBus;

my $socknum = 303; # Eindeutige Nummer des Sockets +1
my $send_ip = "localhost"; # Sendeport (UDP, siehe in Socket-Einstellungen)
my $send_port = "50111"; # Sendeport (UDP, siehe in Socket-Einstellungen)
my $recv_ip = "localhost"; # Empfangsport (UDP, siehe in Socket-Einstellungen)
my $recv_port = "50110"; # Empfangsport (UDP, siehe in Socket-Einstellungen)

### Vaillant Konfiguration ###
my @sets;
push @sets, { name => "RT_soll", 	GA => "0/0/0", 		QQ => "00", ZZ => "50", PB => "B5", SB => "05", NN => "02", DB1 => "01", DB2 => "" };
push @sets, { name => "RT_min", 	GA => "0/0/0", 		QQ => "00", ZZ => "50", PB => "B5", SB => "05", NN => "02", DB1 => "0A", DB2 => "" };
push @sets, { name => "HK_mode",	GA => "0/5/102", 	QQ => "00", ZZ => "50", PB => "B5", SB => "05", NN => "02", DB1 => "02", DB2 => "" };
push @sets, { name => "HK_curve", 	GA => "0/0/0", 		QQ => "00", ZZ => "50", PB => "B5", SB => "05", NN => "03", DB1 => "0B", DB2 => "", DB3 => "00" };
push @sets, { name => "HK_party", 	GA => "0/0/0", 		QQ => "00", ZZ => "50", PB => "B5", SB => "05", NN => "02", DB1 => "05", DB2 => "" };
push @sets, { name => "HK_spar", 	GA => "0/0/0", 		QQ => "00", ZZ => "50", PB => "B5", SB => "05", NN => "02", DB1 => "07", DB2 => "" };
push @sets, { name => "AT_off", 	GA => "0/0/0", 		QQ => "00", ZZ => "50", PB => "B5", SB => "09", NN => "04", DB1 => "0E", DB2 => "36", DB3 => "00", DB4 => "", DB5 => "00" };
push @sets, { name => "WW_load", 	GA => "0/5/101", 	QQ => "10", ZZ => "FE", PB => "B5", SB => "05", NN => "02", DB1 => "06", DB2 => "" };
push @sets, { name => "WW_soll", 	GA => "0/0/0", 		QQ => "00", ZZ => "25", PB => "B5", SB => "09", NN => "05", DB1 => "0E", DB2 => "82", DB3 => "00", DB4 => "", DB5 => "" };
push @sets, { name => "WW_min", 	GA => "0/0/0", 		QQ => "00", ZZ => "25", PB => "B5", SB => "09", NN => "05", DB1 => "0E", DB2 => "82", DB3 => "00", DB4 => "", DB5 => "" };
push @sets, { name => "WW_mode", 	GA => "0/0/0", 		QQ => "00", ZZ => "25", PB => "B5", SB => "09", NN => "04", DB1 => "0E", DB2 => "2B", DB3 => "00", DB4 => ""};
push @sets, { name => "HOL_date", 	GA => "0/0/0", 		QQ => "00", ZZ => "FE", PB => "B5", SB => "0B", NN => "08", DB1 => "01", DB2 => "Nr", DB3 => "ST", DB4 => "SM", DB5 => "SJ", DB6 => "ET", DB7 => "EM", DB8 => "EJ"};###FIXME DATATYP
push @sets, { name => "HOL_temp", 	GA => "0/0/0", 		QQ => "00", ZZ => "FE", PB => "B5", SB => "05", NN => "02", DB1 => "2A", DB2 => ""};
push @sets, { name => "HK_int", 	GA => "0/0/0", 		QQ => "10", ZZ => "08", PB => "B5", SB => "05", NN => "05", DB1 => "0E", DB2 => "7C", DB3 => "00", DB4 => "", DB5 => "FF" };
### Ende Vaillant Konfiguration ###


###############
### M A I N ###
###############

### Socket einrichten ###
$plugin_info{$plugname.'_cycle'} = 300;
if (!$socket[$socknum]) { # socket erstellen
        $socket[$socknum] = IO::Socket::INET->new(LocalPort => $recv_port,
                                  Proto => "udp",
                                  LocalAddr => $recv_ip,
                                  PeerPort  => $send_port,
                                  PeerAddr  => $send_ip,
                                  ReuseAddr => 1
                                   )
    or return ("open of $recv_ip : $recv_port failed: $!");

    $socksel->add($socket[$socknum]); # add socket to select

    $plugin_socket_subscribe{$socket[$socknum]} = $plugname; # subscribe plugin
    plugin_log($plugname,'Soket verbunden. Soketnummer: ' . $socknum);
    return "opened Socket $socknum";   
}
###

### Konfiguration einlesen ###
foreach my $set (@sets) {
$plugin_subscribe{$set->{GA}}{$plugname} = 1;   # An Gruppenadresse anmelden

if ($msg{'dst'} eq $set->{GA})                  # Auf eintreffendes KNX-Telegramm reagiern + anhand der GA filtern

{	
plugin_log($plugname, "Befehlsgruppe: $set->{name}");   # Logging der Befehlsgruppe
my $val = $msg{'value'};                                # Wert aus Telegramm filtern
my $subname = $set->{name};                             # $subname bekommt den Namen der entsprecheden sub
my $subref = \&$subname;                                # jetzt wird $subref die entsprechende sub zugewiesen
my $command = addCRC(&$subref($val));                   # Befehls-Sub ausfŸhren und CRC anhŠngen

&send ($command);   # Befehl senden
}
}

###################
### S E N D E N ###
###################

sub send
{
    my $cmd = shift;
    my $raw = $cmd;
    $raw =~ s/([0-9a-f]{2})/chr( hex( $1 ) )/gie;      # !!! Umwandlung des Hex-Strings
    plugin_log($plugname, "send: $cmd");
    syswrite($socket[$socknum], $raw); 
}


################################
### V A I L L A N T  S U B S ###
################################
#lassen sich bestimmt noch optimieren in dem man die Konfiguration etwas erweitert

### Sparen bis ...  30min = 0,5 Stunden (21:30Uhr = 21,5) ###
sub HK_spar
{
foreach my $set(@sets){
if ($set->{name} eq "HK_spar")
{
my $input = $_[0];
my $val = (sprintf "%02d",$input); 				
$val = encode_d1c ($val);
my $message = $set->{QQ}.$set->{ZZ}.$set->{PB}.$set->{SB}.$set->{NN}.$set->{DB1}.$val;
return $message;
}
}
}
###

### Ferientemperatur ###
sub HOL_temp
{
foreach my $set(@sets){
if ($set->{name} eq "HOL_temp")
{
my $input = $_[0];
my $val = (sprintf "%02d",$input); 				
$val = encode_d1b ($val);
my $message = $set->{QQ}.$set->{ZZ}.$set->{PB}.$set->{SB}.$set->{NN}.$set->{DB1}.$val;
return $message;
}
}
}
###


### Raumtemperatur Soll ###
sub RT_soll
{
foreach my $set(@sets){
if ($set->{name} eq "RT_soll")
{
my $input = $_[0];
my $val = (sprintf "%02d",$input); 				
$val = encode_d1b ($val);
my $message = $set->{QQ}.$set->{ZZ}.$set->{PB}.$set->{SB}.$set->{NN}.$set->{DB1}.$val;
return $message;
}
}
}
###

### Raumtemperatur Absenkung ###
sub RT_min
{
foreach my $set(@sets){
if ($set->{name} eq "RT_min")
{
my $input = $_[0];
my $val = (sprintf "%02d",$input); 				
$val = encode_d1b ($val);
my $message = $set->{QQ}.$set->{ZZ}.$set->{PB}.$set->{SB}.$set->{NN}.$set->{DB1}.$val;
return $message;
}
}
}
###

### 1-Heizen, 2-Aus, 3-Auto, 4-Eco, 5-Absenken ###
sub HK_mode
{
foreach my $set(@sets){
if ($set->{name} eq "HK_mode")
{
my $input = $_[0];
my $val = (sprintf "%02d",int($input)); 
my $message = $set->{QQ}.$set->{ZZ}.$set->{PB}.$set->{SB}.$set->{NN}.$set->{DB1}.$val;
return $message;
}
}
}
###

### Heizkurve 0,20 etc ###
sub HK_curve
{
foreach my $set(@sets){
if ($set->{name} eq "HK_curve")
{
my $input = $_[0];
$input *= 100;
my $val = (sprintf "%02d",$input); 
$val = encode_d1b($val);
my $message = $set->{QQ}.$set->{ZZ}.$set->{PB}.$set->{SB}.$set->{NN}.$set->{DB1}.$val.$set->{DB3};
return $message;
}
}
}
###

### 0-Partymodus aus, 1-Partymodus an ###
sub HK_party
{
foreach my $set(@sets){
if ($set->{name} eq "HK_party")
{
my $input = $_[0];
my $val = (sprintf "%02d",$input);
my $message = $set->{QQ}.$set->{ZZ}.$set->{PB}.$set->{SB}.$set->{NN}.$set->{DB1}.$val;
return $message;
}
}
}
###

### Betriebsmodus WW 1-aus, 2-an, 3-auto ###
sub WW_mode
{
foreach my $set(@sets){
if ($set->{name} eq "WW_mode")
{
my $input = $_[0];
my $val = (sprintf "%02d",$input);
my $message = $set->{QQ}.$set->{ZZ}.$set->{PB}.$set->{SB}.$set->{NN}.$set->{DB1}.$set->{DB2}.$set->{DB3}.$val;
return $message;
}
}
}
###

### 0-Speicherladung abbrechen, 1-Speicherladung ###
sub WW_load
{
foreach my $set(@sets){
if ($set->{name} eq "WW_load")
{
my $input = $_[0];
my $val = (sprintf "%02d",$input);
my $message = $set->{QQ}.$set->{ZZ}.$set->{PB}.$set->{SB}.$set->{NN}.$set->{DB1}.$val;
return $message;
}
}
}
###


### Energieintegral setzen ###
sub HK_int
{
foreach my $set(@sets){
if ($set->{name} eq "HK_int")
{
my $input = $_[0];
my $val = (sprintf "%02d",$input);
$val = encode_d1b($val);
my $message = $set->{QQ}.$set->{ZZ}.$set->{PB}.$set->{SB}.$set->{NN}.$set->{DB1}.$set->{DB2}.$set->{DB3}.$val.$set->{DB3};
return $message;
}
}
}
###

### Au§entemperatur Abschaltgrenze ###
sub AT_off
{
foreach my $set(@sets){
if ($set->{name} eq "AT_off")
{
my $input = $_[0];
my $val = (sprintf "%02d",$input);
$val = encode_d1b($val);
my $message = $set->{QQ}.$set->{ZZ}.$set->{PB}.$set->{SB}.$set->{NN}.$set->{DB1}.$set->{DB2}.$set->{DB3}.$val.$set->{DB3};
return $message;
}
}
}
###

### Solltemperatur WW-Speicher ### 
sub WW_soll
{
foreach my $set(@sets){
if ($set->{name} eq "WW_soll")
{
my $input = $_[0];
my $val = (sprintf "%02d",$input);
$val = encode_d2c($val);
my $message = $set->{QQ}.$set->{ZZ}.$set->{PB}.$set->{SB}.$set->{NN}.$set->{DB1}.$set->{DB2}.$set->{DB3}.$val;
return $message;
}
}
}
###

### Min.-Temperatur WW-Speicher ### 
sub WW_min
{
foreach my $set(@sets){
if ($set->{name} eq "WW_min")
{
my $input = $_[0];
my $val = (sprintf "%02d",$input); 	
$val = encode_d2c($val);
my $message = $set->{QQ}.$set->{ZZ}.$set->{PB}.$set->{SB}.$set->{NN}.$set->{DB1}.$set->{DB2}.$set->{DB3}.$val;
return $message;
}
}
}
###

############################################
### D A T E N K O N V E R T I E R U N G ####
############################################


### BCD ### ### FIX ME !!!!!
sub decode_bcd {
    #return (unpack "H*", pack "C*",hex($_[0]));
	unpack "H*", $_[0]; ####?????
}

sub encode_bcd {
	return pack 'H*', join '', $_[0];
}

### DATA1b ###

sub decode_d1b{         #1byte signed 
    my $val = hex(shift);
    return $val > 127 ? $val-256 : $val;
}

sub encode_d1b {        #### F I X M E !!!!!
    my $y = shift;
    $y *= 256;
    $y = $y & 0xffff if ($y < 0);
    my $hb = int $y/256;
    return (sprintf("%0.2X", $hb));
}


### DATA1c

sub decode_d1c {
my $y = hex ($_[0])/2;
return $y;
}

sub encode_d1c {
    return sprintf "%x",(($_[0])*2);
}


### DATA2b ###

sub decode_d2b { 
	return unpack("s", pack("s", hex($_[0].$_[1]))) / 256; 
}

sub encode_d2b {
	my ($hb, $lb) = unpack("H[2]H[2]", pack("s", $_[0] * 256));
	return $lb.$hb;
}

### alternativ
#sub decodex_d2b{
#    my $hb = hex($_[0]);
#    my $lb = hex($_[1]);
#
#   if ($hb & 0x80) {
#      return -( (~$hb & 255) + ((~$lb & 255) + 1)/256 );
#    }
#   else {
#        return $hb + $lb/256;
#    }
#}
#
#sub encodex_d2b {
#    my $y = shift;
#    $y *= 256;
#    $y = $y & 0xffff if ($y < 0);
#    my $hb = int $y/256;
#    my $lb = $y % 256;
#    return (sprintf("%0.2X", $hb), sprintf("%0.2X", $lb));
#}


### DATA2c ###

sub decode_d2c{
my $high = $_[1];
my $low = $_[0];
return unpack("s",(pack("H4", $low.$high)))/16;
}

sub encode_d2c{
my $val = $_[0];
my $temp_hex = unpack("H4", pack("n", ($val)*16));
# change lowbyte/highbyte -> lowbyte first
return substr($temp_hex,2,4).substr($temp_hex,0,2);
}

####################
### A D D  C R C ###
####################

### CRC hinzufuegen
sub addCRC
{
my $string = $_[0];
my $temp_string = pack("H*","$string"); ### geht auch!
my $crc = new EBus();
my $check = $crc->calcCrcExpanded($temp_string);
my $crcfinal = uc(sprintf("%02x", $check));
my $finalStr = $string.$crcfinal;
}
###


###################################
### V O M  E - B U S  L E S E N ###
###################################

#if ($fh) { # Wenn eBus ein Telegramm sendet, wird ab hier der entsprechende Status ausgelesen.
#  my $buf;
#  recv($fh,$buf,255,0);
#  my $bufhex = $buf;
#  $bufhex =~ s/(.)/sprintf("%.2X",ord($1))/eg;
#  return "Received: $bufhex";
#}
###


return;