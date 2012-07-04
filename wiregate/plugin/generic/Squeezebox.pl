# Steuern der Squeezeboxen
# socat notwendig
# V0.2 2012-06-30
# Autor: kleinklausi / JuMi2006 (http://knx-user-forum.de)

### Im WG muss eine Socketverbindung mit folgenden Parametern erstellt werden
# Socket1: tcp-connect, Socket: IP_OF_SqueezeServer:9090
# Socket2: udp-datagram, Socket: localhost:50105, Optionen: bind=localhost:50106,reuseaddr

### Definitionen 

# 00%3A04%3A20%3A1f%3A92%3Ac4
# 00:04:20:1f:92:c4
my $player_id = "00%3A04%3A20%3A1f%3A92%3Ac4";   # Player ID = Mac Adresse Trennzeichen "%3A"

my %function = ("power"=>"8/1/0",
                "play"=>"8/1/1",
                "mute"=>"8/1/2",
                "vol_trigger"=>"8/1/3",
                "volume"=>"8/1/5",
                "pause"=>"8/1/4",
                "stop"=>"8/1/6",
                "favorites"=>"8/1/7",
                "show"=>"1/2/35");

my $socknum = 121; # Eindeutige Nummer des Sockets +1
my $send_ip = "localhost"; # Sendeport (UDP, siehe in Socket-Einstellungen)
my $send_port = "50106"; # Sendeport (UDP, siehe in Socket-Einstellungen)
my $recv_ip = "localhost"; # Empfangsport (UDP, siehe in Socket-Einstellungen)
my $recv_port = "50105"; # Empfangsport (UDP, siehe in Socket-Einstellungen)

### Ende Definitionen

# Eigenen Aufruf-Zyklus setzen
$plugin_info{$plugname.'_cycle'} = 86400;

# Plugin an Gruppenadresse "anmelden"
while (my($key,$ga) = each %function)
{
  $plugin_subscribe{$function{$key}}{$plugname} = 1;
}

# Beispiel für Hash-Zuordnung
# $key = power
# {$function{power} = "8/1/0"

# Socket erstellen
if (!$socket[$socknum]) {
        $socket[$socknum] = IO::Socket::INET->new(LocalPort => $recv_port,
                                  Proto => "udp",
                                  LocalAddr => $recv_ip,
                                  PeerPort  => $send_port,
                                  PeerAddr  => $send_ip,
                                  ReuseAddr => 1
                                   )
    or plugin_log($plugname, "open of $recv_ip : $recv_port failed: $!");
    $socksel->add($socket[$socknum]); # add socket to select
    $plugin_socket_subscribe{$socket[$socknum]} = $plugname; # subscribe plugin
    plugin_log($plugname, "opened Socket $socknum");
} 

# Nur bei einem Wert auf GA reagieren

# Power Befehl / 0=off 1=on
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{power} && defined $msg{'value'}) {
    my $command = $player_id . " power " . $msg{'value'};
    my $return_val = sendCommand($command);
 #   plugin_log($plugname, $return_val);
}

# Play (last) = Power on / Trigger mit beliebigem Wert
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{play} && defined $msg{'value'}) {
    my $command = $player_id . " play";
    my $return_val = sendCommand($command);
#    plugin_log($plugname, $return_val);
}

# Mute Befehl / Trigger mit beliebigem Wert
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{mute} && defined $msg{'value'}) {
    my $command = $player_id . " mixer muting " . $msg{'value'};
    my $return_val = sendCommand($command);
#    plugin_log($plugname, $return_val);
}

# Volume Down Befehl -10 Prozent / DPT 1 Trigger auf 0
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{vol_trigger} && $msg{'value'}==0) {
    my $command = $player_id . " mixer volume -10";
    my $return_val = sendCommand($command);
#    plugin_log($plugname, $return_val);
}

# Volume Down Befehl +10 Prozent / DPT 1 Trigger auf 1
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{vol_trigger} && $msg{'value'}==1) {
    my $command = $player_id . " mixer volume +10";
    my $return_val = sendCommand($command);
#    plugin_log($plugname, $return_val);
}

# Lautstärke setzen / DPT 5 in %
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{volume} && defined $msg{'value'}) {
    my $command = $player_id ." mixer volume " .$msg{'value'};
    my $return_val = sendCommand($command);
#    plugin_log($plugname, $return_val);
}

# Pause Befehl / Trigger mit beliebigem Wert
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{pause} && defined $msg{'value'}) {
    my $command = $player_id . " button pause";
    my $return_val = sendCommand($command);
#    plugin_log($plugname, $return_val);

}
# Stop Befehl über Button / Trigger mit beliebigem Wert
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{stop} && defined $msg{'value'}) {
    my $command = $player_id . " button stop";
    my $return_val = sendCommand($command);
#    plugin_log($plugname, $return_val);
}

# Favoriten wählen / DPT 6.020 als integer der Favoritennummer
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{favorites} && defined $msg{'value'}) {
    my $command = $player_id ." favorites playlist play item_id:" .$msg{'value'};
    my $return_val = sendCommand($command);
#    plugin_log($plugname, $return_val);
}

# Display / Trigger mit beliebigem Wert
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{show} && defined $msg{'value'}) {
    my $command = $player_id . " show line1:Mirko%20und line2:Juliane duration:30 centered:1";
    my $return_val = sendCommand($command);
#    plugin_log($plugname, $return_val);
}

#Special Notifications
#Aussentemperatur + Speicher anzeigen
my $temp_aussen = knx_read("7/0/0",0);
my $temp_speicher = knx_read("7/0/20",0);
my $temp_trigger = "1/2/100";
$plugin_subscribe{$temp_trigger}{$plugname} = 1;
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $temp_trigger && defined $msg{'value'}) {
    my $command = $player_id . " show line1:Aussentemperatur%20" . $temp_aussen . "%20°C line2:Speicher%20" . $temp_speicher . "%20°C duration:30 centered:1";
    my $return_val = sendCommand($command);
}

# Log
return 0;

sub sendCommand {

    my $request = $_[0]."\n";
    plugin_log($plugname, $_[0]);
    syswrite($socket[$socknum], $request);
}