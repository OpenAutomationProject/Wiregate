#############################################################################
# Plugin: Russound RIO
# V0.1 2011-12-26
# Copyright: Christian Mayer (mail at ChristianMayer.de)
# License: GPL (v3)
#
# Plugin for talking to the Russound multi room amplifiers via the RIO
# protocoll over the IP interface
#
# Suggested settings:
# ===================
#
#############################################################################

#return;   # uncomment to disable plugin

#############################################################################
# Configuration:
# --> change values in the conf.d directory!
my $IP_of_Russound;
my $MAC_of_Russound;
my $numzones;
my $KNX_Start_Address;

my $socknum;    # unique number of the Socket

my $reset     ; # set to 1 to reset the states, run script and change to 0 again
my $show_debug; # switches debug information that will be shown in the log
#############################################################################
# Do NOT change anything below!
#############################################################################

#############################################################################
# Constants:
my $MAX_ZONES = 31;
my $ZONES_PER_CONTROLLER = 6;

#############################################################################
# Collect log information
my $retval = '';

#############################################################################
# Read config file in conf.d
my $confFile = '/etc/wiregate/plugin/generic/conf.d/'.basename($plugname,'.pl').'.conf';
if (! -f $confFile)
{
  plugin_log($plugname, " no conf file [$confFile] found."); 
}
else
{
  plugin_log($plugname, " reading conf file [$confFile].") if( $show_debug > 1); 
  open(CONF, $confFile);
  my @lines = <CONF>;
  close($confFile);
  my $result = eval("@lines");
  if( $show_debug > 1 )
  {
    ($result) and plugin_log($plugname, "conf file [$confFile] returned result[$result]");
  }
  if ($@) 
  {
    plugin_log($plugname, "conf file [$confFile] returned:") if( $show_debug > 1 );
    my @parts = split(/\n/, $@);
    if( $show_debug > 1 )
    {
      plugin_log($plugname, "--> $_") foreach (@parts);
    }
  }
}

#############################################################################
# Configure socket
if (!$socket[$socknum]) { # if it doesn't exist: create socket
  if ($IP_of_Russound) {
    $socket[$socknum] = IO::Socket::INET->new(
      PeerAddr => $IP_of_Russound, 
      PeerPort => '9621', 
      Proto => 'tcp', 
      Timeout => 120, 
      Blocking => 0
    );
    if(!$socket[$socknum]) # retry with WOL if first try didn't work
    {
      `wakeonlan $MAC_of_Russound`;
      $socket[$socknum] = IO::Socket::INET->new(
        PeerAddr => $IP_of_Russound, 
        PeerPort => '9621', 
        Proto => 'tcp', 
        Timeout => 120, 
        Blocking => 0
      );
    }
    if(!$socket[$socknum]) { # fail if second try also didn't work
      return "open of $IP_of_Russound failed: $!";
    }
  } else {
    return "ERROR: No IP address configured!";
  }

  $socksel->add($socket[$socknum]); # add socket to select

  $plugin_socket_subscribe{$socket[$socknum]} = $plugname; # subscribe plugin
  $retval .= "opened Socket $socknum!" if $show_debug;
} 

#############################################################################
my $destReadable =  $msg{'dst'};
my $val = hex $msg{'data'};

# Convert to numeric GA
my $knxstartaddress = str2addr( $KNX_Start_Address );
my $dest = str2addr( $destReadable );

# Eigenen Aufruf-Zyklus ausschalten
$plugin_info{$plugname.'_cycle'} = 0;

if (%msg) { # KNX telegramm
  $retval .= 'KNX:' if $show_debug;
} elsif ($fh) { # incoming network message
  my $sockInfo .= 'Socket: [';
  my $cnt = 0;
  my $line;
  $/ = "\r\n"; # remove all new line
  while( defined ($line = <$fh>) )
  {
    chomp( $line );
    $sockInfo .= ($cnt++) . ': ' . $line .';';
    handleRussResponse( $line );
  }
  $retval .= $sockInfo if $show_debug;
} else 
{ # called during init or on cycle intervall
  syswrite( $socket[$socknum],  "VERSION\r" );
  syswrite( $socket[$socknum],  "WATCH System ON\r" );

  # aboniere alle relevanten GAs
  for (my $zone=0;$zone<$numzones;$zone++) 
  {
    my $ctrl = int($zone/$ZONES_PER_CONTROLLER);
    my $czone = int($zone%$ZONES_PER_CONTROLLER);
    my $base = $knxstartaddress + 10 + ($czone*40) + ($ctrl*256);
    for( my $i = 0; $i < 13; $i++ ) # iterate funcnames
    {
      my $a = $base + $i;
      my $gastr = sprintf "%d/%d/%d", ($a >> 11) & 0xf, ($a >> 8) & 0x7, $a & 0xff;
      $plugin_subscribe{$gastr}{$plugname} = 1;
    }
    for( my $i = 0; $i < 10; $i++ ) # iterate stateames
    {
      my $a = $base + $i + 20;
      my $gastr = sprintf "%d/%d/%d", ($a >> 11) & 0xf, ($a >> 8) & 0x7, $a & 0xff;
      $plugin_subscribe{$gastr}{$plugname} = 1;
    }
  }
}

$retval .= $msg{'apci'} . '->' . $msg{'dst'} . ';'. $msg{'data'} . ';' if $show_debug;

#############################################################################
# Main function
if($msg{'apci'} eq "A_GroupValue_Write")
{
  # Transfere KNX Address to Russound Function similarly
  # to the rusconnectd
  my $func;
  my $zone;
  my $controller;
  {
    use integer;
    $func = ($dest - $knxstartaddress) % 256;
    $zone = ($func - 10) / 40;
    $func = ($func - 10) % 40;
    $controller = ($dest - $knxstartaddress) / 256;
  }
  
  if( $func < 20) # >= 20 = response addresses
  {
    $retval .= sendrussFunc( $controller, $zone, $func, $val );
  }
}

return $retval;

#############################################################################
# Helper funtions
sub sendcmd 
{
  my $cmd = shift;
  syswrite( $socket[$socknum],  "$cmd\r" );
  return;
}

sub sendrussFunc
{
  my $controller = shift;
  my $zone       = shift;
  my $func       = shift;
  my $val        = shift;

  my $cz = 'C[' . ($controller+1) . '].Z[' . ($zone+1) . ']';

  if( -9 == $func ) #all zones
  {
    return 'Func ' . $func . ' not implemented or known';
  } elsif( 0 == $func ) #power
  {
    if( $val == 0 )
    {
      sendcmd("EVENT $cz!ZoneOff");
      sendcmd("WATCH $cz OFF" );
    } else {
      `wakeonlan $MAC_of_Russound`; # just to be sure
      sendcmd("EVENT $cz!ZoneOn" );
      sendcmd("WATCH $cz ON" );
    }
  } elsif( 1 == $func ) #src
  {
    my $mapped = $val + 1;
    sendcmd("EVENT $cz!SelectSource $mapped");
  } elsif( 2 == $func ) #volume
  {
    my $mapped = int( $val * 50/255 );
    sendcmd("EVENT $cz!KeyPress Volume $mapped");
  } elsif( 3 == $func ) #bass
  {
    my $mapped = $val > 10 ? $val-256 : $val;
    sendcmd("SET $cz.bass=\"$mapped\"");
  } elsif( 4 == $func ) #treb
  {
    my $mapped = $val > 10 ? $val-256 : $val;
    sendcmd("SET $cz.treble=\"$mapped\"");
  } elsif( 5 == $func ) #loud
  {
    sendcmd("SET $cz.loudness=\"" . ($val?'ON':'OFF') . '"');
  } elsif( 6 == $func ) #bal
  {
    my $mapped = $val > 10 ? $val-256 : $val;
    sendcmd("SET $cz.balance=\"$mapped\"");
  } elsif( 7 == $func ) #party
  {
    sendcmd("EVENT $cz!PartyMode " . ($val?'ON':'OFF') );
  } elsif( 8 == $func ) #dnd
  {
    sendcmd("EVENT $cz!DoNotDisturb " . ($val?'ON':'OFF') );
  } elsif( 9 == $func ) #turnonvol
  {
    my $mapped = int( $val * 50/255 );
    sendcmd("SET $cz.turnOnVolume=\"$mapped\"");
  #TODO: 10 src cmd and 11 keypadcmd
  } elsif( 12 == $func ) #volume relative up/down
  {
    sendcmd("EVENT $cz!KeyPress Volume" . ($val?'Up':'Down') );
  } else {
    return 'Func ' . $func . ' not implemented or known('.$val.')';
  }
}

sub handleRussResponse
{
  my $response = shift;
  
  return if $response eq 'S';
  
  if( $response =~ /^N C\[([0-9]*)\].Z\[([0-9]*)\].(.*)="(.*)"/ )
  { # WATCH message from a controller
    my $index = "${plugname}_$1_$2_$3";
    return if $plugin_info{$index} eq $4; # no change
    
    $plugin_info{$index} = $4;
    sendKNXfuncCZ( $1, $2, $3, $4 );
  } elsif( $response =~ /^N S\[([0-9]*)\].(.*)="(.*)"/ )
  {
    #$retval .= 'S:'.$1.'>'.$2.'>'.$3.';';
  } elsif( $response =~ /^N System.(.*)="(.*)"/ )
  {
    #$retval .= 'System:'.$1.'>'.$2.';';
  } elsif( $response =~ /^S / )
  {
    return; # don't care about response code...
  } else {
    $retval .= "<Unknown: $response>";
  }
}

sub sendKNXfuncCZ
{
  my $C     = shift;
  my $Z     = shift;
  my $state = shift;
  my $val   = shift;
  my $func; # KNX func number
  my $dpt;
  
  if( $state eq 'status' )
  {
    $func = 0;
    $val  = $val eq 'ON' ? 1 : 0;
    $dpt  = 1;
  } elsif( $state eq 'currentSource' )
  {
    $func = 1;
    $val = $val - 1;
    $dpt  = 5.004;
  } elsif( $state eq 'volume' )
  {
    $func = 2;
    $val = int($val * 255 / 50);
    $dpt  = 5.004;
  } elsif( $state eq 'bass' )
  {
    $func = 3;
    $val = $val < 0 ? 256+$val : $val;
    $dpt  = 5.004;
  } elsif( $state eq 'treble')
  {
    $func = 4;
    $val = $val < 0 ? 256+$val : $val;
    $dpt  = 5.004;
  } elsif( $state eq 'loudness' )
  {
    $func = 5;
    $val  = $val eq 'ON' ? 1 : 0;
    $dpt  = 1;
  } elsif( $state eq 'balance' )
  {
    $func = 6;
    $val = $val < 0 ? 256+$val : $val;
    $dpt  = 5.004;
  } elsif( $state eq 'partyMode' )
  {
    $func = 7;
    $val  = ($val eq 'ON' || $val eq 'MASTER') ? 1 : 0;
    $dpt  = 1;
  } elsif( $state eq 'doNotDisturb' )
  {
    $func = 8;
    $val  = $val eq 'ON' ? 1 : 0;
    $dpt  = 1;
  } elsif( $state eq 'turnOnVolume' )
  {
    $func = 9;
    $val = int($val * 255 / 50);
    $dpt  = 5.004;
  } else {
    $retval .= "ERROR: Unknown state '$state' with value '$val'!";
    return;
  }
    
  my $knxGA = $knxstartaddress+30+$func + (($Z-1)*40) + (($C-1)*256);
  knx_write( addr2str( $knxGA, 1 ), $val, $dpt );
  $retval .= 'KNX[' . addr2str( $knxGA, 1 ) . ',' . $dpt . ']:' . $val . ';' if $show_debug;
}