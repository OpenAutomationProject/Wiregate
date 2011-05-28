# Plugin Denon-AVR
# Kommunikation via UDP - socat separat einzurichten
# Version: 0.1 2011-01-31

##################
### DEFINITION ###
##################

my $socknum = 118;                # Eindeutige Nummer des Sockets +1

# Eigenen Aufruf-Zyklus setzen (Initialisierung/zyklisches pruefen)
$plugin_info{$plugname.'_cycle'} = 600;

my $send_ip = "localhost"; # Sendeport (UDP, sie in Socket-Einstellungen)
my $send_port = "50106"; # Sendeport (UDP, sie in Socket-Einstellungen)
my $recv_ip = "localhost"; # Empfangsport (UDP, sie in Socket-Einstellungen)
my $recv_port = "50105"; # Empfangsport (UDP, sie in Socket-Einstellungen)

my $denon_ip;
#$denon_ip = "172.17.2.89:23";  # uncomment to use direct telnet without socat

my $basega = "10/0/0";
my $numgas = 20;
# Startadresse
# 0=PW 1=PWStatus

#######################
### ENDE DEFINITION ###
#######################

# Hauptverarbeitung
if (!$socket[$socknum]) { # socket erstellen
    if ($denon_ip) {
        $socket[$socknum] = IO::Socket::INET->new(PeerAddr => $denon_ip, Timeout => 120, Blocking => 0)
             or return ("open of $denon_ip  failed: $!");
    } else {
        $socket[$socknum] = IO::Socket::INET->new(LocalPort => $recv_port,
                                  Proto => "udp",
                                  LocalAddr => $recv_ip,
                                  PeerPort  => $send_port,
                                  PeerAddr  => $send_ip,
                                  ReuseAddr => 1
                                   )
                 or return ("open of $recv_ip : $recv_port failed: $!");
    }

    $socksel->add($socket[$socknum]); # add socket to select

    $plugin_socket_subscribe{$socket[$socknum]} = $plugname; # subscribe plugin
    return "opened Socket $socknum";
} 

if (%msg) { # telegramm vom KNX
  if ($msg{'apci'} eq "A_GroupValue_Write") {
      my $idx = str2addr($msg{'dst'}) - str2addr($basega);
      if ($idx==0) {
          my @vals = qw/PWSTANDBY PWON/; #1bit on/off
          syswrite($socket[$socknum], $vals[$msg{'data'}]."\r");
      #1=PW?
      } elsif ($idx==2) { 
          my @vals = qw /MVDOWN MVUP/; #1bit master-vol
          syswrite($socket[$socknum], $vals[$msg{'data'}]."\r");
      } elsif ($idx==3) { # 1byte 0-99
          syswrite($socket[$socknum], sprintf("MV%02d\r",$msg{'data'}));
      #4=MV?
      } elsif ($idx==5) {
          my @vals = qw /MUOFF MUON/; #1bit mute
          syswrite($socket[$socknum], $vals[$msg{'data'}]."\r");
      #6=MU?
      } elsif ($idx==7) { #1byte source 5=TV 11=ipod 19=usb
          my @vals = qw /PHONO CD TUNER DVD BD TV SAT\/CBL DVR GAME V.AUX DOCK IPOD NET\/USB NAPSTER LASTFM FLICKR FAVORITES IRADIO SERVER USB\/IPOD/;
          syswrite($socket[$socknum], "SI".$vals[$msg{'data'}]."\r");
      #8=SI?
      } elsif ($idx==9) { #1byte sourround mode 2=ST 6=MCHST 10=Matrix
          my @vals = ("DIRECT","PURE DIRECT","STEREO","STANDARD","DOLBY DIGITAL","DTS SUROUND","MCH STEREO","ROCK ARENA","JAZZ CLUB","MONO MOVIE","MATRIX","VIDEO GAME","VIRTUAL");
          syswrite($socket[$socknum], "MS".$vals[$msg{'data'}]."\r");
      #10=MS?
      } else {
          return "dunno? recv KNX $msg{'dst'} $msg{'data'}";
      }
  }
  return;
} elsif ($fh) { # incoming dgram
    my $buf = <$fh>;
    my $bufhex = unpack("H*",$buf);
    chomp $buf;
    my $fn = substr($buf,0,2);
    # this is still very dumb
    if ($fn eq "PW") {
        my @vals = qw/PWSTANDBY PWON/; #1bit on/off
        my( $val )= grep { $vals[$_] eq $buf } 0..$#vals;
        knx_write(addr2str(str2addr($basega)+1) ,$val,1);
        return "$val - @vals - $buf";
    } elsif ($fn eq "MV" and $buf !~ /^MVMAX/) { # MVMAX is undocumented?
        # broken, just sends every 2, .5 isn't considered
        knx_write(addr2str(str2addr($basega)+4),substr($buf,2,2),5.010);
        return "recv $buf ($bufhex)";
    } else {
        return "dunno recv $buf ($bufhex)";
    }
    return;
}

for (my $i=0; $i<$numgas;$i++) {
    $plugin_subscribe{$basega}{$plugname} = 1;
    $basega = addr2str(str2addr($basega)+1,1);
}

# insert all commands to be sent cyclic
syswrite($socket[$socknum],"PW?\r");

return "cycle";
