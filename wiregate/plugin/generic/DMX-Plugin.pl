# Plugin DMX-Gateway
# Version: 0.3 2011-05-28
# Benötigt DMX USB-Interface

##################
### DEFINITION ###
##################

my $socknum = 6;                # Eindeutige Nummer des Sockets +1

# Eigenen Aufruf-Zyklus setzen (Initialisierung/zyklisches prüfen)
$plugin_info{$plugname.'_cycle'} = 300;
# Gruppenadressen DMX - leer um Versand zu unterbinden
# 8Bit/1Byte Dimmwerte werden 1:1 auf DMX-Adressen übersetzt
my $knx_startGA = "11/1/0"; #DMX-Kanal 1, DMX-Kanal 256=1/1/255, DMX-Kanal 257..512=1/2/0..255
my $dmx_channels = 512;     # Anzahl der DMX-Kanäle
# oder for XXX in array

my $dmx_send_ip = "localhost"; # Sendeport (UDP, sie in Socket-Einstellungen)
my $dmx_send_port = "50012"; # Sendeport (UDP, sie in Socket-Einstellungen)
my $dmx_recv_ip = "localhost"; # Empfangsport (UDP, sie in Socket-Einstellungen)
my $dmx_recv_port = "50011"; # Empfangsport (UDP, sie in Socket-Einstellungen)

#######################
### ENDE DEFINITION ###
#######################

my @dimcurve = (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
                  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   1,   1,   1,   1,   1,
                  1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,
                  1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,
                  1,   1,   1,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,
                  2,   2,   2,   2,   2,   2,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
                  3,   3,   4,   4,   4,   4,   4,   4,   4,   4,   4,   4,   5,   5,   5,   5,
                  5,   5,   5,   6,   6,   6,   6,   6,   6,   7,   7,   7,   7,   7,   8,   8,
                  8,   8,   8,   9,   9,   9,   9,  10,  10,  10,  10,  11,  11,  11,  12,  12,
                 12,  13,  13,  13,  14,  14,  14,  15,  15,  16,  16,  17,  17,  18,  18,  19,
                 19,  20,  20,  21,  21,  22,  22,  23,  24,  24,  25,  26,  26,  27,  28,  29,
                 29,  30,  31,  32,  33,  34,  35,  36,  37,  38,  39,  40,  41,  42,  43,  44,
                 46,  47,  48,  50,  51,  52,  54,  55,  57,  58,  60,  62,  63,  65,  67,  69,
                 71,  73,  75,  77,  79,  81,  83,  86,  88,  90,  93,  95,  98, 101, 104, 106,
                109, 112, 115, 119, 122, 125, 129, 132, 136, 140, 144, 148, 152, 156, 160, 165,
                169, 174, 179, 184, 189, 194, 199, 205, 211, 216, 222, 228, 235, 241, 248, 255);

# Hauptverarbeitung
if (!$socket[$socknum]) { # socket erstellen
    if (defined $socket[$socknum]) { #debug
        if ($socket[$socknum]->opened) { $socket[$socknum]->close(); }
        undef $socket[$socknum];
    }  #debug      my $dgram = sprintf("C%03dL%03d\r\n",$dmxchan,hex($msg{'data'}));

    $socksel->remove($socket[$socknum]);
    $socket[$socknum] = IO::Socket::INET->new(LocalPort => $dmx_recv_port,
                              Proto => "udp",
                              LocalAddr => $dmx_recv_ip,
                              PeerPort  => $dmx_send_port,
                              PeerAddr  => $dmx_send_ip,
                              ReuseAddr => 1
                               )
	     or return ("open of $dmx_recv_ip : $dmx_recv_port failed: $!");
    $socksel->add($socket[$socknum]); # add socket to select
    $plugin_socket_subscribe{$socket[$socknum]} = $plugname; # subscribe plugin
    for (my $i=0; $i<$dmx_channels;$i++) {
    	$plugin_subscribe{$knx_startGA}{$plugname} = 1;
    	$knx_startGA = addr2str(str2addr($knx_startGA)+1,1);
    }
    return "opened UDP-Socket $socknum";
} 
if (%msg) { # telegramm vom KNX
	my $destN = str2addr($msg{'dst'});
	my $startN = str2addr($knx_startGA);
	my $dmxchan = $destN - $startN;
  if ($msg{'apci'} eq "A_GroupValue_Write" and $destN >= $startN and $destN <= $startN+$dmx_channels) {
    	# send $dmxchan -> UDP as CaaaLvvv
        my $dgram = sprintf("C%03dL%03d\r\n",$dmxchan,$dimcurve[hex($msg{'data'})]);
    	$socket[$socknum]->send($dgram) or return "send failed: $!";
      # debug chop($dgram);chop($dgram); # debug
      # debug return "sent $msg{'dst'} $msg{'value'} $dgram to DMX $dmxchan"; # debug
      return;
 	}
} elsif ($fh) {
    my $buf;
    recv($fh,$buf,255,0);
    my $bufhex = $buf;
    $bufhex =~ s/(.)/sprintf("0x%x ",ord($1))/eg;
    #debug return "recv $buf $bufhex";
    return;
}

return;
