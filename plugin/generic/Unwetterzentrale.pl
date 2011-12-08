# Plugin zum Auslesen der Unwettermeldungen
# Version 0.3 07.12.2011
# Copyright: JNK (http://knx-user-forum.de/members/jnk.html)
# In Anlehnung an HS/FS Logikbaustein 19909 by Michael Grosalski
# Hoehenerkennung angeregt von ctr (http://knx-user-forum.de/members/ctr.html)
# License: GPL (v2)

####################
###Einstellungen:###
####################

# !!!!!! config-file beachten !!!!!

my $unwetter_txt_GA; # sendet Textmeldung DPT 16
my $unwetter_max_stufe_GA; # sendet höchste Warnstufe als DPT 5.005
my $unwetter_max_typ_GA; # sendet höchsten Warntyp als DPT 5.005
my $unwetter_max_neu_GA; # sendet 1=neue Meldungen, 0=alte Meldungen, DPT 1

my $plz; #PLZ
my $baseurl = 'http://www.unwetterzentrale.de/uwz/getwarning_de.php?plz='; # Basis-URL
my $country = 'DE'; # Land
my $lang = 'de';  # deutsch
my $hoehe; # Hoehenbegrenzung

my $udp_addr; # udp Adresse fuer Textmeldung (z.B. an PROWL Plugin)

my $show_debug = 0;

######################
##ENDE Einstellungen##
######################

use LWP::Simple;
use Encode;

my %warnstufen = ( gelb => 1, orange => 2, rot => 3, violett => 4 );
my %warntyp = ( gewitter => 1, glatteisregen => 2, regen => 3, schnee => 4, sturm => 5, temperatur => 6, strassenglaette => 7);

my @warnstufen_txt = ( 'keine Meldung', 'Vorwarn.', '', 'stark. ', 'extr. ' );
my @warntyp_txt = ( '', 'Gewitter', 'Glatteis', 'Regen', 'Schnee', 'Sturm', 'Temperatur', 'Glaette' );

my $confFile = '/etc/wiregate/plugin/generic/conf.d/'.basename($plugname,'.pl');
if (! -f $confFile)
{
  plugin_log($plugname, " no conf file [$confFile] found."); 
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

$plugin_info{$plugname.'_cycle'} = 900;

# Abfrage

my $url = $baseurl.$plz.'&uwz=UWZ-'.$country.'&lang='.$lang;
my $content = get($url);

if ($content eq undef) 
{
  return 'HTTP failed.';
}

my @LINES = split (/\n/, decode('UTF-8', $content));

my $high_typ = 0;
my $high_stufe = 0;
my $all_str = '';
my $typ;
my $stufe;
my $process_next = 1;	# 1 = beachten, 0= nicht beachten, standard ist: beachten.

for (my $i=0;$i<@LINES;$i++)  
{
  if ($LINES[$i] =~ /\s*<span style="\s*color:.*?;">g.?ltig f.?r:<\/span> <b>(.*?)<\/b>/i) 
  {
    my $warnung_hoehe_text = $1;
    if ($warnung_hoehe_text =~ /\s*H.hen bis (\d+) m/i) 
    {
      if ($show_debug > 1)
      {
      	plugin_log($plugname, "naechste Meldung bis ".$1 );
      }
      $process_next = ($1 ge $hoehe);
    } 
    elsif ($warnung_hoehe_text =~ /\s*H.hen ab (\d+) m/i) 
    {
      if ($show_debug > 1)
      {
      	plugin_log($plugname, "naechste Meldung ab ".$1 );
      }
      $process_next = ($1 le $hoehe);
    } 
    elsif ($warnung_hoehe_text =~ /\s*H.hen von (\d+) bis (\d+) m/i)
    {
      if ($show_debug > 1)
      {
      	plugin_log($plugname, "naechste Meldung von ".$1." bis ".$2 );
      }    
      $process_next = (($1 le $hoehe) && ($2 ge $hoehe));
    } 
    else 
    {
      if ($show_debug > 1)
      {
      	plugin_log($plugname, "naechste Meldung Hoehe nicht erkannt/alle Hoehen" );
      }        
      $process_next = 1;
    }
    if ($show_debug > 1)
      {
      	plugin_log($plugname, "naechste Meldung prozessieren: ".$process_next );
      }        
  } 
  elsif (($process_next || ($hoehe eq undef)) && ($LINES[$i] =~ /<div style="float:left;display:block;width:117px;height:110px;padding-top:6px;"><img src="..\/images\/icons\/(.*?)-(.*?).gif" width="117" height="104"><\/div>/i)) 
  {
    $typ = $warntyp{$1};
    $stufe = $warnstufen{$2};
    my $str = $stufe.$typ;
    if ($stufe>$high_stufe) 
    {
      $high_stufe = $stufe;
      $high_typ = $typ;
    }
    $all_str .= $str;
  }
}

if ($unwetter_txt_GA) 
{
  knx_write($unwetter_txt_GA, $warnstufen_txt[$high_stufe].$warntyp_txt[$high_typ], 16);
}

if ($unwetter_max_stufe_GA) 
{
  knx_write($unwetter_max_stufe_GA, $high_stufe, 5.005);
}

if ($unwetter_max_typ_GA) 
{
  knx_write($unwetter_max_typ_GA, $high_typ, 5.005);
}

if ($plugin_info{$plugname.'_allstr'} == $all_str) 
{
  if ($unwetter_max_neu_GA) 
  {
    knx_write($unwetter_max_neu_GA, 0, 1);
  }
} 
else 
{
  if ($unwetter_max_neu_GA) 
  {
    knx_write($unwetter_max_neu_GA, 1, 1);
  }
  if ($udp_addr) 
  {
    my $sock = IO::Socket::INET->new(
      Proto    => 'udp',
      PeerAddr => $udp_addr,
    );
    my $meldung = $warnstufen_txt[$high_stufe].$warntyp_txt[$high_typ];
    $sock->send("0;Unwetterwarnung;Unwetterwarnung;$meldung\n");
  }
  $plugin_info{$plugname.'_allstr'} = $all_str;
}

return 0;