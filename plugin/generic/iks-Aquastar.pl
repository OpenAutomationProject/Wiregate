# V1.0 2013-04-07
# simple Plugin fuer iks Aquastar
# socat: socat /dev/ttyS0,raw,b9600,cs8,icanon=1 udp-datagram:localhost:50108,reuseaddr

##################
### DEFINITION ###
##################

my $socknum = 1;                # Eindeutige Nummer des Sockets

my $interval = 120; # Sendeintervall KNX

my $recv_ip = "localhost"; # Empfangsport (UDP, wie in Socket-Einstellungen)
my $recv_port = "50108"; # Empfangsport (UDP, wie in Socket-Einstellungen)

my $temp_ga = "13/3/1";
my $ph_ga = "13/3/2";
my $redox_ga = "13/3/3";

# Eigenen Aufruf-Zyklus setzen (Initialisierung/zyklisches pruefen)
$plugin_info{$plugname.'_cycle'} = 300;

#######################
### ENDE DEFINITION ###
#######################

# Hauptverarbeitung
if (!$socket[$socknum]) { # socket erstellen
    $socket[$socknum] = IO::Socket::INET->new(LocalPort => $recv_port,
                              Proto => "udp",
                              LocalAddr => $recv_ip
                                  )
         or return ("open of $recv_ip : $recv_port failed: $!");
    $socksel->add($socket[$socknum]); # add socket to select
    $plugin_socket_subscribe{$socket[$socknum]} = $plugname; # subscribe plugin
    return "opened UDP-Socket $socknum";
} 
elsif ($fh) { # Read from UDP-Socket
    my $buf;
    recv($fh,$buf,255,0);
    next if(!$buf || length($buf) < 2);            # Bogus messages    
    $buf =~ s/\r|\n//g; # remove CR/LF
    my $bufhex = $buf;
    $bufhex =~ s/(.)/sprintf("%x ",ord($1))/eg;
    if($buf =~ /^E([0-9]+) (\(.*\))([\s-+]*?[0-9]*\.?[0-9]+).*/ ) {
        if ($1 == 2) {
            $plugin_info{$plugname.'_tempval'} = $3;
        } elsif ($1 == 3) {
            $plugin_info{$plugname.'_phval'} = $3;
        } elsif ($1 == 4) {
            $plugin_info{$plugname.'_redoxval'} = $3;
        }
        if (time() - $plugin_info{$plugname.'_sentlast'} > $interval) {
            # write to knx
            knx_write($temp_ga,$plugin_info{$plugname.'_tempval'},9);
            knx_write($ph_ga,$plugin_info{$plugname.'_phval'},9);
            knx_write($redox_ga,$plugin_info{$plugname.'_redoxval'},9);
            # Update _sentlast
            $plugin_info{$plugname.'_sentlast'} = time();
        }
        #return "Recv $buf == Input: $1 Type/State: $2 Val: $3";
    } else {
        #DEBUG: return "Recv $buf ($bufhex)";
    }
}
return;

# in debug we get:
#2013-04-07 14:57:03.024,iks-Aquastar,Recv E1 (Pe ) Wasser     (45 31 20 28 50 65 20 29 20 57 61 73 73 65 72 20 20 20 20 ),0s,
#2013-04-07 14:57:04.867,iks-Aquastar,Recv E2 (Te ) 26.5  �C == Input: 2 Type: (Te ) Val:  26.5,0s,
#2013-04-07 14:57:06.712,iks-Aquastar,Recv E3 (pH )07.87  pH == Input: 3 Type: (pH ) Val: 07.87,0s,
#2013-04-07 14:57:09.140,iks-Aquastar,Recv E4 (Rx ) +396  mV == Input: 4 Type: (Rx ) Val:  +396,0s,
#2013-04-07 14:57:10.874,iks-Aquastar,Recv E15:10    So, 07.04. (45 31 35 3a 31 30 20 20 20 20 53 6f 2c 20 30 37 2e 30 34 2e ),0s,

