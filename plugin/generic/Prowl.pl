# Plugin um Nachrichten an Prowl zu senden
# Version: 0.1 2010-10-14
# Benötigt einen Prowl-Account sowie API-Key

##################
### DEFINITION ###
##################

my $socknum = 8;                # Eindeutige Nummer des Sockets

# Eigenen Aufruf-Zyklus setzen (Initialisierung/zyklisches prüfen)
$plugin_info{$plugname.'_cycle'} = 300;

my %options = ();
$options{'apikey'} = "xyzxyz";


# Zwei Möglichkeiten zur Nutzung:
# VARIANTE 1: Bitwert auf GA sendet fixes Nachricht:
my %prowl_ga; # Eintrag darf nicht auskommentiert werden, solange nachfolgend keine GA definiert erfolgt kein Versand!
$prowl_ga{'14/5/208'} = '0;Event;Description Hallo;Application'; # Priority,Event,Description,Application - ggfs. NUR DIESE Zeile auskommentieren!

# VARIANTE 2: Plugin horcht auf UDP-Port und empfängt Format PRIO;Event;Description;Application\n
my $recv_ip = "0.0.0.0"; # Empfangs-IP
my $recv_port = "50018"; # Empfangsport 

#######################
### ENDE DEFINITION ###
#######################

# Hauptverarbeitung
if (!$socket[$socknum]) { # socket erstellen
    if (defined $socket[$socknum]) { #debug
        if ($socket[$socknum]->opened) { $socket[$socknum]->close(); }
        undef $socket[$socknum];
    }  #debug
    $socksel->remove($socket[$socknum]);
    $socket[$socknum] = IO::Socket::INET->new(LocalPort => $recv_port,
                              Proto => "udp",
                              LocalAddr => $recv_ip,
                              ReuseAddr => 1
                               )
	     or return ("open of $recv_ip : $recv_port failed: $!");
    $socksel->add($socket[$socknum]); # add socket to select
    $plugin_socket_subscribe{$socket[$socknum]} = $plugname; # subscribe plugin
    # subscribe GA's
 		while( my ($k, $v) = each(%prowl_ga) ) {
      # Plugin an Gruppenadresse "anmelden"
      $plugin_subscribe{$k}{$plugname} = 1;
 		}
    return "opened UDP-Socket $socknum";
} 

if (%msg) { # telegramm vom KNX
  if ($msg{'apci'} eq "A_GroupValue_Write" and $prowl_ga{$msg{'dst'}}) {
        return sendProwl($prowl_ga{$msg{'dst'}});
  }
} elsif ($fh) { # UDP-Packet
        my $buf = <$fh>;
        chomp $buf;
        return sendProwl($buf);
} else {
    # cyclic/init/change
    # subscribe GA's
 		while( my ($k, $v) = each(%prowl_ga) ) {
      # Plugin an Gruppenadresse "anmelden"
      $plugin_subscribe{$k}{$plugname} = 1;
 		}
    return; # ("return dunno");
}

sub sendProwl {
  ($options{'priority'},$options{'event'},$options{'description'},$options{'application'}) = split ';',shift;
  use LWP::UserAgent;
  $options{'priority'} ||= 0;
  $options{'application'} ||= "WireGate KNX"; # Application fuer Telegramme
  # URL encode our arguments
  $options{'application'} =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
  $options{'event'} =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
  $options{'notification'} =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
  # Generate our HTTP request.
  my ($userAgent, $request, $response, $requestURL);
  $userAgent = LWP::UserAgent->new;
  $userAgent->agent("WireGatePlugin/1.0");
  
  $requestURL = sprintf("https://prowl.weks.net/publicapi/add?apikey=%s&application=%s&event=%s&description=%s&priority=%d",
  				$options{'apikey'},
  				$options{'application'},
  				$options{'event'},
  				$options{'notification'},
  				$options{'priority'});
  
  $request = HTTP::Request->new(GET => $requestURL);
  #$request->timeout(5);

  $response = $userAgent->request($request);
  
  if ($response->is_success) {
  	return "Notification successfully posted: $options{'priority'},$options{'event'},$options{'description'},$options{'application'}";
  } elsif ($response->code == 401) {
  	return "Notification not posted: incorrect API key.";
  } else {
  	return "Notification not posted: " . $response->content;
  }

}

return;
