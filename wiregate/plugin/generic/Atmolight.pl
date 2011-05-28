# Plugin Atmolight
# Kommunikation via UDP - socat separat, muss an einen USB
# Version: 0.1 2011-02-03

# Eigenen Aufruf-Zyklus setzen (Initialisierung/zyklisches prüfen)
$plugin_info{$plugname.'_cycle'} = 600;
#return "broken";
#if ($socket[$socknum]->opened) { $socket[$socknum]->close(); }
#undef $socket[$socknum];

##################
### DEFINITION ###
##################

my $socknum = 121;                # Eindeutige Nummer des Sockets

my $send_ip = "172.17.2.68"; # Sendeport (UDP, sie in Socket-Einstellungen)
my $send_port = "50118"; # Sendeport (UDP, sie in Socket-Einstellungen)
my $recv_ip = "172.17.2.203"; # Empfangsport (UDP, sie in Socket-Einstellungen)
my $recv_port = "50117"; # Empfangsport (UDP, sie in Socket-Einstellungen)

my $basega = "10/0/110";
my $numgas = 15;
# Startadresse
# 0-2 alle(center?), 3-5 left 6-8 right, 9-11 = oben, 12-14 unten

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
                              ReuseAddr => 1,
                              Blocking => 0
                               )
             or return ("open of $recv_ip : $recv_port failed: $!");

    $socksel->add($socket[$socknum]); # add socket to select

    $plugin_socket_subscribe{$socket[$socknum]} = $plugname; # subscribe plugin
    for my $chan ("center","left","right","top","bottom") {
        $plugin_info{$plugname.'_R_'.$chan} = "00" unless $plugin_info{$plugname.'_R_'.$chan};
        $plugin_info{$plugname.'_G_'.$chan} = "00" unless $plugin_info{$plugname.'_G_'.$chan};
        $plugin_info{$plugname.'_B_'.$chan} = "00" unless $plugin_info{$plugname.'_B_'.$chan};
    }
    # fall through! return "opened Socket $socknum";
} 

if (%msg) { # telegramm vom KNX
  if ($msg{'apci'} eq "A_GroupValue_Write") {
     my $idx = str2addr($msg{'dst'}) - str2addr($basega);
     my @col = ("R","G","B");
     my @chan = ("center","left","right","top","bottom");
     my $ret;
     $plugin_info{$plugname.'_'.$col[$msg{'data'}%3].'_'.$chan[%3]} = $msg{'data'};
     if ($idx==0) {
            return "null";
      } else {
    for my $chan ("center","left","right","top","bottom") {
        $ret = $plugin_info{$plugname.'_R_'.$chan} = "00" unless $plugin_info{$plugname.'_R_'.$chan};
        $ret .= $plugin_info{$plugname.'_G_'.$chan} = "00" unless $plugin_info{$plugname.'_G_'.$chan};
        $ret .= $plugin_info{$plugname.'_B_'.$chan} = "00" unless $plugin_info{$plugname.'_B_'.$chan};
    }

          return "dunno? recv KNX $msg{'dst'} $msg{'data'} $ret";
      }
  }
  return "recv $msg{'dst'} ". hex($msg{'data'});
} elsif ($fh) { # incoming dgram
    my $buf; # not linewise! = <$fh>;
    $socket[$socknum]->recv($buf,1024);

    my $bufhex = unpack("H*",$buf);
    chomp $buf;
    my $fn = substr($buf,0,2);
    # this is still very dumb
    return "dunno recv $buf ($bufhex)";
}

for (my $i=0; $i<$numgas;$i++) {
    $plugin_subscribe{$basega}{$plugname} = 1;
    $basega = addr2str(str2addr($basega)+1,1);
}

# insert all commands to be sent cyclic
# syswrite($socket[$socknum],"PW?\r");

return "cycle";
