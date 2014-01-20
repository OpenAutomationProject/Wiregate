# Philips Hue Leuchten via LAN-GW/Zigbee ansteuern
# Einfachste Variante - just Demo/testing
#
# 2013-04-24 V1.0

### Definitionen
# Eigenen Aufruf-Zyklus auf 300 Sekunden setzen
$plugin_info{$plugname.'_cycle'} = 86400; # egal..
my $ip = "172.17.3.170"; # Gateway-IP FIXME: detect
my $appname = "HuePL";
my $key = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"; # username/API-Key
my $aktiv_ga = "13/2/100";  # Gruppenadresse zum aktivieren
# Gruppenadresse zum aktivieren des Farbwechsel-Modus (Gruppe 0 / alle)
my $color_ga = "13/2/101";  
my $group_ga = "13/2/102";  
### Ende Definitionen


#FIXME: Hash, Array, switch o.a.

if ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $aktiv_ga) {
    #$plugin_info{$plugname.'_aktiv'} = int($msg{'data'});
    #knx_write($schalt_ga,int($msg{'data'}),1);
} elsif ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $color_ga) {
    my $value = int($msg{'data'}) ? "colorloop" : "none";
    my $dummy = `curl -s --request PUT --data '{"effect" : "$value"}' http://$ip/api/$key/groups/0/action`;
    # http://$ip/api/$key/lights/1/state
    return "color_ga: $value -> $dummy"; 
} elsif ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $group_ga) {
    my $value = int($msg{'data'}) ? "true" : "false";
    my $dummy = `curl -s --request PUT --data '{"on" : $value}' http://$ip/api/$key/groups/0/action`;
    return "group_ga: $value -> $dummy"; 
} else { # zyklischer Aufruf
    # Plugin an Gruppenadresse "anmelden"
    $plugin_subscribe{$aktiv_ga}{$plugname} = 1;
    $plugin_subscribe{$color_ga}{$plugname} = 1;
    $plugin_subscribe{$group_ga}{$plugname} = 1;
}

return;

