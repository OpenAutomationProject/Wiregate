# Plugin um das RSS Log für die CometVisu aufzuräumen
#
# Copyright: Christian Mayer (mail at ChristianMayer.de)
# License: GPL (v3)
#
# V1.0 2017-04-09

# Lege maximales Alter der Einträge fest
my $maxAlter = 31 * 86400; # 31 Tage

# Eigenen Aufruf-Zyklus auf 86400 Sekunden = 24 Stunden setzen
$plugin_info{$plugname.'_cycle'} = 86400;

get( 'http://wiregate/cometvisu/plugins/rsslog/rsslog.php?r=' . int(time()-$maxAlter) );
