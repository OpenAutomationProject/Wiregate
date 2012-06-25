# Einfaches Plugin um per GA einen HTTP-GET abzusetzen
# etwas speziell (SMSCON auf N900)
# und smstools/smsd auf einem anderen Host! 
# Sonst wäre es einfacher..
#
# genutzt zum SMS-Versand, server-part: sendsms.php unter oa-svn/scripts
# Version: 0.1 - 2012-06-25

##################
### DEFINITION ###
##################

# Eigenen Aufruf-Zyklus auf 0=never setzen - nur zum subscriben nach restart 
$plugin_info{$plugname.'_cycle'} = 0;
my $wert_ga = "0/7/51";  # Gruppenadresse mit dem Wert
# Host+URL für das script
my $url = "http://IP.adresse.des.Servers/scripts/sendsms.php";
# Prefix (Passwort) für SMSCON - ggfs. einfach leer lassen 
my $prefix = "VerySecret6666Script";
# SMS-Text/Commmand, array je nach GA-Wert, keine gruetze-zeichen, 
# sonst braucht es noch einen encode oder so
my @text = qw(blueon blueoff); # 0=abwesend, BT an, 1=anwesend, BT aus
my $to = "017xxxxxxxx"; # Empfaenger-Rufnummer
# Todo: Flash, charset ISO/UNICODE
my $charset = "ISO";

#######################
### ENDE DEFINITION ###
#######################

# Nun kommt es darauf an, ob das Plugin aufgrund eines eintreffenden Telegramms
# oder zum init aufgerufen wird
# Bei eintreffenden Telegrammen reagieren wir gezielt auf "Write" (gibt ja auch Read/Response)
# und die spezifische Gruppenadresse, das Plugin könnte ja bei mehreren "angemeldet" sein.

if ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $wert_ga) {
  use LWP::Simple;
  my $resp = get($url."?charset=$charset&text=" . $prefix . ' ' . $text[int($msg{'data'})]."&to=$to" );
  #DEBUG: return "Sent !: ".$url."?charset=$charset&text=" . $prefix . " " . $text[int($msg{'data'})]."&to=$to" . " Got: $resp";
} else { # zyklischer/initialer Aufruf
  # Plugin an Gruppenadresse "anmelden"
  $plugin_subscribe{$wert_ga}{$plugname} = 1;
}

return;

