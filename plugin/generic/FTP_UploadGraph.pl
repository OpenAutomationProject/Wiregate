### Plugin zum erstellen von Grafiken aus RRD's und FTP-Upload (SMTP-Versand, ...)
# v0.1
# 2012-01-04
# Kann aktuell nur einen Wert pro Grafik!
# Hinweise: Die Grafikerstellung ist sehr resourcenintensiv -
# stark abhängig von der Groesse der Grafik - und sollte nicht zu haeufig laufen!
# Dringend empfohlen: nicht mehr als 10 Werte pro Plugin!

###################
### DEFINITION           ###
###################

$plugin_info{$plugname . '_cycle'} = 3600; # Aufrufzyklus

# FTP Zugangsdaten
my $host = 'mein.ftpserver.de';
my $user = 'meinuser';
my $password = 'meinpasswort';
my $path = '/public_html/graph'; # Pfad auf dem FTP-Server

my $datasource = 'AVERAGE'; # MIN,AVERAGE,MAX

my %graphics; 
# hash fuer RRD / Grafik-Name
$graphics{'28.2C0E66010000_temp'} = 'WP_HGL-VL.png';
$graphics{'28.5F1966010000_temp'} = 'WP_VL.png';
$graphics{'28.480266010000_temp'} = 'WP_RL.png';

# kann bis auf diesen Teil direkt aus der graph-URL uebernommen werden: 
# DEF:ds0=28.2C0E66010000_temp.rrd:value:AVERAGE;
# (DEF:ds0.. bis ;)
# kann man anpassen
my $url1 = 'http://localhost/graph.pl?--start=-24h;--end=now;-X=0;-W=WireGate;--slope-mode;--lazy;-h=200;-w=650;--full-size-mode;--vertical-label=%B0%20Celsius;';
my $url2 = 'LINE1:ds0%23ff0000:Wert;VDEF:ds0_LAST=ds0,LAST;GPRINT:ds0_LAST:%2.2lf%B0C;;VDEF:ds0_MIN=ds0,MINIMUM;GPRINT:ds0_MIN:Min\:%20%8.2lf%B0C;VDEF:ds0_AVERAGE=ds0,AVERAGE;GPRINT:ds0_AVERAGE:Mittel\:%20%8.2lf%B0C;VDEF:ds0_MAX=ds0,MAXIMUM;GPRINT:ds0_MAX:Max\:%20%8.2lf%B0C\n;';

########################
### Ende DEFINITION  ###
########################


use Net::FTP;
my $rrd_ret;

my $ftp = Net::FTP->new($host, Debug => 0, Passive => 1, Timeout => 10)
  or return "Cannot connect to host $!";
$ftp->login($user,$password)
  or return "Cannot login " . $ftp->message . "$!";
$ftp->cwd($path)
  or return "Cannot change working directory: " . $ftp->message . "$!";
$ftp->binary;

# durch den Hash gehen und senden
while ( my ($rrd,$filename) = each(%graphics) ) {
    my $url = $url1 . "DEF:ds0=$rrd.rrd:value:$datasource;" . $url2;
    $rrd_ret .= `wget "$url" -O /tmp/$filename -o /tmp/wget.log`;
    $ftp->put("/tmp/$filename",$filename) 
      or return "Cannot send $filename: $!";

    # oder hier z.B. eMails verschicken oder...
} 

$ftp->quit;

#return; # ohne Logeintrag
return "FTP said " . $ftp->message;

