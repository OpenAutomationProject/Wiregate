# Plugin um Meldungen an die Dreambox zu senden (mit LWP::UserAgent statt wget)
# für Enigma2-boxen (7025,8000,800,..)
# Version: 0.1 2011-06-19

##################
### DEFINITION ###
##################

my $socknum = 131;                # Eindeutige Nummer des UDP-Sockets

# Eigenen Aufruf-Zyklus setzen (Initialisierung/zyklisches prüfen)
$plugin_info{$plugname.'_cycle'} = 86400;

my %options = ();
$options{'dream_ip'} = "172.17.2.90";	  # IP-Adresse der Dreambox

# Drei verschiedene Möglichkeiten zur Nutzung:
# VARIANTE 1: Wert auf einer GA sendet fixe Nachricht mit Wert (Bitwert oder Bytewert):
my %meldungs_ga; # Eintrag darf nicht auskommentiert werden, solange nachfolgend keine GA definiert erfolgt kein Versand!
$meldungs_ga{'14/5/208'} = "1;5;Text208"; # Type,Timeout,Text - ggfs. NUR DIESE Zeile auskommentieren um Variante 1 nicht zu nutzen!
$meldungs_ga{'14/5/209'} = "1;5;Text209"; # Type,Timeout,Text - ggfs. NUR DIESE Zeile auskommentieren um Variante 1 nicht zu nutzen!
# Type: 1=Info-Icon,2=kein Icon,3= Error-Icon,0=Frage ja/nein->nonsens hier

# VARIANTE 2: Plugin horcht auf UDP-Port und empfängt Format Type;Timeout;Text\n
# Vorteil: man mann aus anderen Plugins - sofern diese vorhanden - z.B. auch einfach mit 
# syswrite($socket[131],"1;5;MeinText");
# eine Meldung absetzten. 131 siehe oben, die Variable ist nur lokal im Plugin vorhanden
my $recv_ip = "0.0.0.0"; # Empfangs-IP
my $recv_port = "50019"; # Empfangsport 

# VARIANTE 3: vordefinierte Meldungstexte je nach Inhalt des Telegramms (1-Byte unsigned DPT5.010 - 0-255)
my $meldungs_array_ga = "14/5/210"; # Eintrag darf nicht auskommentiert werden, solange nachfolgend keine Meldung definiert erfolgt kein Versand!
my @meldungs_array; # Eintrag darf nicht auskommentiert werden, solange nachfolgend keine Meldung definiert erfolgt kein Versand!
$meldungs_array[0] = "1;5;Text für Wert 0";
#...
$meldungs_array[99] = "1;5;Text für Wert 99";

#######################
### ENDE DEFINITION ###
#######################

# Hauptverarbeitung
if (!$socket[$socknum]) { # horchenden UDP-socket erstellen
    $socket[$socknum] = IO::Socket::INET->new(LocalPort => $recv_port,
                              Proto => "udp",
                              LocalAddr => $recv_ip,
                              ReuseAddr => 1
                               )
         or return ("open of $recv_ip : $recv_port failed: $!");
    $socksel->add($socket[$socknum]); # add socket to select
    $plugin_socket_subscribe{$socket[$socknum]} = $plugname; # subscribe plugin
    # subscribe GA's
    while( my ($k, $v) = each(%meldungs_ga) ) {
	# Plugin an Gruppenadresse "anmelden"
	$plugin_subscribe{$k}{$plugname} = 1;
    }
    $plugin_subscribe{$meldungs_array_ga}{$plugname} = 1;

    return "opened UDP-Socket $socknum";
} 

if (%msg) { # telegramm vom KNX
  if ($msg{'apci'} eq "A_GroupValue_Write" and $meldungs_ga{$msg{'dst'}}) {
        return sendDream($meldungs_ga{$msg{'dst'}});
  } elsif ($msg{'apci'} eq "A_GroupValue_Write" and $meldungs_array_ga and $meldungs_array[$msg{'data'}]) {
  	    return sendDream($meldungs_array[$msg{'data'}]);
  }
} elsif ($fh) { # UDP-Packet
        my $buf = <$fh>;
        chomp $buf;
        return sendDream($buf);
} else {
    # cyclic/init/change
    # subscribe GA's
    while( my ($k, $v) = each(%meldungs_ga) ) {
      # Plugin an Gruppenadresse "anmelden"
      $plugin_subscribe{$k}{$plugname} = 1;
    }
    $plugin_subscribe{$meldungs_array_ga}{$plugname} = 1;
    return; # ("return dunno");
}

sub sendDream {
  ($options{'type'},$options{'timeout'},$options{'text'}) = split ';',shift;
  use LWP::UserAgent;
  # URL encode our arguments
  $options{'text'} =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
  # Generate our HTTP request.
  my ($userAgent, $request, $response, $requestURL);
  $userAgent = LWP::UserAgent->new;
  $userAgent->agent("WireGatePlugin/1.0");
  
  $requestURL = sprintf("http://%s/web/message?type=%d&timeout=%d&text=%s",
                  $options{'dream_ip'},
                  $options{'type'},
                  $options{'timeout'},
                  $options{'text'});
  
  $request = HTTP::Request->new(GET => $requestURL);
  
  $response = $userAgent->request($request);
  
  if ($response->is_success) {
      return "Notification successfully posted: $options{'type'},$options{'timeout'},$options{'text'}";
  } elsif ($response->code == 401) {
      return "Notification not posted: access denied: " . $response->content;
  } else {
      return "Notification not posted: " . $response->content;
  }
}

return;
