### Plugin Zutrittskontrolle Fa. ACTICON
# 2013-02-25 v2 ohne socat mit netcat
my $ip = "192.168.6.1";
my $port = "3300";

$plugin_info{$plugname.'_cycle'} = 60; # Aufruf/Abfragezyklus in sek.
my $watchdog_ga = "13/5/1"; # GA für Watchdog, wenn keine Abfrage läuft
my %users; # Hash für die User
# Hash mit der Zuordnung ID -> Gruppenadresse
$users{'1234123488'} = "13/5/10"; # EMA (scharf?)
$users{'1234123472'} = "12/0/1"; #Huber
# usw.

#######################
### ENDE DEFINITION ###
#######################

# Hauptverarbeitung

my @result = `echo "SWT#ANW_ZE" | nc -q 1 $ip $port`;
foreach my $buf (@result) { # incoming data
    my $len = length($buf);
    $buf =~ s/\x0+//g; # clean out null-bytes:
    $plugin_info{$plugname.'_setlen'} += $len;
    next if(!$buf); # crap received, skip null-byte packets
    $buf =~ s/\r|\n//g; # remove CR/LF
    if ($buf =~ /START-SEND/) {
        $plugin_info{$plugname.'_setlen'} = $len;
        $plugin_info{$plugname.'_startT'} = time(); # runtime-calc
        $plugin_info{$plugname.'_lastSuccess'} = time();
        knx_write($watchdog_ga, 1, 1);
    }
    if ($buf =~ /STOP-SEND/) {
        return "$buf took: " . int(time() - $plugin_info{$plugname.'_startT'} . " len: $plugin_info{$plugname.'_setlen'}");
    }
    my $bufhex = $buf;
    $bufhex =~ s/(.)/sprintf("0x%x ",ord($1))/eg;

    my @anwesend = split('\|',$buf);
    #plugin_log($plugname, "Nummer: $anwesend[3] GA: $users{$anwesend[3]}");
    knx_write($users{$anwesend[3]}, 1, 1);
}

return "dunno";

