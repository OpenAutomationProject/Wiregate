### Plugin Zutrittskontrolle Fa. ACTICON

$plugin_info{$plugname.'_cycle'} = 60; # Aufruf/Abfragezyklus in sek.
my $watchdog_ga = "13/5/1"; # GA für Watchdog, wenn keine Abfrage läuft
my %users; # Hash für die User
# Hash mit der Zuordnung ID -> Gruppenadresse
$users{'1208123123'} = "13/5/10"; # EMA (scharf?)
$users{'1319123567'} = "12/0/1"; #Mustermann, Heinz
# sieht so aus: EMA,|          |c0c0c0|1208123123


# intern, nicht aendern: siehe socat:
# /usr/bin/socat tcp-connect:192.168.6.1:3300,forever,crlf udp-datagram:localhost:50105,bind=localhost:50106,reuseaddr
my $socknum = 38;
my $send_ip = "localhost";
my $send_port = "50106";
my $recv_ip = "localhost";
my $recv_port = "50105";

#######################
### ENDE DEFINITION ###
#######################

# Hauptverarbeitung
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
    syswrite($socket[$socknum],"SWT#ANW_ZE\r\n");
    return "opened Socket $socknum";    
} 

if ($fh) { # incoming data
    my $buf;
    recv($fh,$buf,255,0); # recv, not <$fh> as we receive mostly crap with NULL!
    $buf =~ s/\x0+//g; # clean out null-bytes:
    return if(!$buf); # crap received, skip null-byte packets
    if ($buf =~ /START-SEND/) {
        knx_write($watchdog_ga, 1, 1);
        return; # "Start";
    }
    return if ($buf =~ /STOP-SEND/);
    chomp($buf); # remove CR/LF
    my $bufhex = $buf;
    $bufhex =~ s/(.)/sprintf("0x%x ",ord($1))/eg;
    
    my @anwesend = split('\|',$buf);
    knx_write($users{$anwesend[3]}, 1, 1);

    return;
    #return "FH recv $buf ($bufhex)";
} else { # zyklischer Aufruf
    # Send command 
    syswrite($socket[$socknum],"SWT#ANW_ZE\r\n");
    # reset local $buf 
    return; #  "cycle";
}

return "dunno we never get here?";

