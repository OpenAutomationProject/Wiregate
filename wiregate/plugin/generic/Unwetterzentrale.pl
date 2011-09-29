# Plugin zum Auslesen der Unwettermeldungen
# Version 0.1 29.09.2011
# Copyright: JNK (http://knx-user-forum.de/members/jnk.html)
# In Anlehnung an HS/FS Logigbaustein 19909 by Michael Grosalski
# License: GPL (v2)
# Aufbau möglichst so, dass man unterhalb der Einstellungen nichts verändern muss!


####################
###Einstellungen:###
####################

my $unwetter_txt_GA = '0/1/1'; # sendet Textmeldung DPT 16
my $unwetter_max_stufe_GA  = '0/1/2'; # sendet höchste Warnstufe als DPT 5.005
my $unwetter_max_typ_GA = '0/1/3'; # sendet höchsten Warntyp als DPT 5.005
my $unwetter_max_neu_GA = '0/1/4'; # sendet 1=neue Meldungen, 0=alte Meldungen, DPT 1

my $plz = '45886'; #PLZ
my $baseurl = 'http://www.unwetterzentrale.de/uwz/getwarning_de.php?plz='; # Basis-URL
my $country = 'DE'; # Land
my $lang = 'de';  # deutsch


######################
##ENDE Einstellungen##
######################

use LWP::Simple;

my %warnstufen = ( gelb => 1, orange => 2, rot => 3, violett => 4 );
my %warntyp = ( gewitter => 1, glatteisregen => 2, regen => 3, schnee => 4, sturm => 5, temperatur => 6 );

my @warnstufen_txt = ( 'keine Meldung', 'Vorwarn.', '', 'stark. ', 'extr. ' );
my @warntyp_txt = ( '', 'Gewitter', 'Glatteis', 'Regen', 'Schnee', 'Sturm', 'Temperatur' );

$plugin_info{$plugname.'_cycle'} = 900;

# Abfrage

my $url = $baseurl.$plz.'&uwz=UWZ-'.$country.'&lang='.$lang;
my $content = get($url);

if ($content eq undef) {
  return 'HTTP failed.';
}

my @LINES = split (/\n/, $content);

my $high_typ = 0;
my $high_stufe = 0;
my $all_str = '';
my $typ;
my $stufe;

for (my $i=0;$i<@LINES;$i++)  {
  if ($LINES[$i] =~ /<div style="float:left;display:block;width:117px;height:110px;padding-top:6px;"><img src="..\/images\/icons\/(.*?)-(.*?).gif" width="117" height="104"><\/div>/i) {
    $typ = $warntyp{$1};
    $stufe = $warnstufen{$2};
    my $str = $stufe.$typ;
    if ($stufe>$high_stufe) {
      $high_stufe = $stufe;
      $high_typ = $typ;
    }
    $all_str .= $str;
  }
}



if ($unwetter_txt_GA) {
  knx_write($unwetter_txt_GA, $warnstufen_txt[$high_stufe].$warntyp_txt[$high_typ], 16);
}

if ($unwetter_max_stufe_GA) {
  knx_write($unwetter_max_stufe_GA, $high_stufe, 5.005);
}

if ($unwetter_max_typ_GA) {
  knx_write($unwetter_max_typ_GA, $high_typ, 5.005);
}

if ($plugin_info{$plugname.'_allstr'} == $all_str) {
  if ($unwetter_max_neu_GA) {
    knx_write($unwetter_max_neu_GA, 0, 1);
  }
} else {
  if ($unwetter_max_neu_GA) {
    knx_write($unwetter_max_neu_GA, 1, 1);
  }
  $plugin_info{$plugname.'_allstr'} = $all_str;
}

return $all_str;