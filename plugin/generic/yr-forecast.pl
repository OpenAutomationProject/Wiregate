###############################################################################
# Plugin yr.no Wetter (long-term)
# - teilw. noch Testscript zum parsen !
# - benoetigt gnuplot!

# URL wie im Browser + forecast.xml (varsel.xml)
my $url = "http://www.yr.no/place/Germany/Bavaria/Ottobrunn~6556321/";
my $url_xml = "forecast.xml";
my $image_name = "/var/www/images/forecast.png";

# Todo: forecast_hour_by_hour.xml ?
# Moegliche Funktionen
my $rain_intervals = 4; # Anzahl der (je 6h) zusammengezaehlten Vorhersage-Intervalle fuer die erwartete Niederschlagsmenge 
my $rain_threshold = 4; # Schwellwert fuer Regen (intervals addiert) - Ziel: Bewaesserungs-steuerung mit (Kurzzeit!)-Vorhersage
my $wind_intervals = 4; # Anzahl der (je 6h) zusammengezaehlten Vorhersage-Intervalle fuer Windwarnungen *ohne* Unwetter (Gartenmöbel leicht sichern etc.)
my $wind_threshold = 5; # Schwellwert Windwarnung (meter/sek) - siehe FIXME: cv_config.xml

### Links ###
# http://om.yr.no/verdata/free-weather-data/
# http://api.met.no/weatherapi/documentation
# http://om.yr.no/forklaring/symbol/
# https://code.google.com/p/yrno/
# http://www.webdesign-bamberg.net/erstellen-einer-wetterkarte-yr-no/
# Altes Googlewetter-Plugin:
# http://openautomation.svn.sourceforge.net/viewvc/openautomation/wiregate/plugin/generic/Googleweather?revision=348&view=markup

#TODO: some defines
my $linetype1 = "lw 1 lc rgb '#FF6347'"; # Temp real
my $linetype2 = "lw 2 lc rgb 'red'"; # Temp longterm bezier
my $bg = "black";
###############################################################################
if (! -x '/usr/bin/gnuplot') { return "install gnuplot !"; }
use Date::Parse;
use LWP::Simple;
use XML::Simple;
#use Encode qw(encode decode);

my @period = qw(Nacht Vormittag Nachmittag Abend);
#my $xml = encode("utf8",get($url . $url_xml));
my $xml = get($url . $url_xml);
#TODO: save XML locally to be re-used (Rain,Wind,...)
return "Couldn't get $url" unless defined $xml;

my $yr = XMLin($xml);
#my $yr = XMLin('forecast.xml');

my $nextup = $yr->{meta}{nextupdate};
#my $link = $yr->{credit}{link}{url};
my $start_time;
my $end_time;
my $rain_counter=0;
my $rain_absvalue=0;

# now first unfreak the XML into something readable, CSV ;)
# anonymous tempfile
my $csvfh;
open($csvfh,">",'/tmp/forecast.txt');
print $csvfh "#forecast.xml $yr->{meta}{lastupdate} $yr->{meta}{nextupdate} \n";

# maybe skip/ignore first(current period) record?
# or make two graphs: detailed and long-term
foreach (@{$yr->{forecast}{tabular}{time}}) {
#    print "Von $_->{from}  bis  $_->{to} \n";
#    print " Periode $_->{period} = $period[$_->{period}] \n";
#    print " Symbol $_->{symbol}{number} $_->{symbol}{name} V: $_->{symbol}{var}\n";
#    print " Luftdruck $_->{pressure}{value} \n";
#    print " Wind $_->{windSpeed}{mps} : $_->{windSpeed}{name} \n";    
#    print " Regen $_->{precipitation}{minvalue} $_->{precipitation}{maxvalue} \n";
#    print " Regen $_->{precipitation}{value} \n";
#    print " Temperatur $_->{temperature}{value} \n";
    if (!$start_time) { $start_time = $_->{to}; } # omit first record and start with future-forecast
    $end_time = $_->{to};
    print $csvfh "$_->{from} $_->{temperature}{value} $_->{precipitation}{value} $_->{pressure}{value} $_->{windSpeed}{mps}\n";
    if ($rain_counter < $rain_intervals) {
        $rain_counter++;
        $rain_absvalue += $_->{precipitation}{value};
    }
#FIXME: print JSON for CV here!
}
close($csvfh);

# if ($rain_absvalue > $rain_treshold) {
## Bewaesserung sperren
# } else {
## Bewaesserung freigeben
# }

#print "Infos: Sonnenaufgang $yr->{sun}{rise} Sonnenuntergang: $yr->{sun}{set} \n";
#FIXME: send sunrise/sunset to GA?

# gnuplot ist MUTTER ALLER FREAKSHOWS!
# so print every single command line by line to be able to change this stuff later..
my $gnuplotcmds;
open($gnuplotcmds,'>','/tmp/gnuplotcmds');
#print $gnuplotcmds "set title 'Vorhersage'\n";
print $gnuplotcmds "set title '$yr->{credit}{link}{text}' tc rgb '#cccccc'\n"; # credits
print $gnuplotcmds "set xlabel 'WireGate - created " . getISODateStamp . " von $start_time bis $end_time' tc rgb '#cccccc'\n";
#print $gnuplotcmds "set ylabel 'Temperatur'\n";
print $gnuplotcmds "set format y \"%0.0f\\260C\"\n"; # GradCelsius
print $gnuplotcmds "set y2label 'Niederschlag mm'\n";
print $gnuplotcmds "set ytics nomirror\n";
print $gnuplotcmds "set y2tics nomirror\n";
# Colors
print $gnuplotcmds "set grid front lc rgb '#dddddd'\n"; # Mand command grid!
#print $gnuplotcmds "set border lc rgb 'white'\n"; # optional
#print $gnuplotcmds "set obj 1 rectangle behind from screen 0,0 to screen 1,1\n"; # optional
#print $gnuplotcmds "set obj 1 fillstyle solid 1.0 fillcolor rgbcolor 'black'\n"; # optional
#print $gnuplotcmds "set logscale y2\n";
print $gnuplotcmds "set y2range [0:5]\n";

# Datumsformat
print $gnuplotcmds "set locale 'de_DE.UTF-8'\n";
print $gnuplotcmds "set xdata time\n";
print $gnuplotcmds "set timefmt '%Y-%m-%dT%H:%M:%S'\n";
print $gnuplotcmds "set format x \"%a\\n%d.%m\"\n";
print $gnuplotcmds "set style fill solid 0.3 border 0\n";
#print $gnuplotcmds "set style fill transparent solid 0.3 border 0\n";
print $gnuplotcmds "set term png size 828, 302\n"; # size of yr.no 48h-diagram
print $gnuplotcmds "set out '$image_name'\n";
print $gnuplotcmds "set xrange ['$start_time':'$end_time']\n";
print $gnuplotcmds "plot '/tmp/forecast.txt' using 1:3 title '' with boxes lw -1 lc rgb 'blue' axes x1y2, ";
print $gnuplotcmds "        '' using 1:3 with lines lw 1 lc rgb 'blue' title '' smooth bezier axes x1y2, ";
print $gnuplotcmds "        '' using 1:2 with lines lw 1 lc rgb '#FF6347' title '' smooth csplines, "; 
print $gnuplotcmds "        '' using 1:2 with lines lw 2 lc rgb 'red' title '' smooth bezier ";
print $gnuplotcmds "\n\n";
close $gnuplotcmds;
my $ret = `gnuplot '/tmp/gnuplotcmds'`;

#icons: http://symbol.yr.no/grafikk/sym/b48/10.png

# set cycle to next update-time
$plugin_info{$plugname.'_cycle'} = int((str2time($nextup) -time())+60);
if ($plugin_info{$plugname.'_cycle'} < 60) {
    $plugin_info{$plugname.'_cycle'} = 60; # avoid running wild if theres no new data
}
# important: tune rrd to accept 6h-step!
#rrdtool tune /var/www/rrd/yr_precipation_12h.rrd --heartbeat value:28800
#rrdtool tune /var/www/rrd/yr_precipation_24h.rrd --heartbeat value:28800
update_rrd("yr_precipation_24h","",$rain_absvalue);

return "next update $nextup ($rain_absvalue)";
return "Gnuplot sagt: $ret (nichts ist gut), next update $nextup";

