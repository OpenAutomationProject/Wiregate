# Plugin to control vdr from KNX
# (or run any command ?!)
# this is just a Quickhack!

# no cycle, maybe useful for sending hitk ok?
$plugin_info{$plugname.'_cycle'} = 0;

my %cmd_ga;

### ANFANG config ###
# VARIANTE 1: Wert im Befehlt mit ausgeben, printf-Syntax - DPT der GA muss konfiuriert sein!
# unbenötigtes einfach löschen
$cmd_ga{'10/3/1'} = '/etc/init.d/vdr restart';
$cmd_ga{'10/3/2'} = '/etc/init.d/mpd restart';
$cmd_ga{'10/3/3'} = '/etc/init.d/ddclient restart';
$cmd_ga{'10/3/11'} = 'irgendwas %.2f';
$cmd_ga{'10/3/12'} = 'reboot';

### ENDE config ###

if (%msg) { # telegramm vom KNX
  if ($msg{'apci'} eq "A_GroupValue_Write" and $cmd_ga{$msg{'dst'}}) {
        return `$cmd_ga{$msg{'dst'}}`;
        #FIXME: sprintf!
#  } elsif ($msg{'apci'} eq "A_GroupValue_Write" and $meldungs_array_ga and $meldungs_array[$msg{'data'}]) {
#  	return sendDream($meldungs_array[$msg{'data'}]);
  }
} elsif ($fh) { # UDP-Packet
        my $buf = <$fh>;
        chomp $buf;
#        return sendDream($buf);
} else {
    # cyclic/init/change
    # subscribe GA's
    while( my ($k, $v) = each(%cmd_ga) ) {
      # Plugin an Gruppenadresse "anmelden"
      $plugin_subscribe{$k}{$plugname} = 1;
    }
#    $plugin_subscribe{$meldungs_array_ga}{$plugname} = 1;
    return; # ("return dunno");
}

