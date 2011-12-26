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

#############################################################################
# Configuration:
# --> change values in the conf.d directory!
my $IP_of_Russound;
my $MAC_of_Russound;
my $numzones;
my $KNX_Start_Address;

my $reset     ; # set to 1 to reset the states, run script and change to 0 again
my $show_debug; # switches debug information that will be shown in the log

#############################################################################
# Do NOT change anything below!
#############################################################################

#############################################################################
# External libraries:
use Net::Telnet ();

#############################################################################
# Constants:
my $MAX_ZONES = 31;
my $ZONES_PER_CONTROLLER = 6;

#############################################################################
# Collect log information
my $retval = '';

my $destReadable =  $msg{'dst'};
my $val = hex $msg{'data'};

# Convert to numeric GA
(my $a, my $b, my $c) = split(/\//, $KNX_Start_Address );
my $knxstartaddress = (($a << 11) + ($b << 8) + $c);

# Convert to numeric GA
($a,$b,$c) = split(/\//, $destReadable );
my $dest = (($a << 11) + ($b << 8) + $c);

# Eigenen Aufruf-Zyklus ausschalten
$plugin_info{$plugname.'_cycle'} = 0;

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
  
  sendrussFunc( $controller, $zone, $func, $val );
}

return $retval;

#############################################################################
# Helper funtions
sub sendcmd 
{
  my $cmd = shift;
  my $t = new Net::Telnet (
    Timeout => 10,
    Host => $IP_of_Russound,
    Port => 9621,
    Prompt => '/^/',
    Telnetmode => 0
  );
  $t->open();
  $t->print( $cmd );
  $t->close();
  my $res = $t->getline();
  $retval .= $cmd . '->' . $res if $show_debug;
  return $res;
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
    `wakeonlan $MAC_of_Russound`; # just to be sure
    sendcmd("EVENT $cz!ZoneOff") if( $val == 0 );
    sendcmd("EVENT $cz!ZoneOn" ) if( $val == 1 );
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
    return 'Func ' . $func . ' not implemented or known';
  } elsif( 6 == $func ) #bal
  {
    my $mapped = $val > 10 ? $val-256 : $val;
    sendcmd("SET $cz.balance=\"$mapped\"");
  } elsif( 7 == $func ) #party
  {
    return 'Func ' . $func . ' not implemented or known';
  } elsif( 8 == $func ) #dnd
  {
    return 'Func ' . $func . ' not implemented or known';
  } elsif( 9 == $func ) #turnonvol
  {
    my $mapped = int( $val * 50/255 );
    sendcmd("SET $cz.turnOnVolume=\"$mapped\"");
  #TODO: 10 src cmd and 11 keypadcmd
  } elsif( 12 == $func ) #volume relative up/down
  {
    return 'Func ' . $func . ' not implemented or known';
  } else {
    return 'Func ' . $func . ' not implemented or known';
  }
}
