#############################################################################
# Plugin: Multi RTR
# V0.5 2011-09-18
# Copyright: Christian Mayer (mail at ChristianMayer.de)
# License: GPL (v3)
#
# Plugin for multiple RTR (room temperature controllers) by using a PI 
# controller
#
# Suggested settings:
# ===================
# floor heating:     ProportionalGain = 5 K, IntegralTime = 240 min (*)
# hot water heating: ProportionalGain = 5 K, IntegralTime = 150 min (*)
#
# Uebersetzungshilfe:
# ===================
# ProportionalGain = Proportionalbereich in Kelvin
# IntegralTime     = Nachstellzeit in Minuten
#
# ---------
# (*): GIRA manual for TS2+ with RTR 1052-00 / 1055-00, 01/06, page 71
#############################################################################

#############################################################################
# Configuration:
my %controllers = (
  '130_Hobby1_HK'   => {
    'SetPointGA' => '3/3/130', 'SetPointRRD' => '130_Hobby1_HK_Sollwert', 
    'SensorGA'   => '4/0/130', 
    'ActuatorGA' => '3/0/130', 'ActuatorRRD' => '130_Hobby1_HK_Regelung', 
    'ProportionalGain' => 5, 'IntegralTime' => 150 
  },
  '140_Hobby2_HK'   => { 
    'SetPointGA' => '3/3/140', 'SetPointRRD' => '140_Hobby2_HK_Sollwert', 
    'SensorGA'   => '4/0/140', 
    'ActuatorGA' => '3/0/140', 'ActuatorRRD' => '140_Hobby2_HK_Regelung', 
    'ProportionalGain' => 5, 'IntegralTime' => 240 
  },
);
my %default = (
  'SetPointDPT'   => 9.001,
  'SensorDPT'     => 9.001,
  'ActuratorDPT'  => 5,
  'DisableDPT'    => 1,
  'SetPointInit'  => 21.0,
  'SetPointLFlag' => 1, # true
  'ActuatorLFlag' => 1, # true
  'MinUpdateRate' => 5 * 60, # 5 minutes
);

my $GlobalDisableGA = '14/5/50';

my $reset      = 0; # set to 1 to reset the states, run script and change to 0 again
my $show_debug = 1; # switches debug information that will be shown in the log

#############################################################################
# Do NOT change anything below!
#############################################################################
my $busActive = !(!keys %msg); # true if script was called due to bus traffic

my $ret_val = '';
#############################################################################
# Initialisation
if( !$busActive ) # unnecesary during bus traffic
{
  for my $this_controller_name ( keys %controllers ) 
  {
    my %this_controller = (%{$controllers{ $this_controller_name }}, %default);
    
    # Initialise controller state variables
    if( $reset or not exists $plugin_info{ $plugname . '_' . $this_controller_name . '_Actuator' } )
    {
      $plugin_info{ $plugname . '_' . $this_controller_name . '_SetPoint' } = $this_controller{ 'SetPointInit' };
      $plugin_info{ $plugname . '_' . $this_controller_name . '_Integral' } = 0;
      $plugin_info{ $plugname . '_' . $this_controller_name . '_Actuator' } = 0;  # Reset
      if( defined $this_controller{ 'SetPointGA' } and defined $this_controller{ 'SetPointDPT' } )
      {
        knx_write( $this_controller{ 'SetPointGA' }, $this_controller{ 'SetPointInit' }, $this_controller{ 'SetPointDPT' } ); # send initial value
      }
      # The ActuatorGA doesn't need to be sent here as !$busActive will also
      # cause the first round of controller calculations
    }
    
    # subscribe SetPointGA
    if( defined $this_controller{ 'SetPointGA' } )
    {
      $plugin_subscribe{ $this_controller{ 'SetPointGA' } }{ $plugname } = 1;
    }
    # subscribe SensorGA
    if( defined $this_controller{ 'SensorGA'   } )
    {
      $plugin_subscribe{ $this_controller{ 'SensorGA'   } }{ $plugname } = 1;
    }
    # subscribe ActuatorGA
    if( defined $this_controller{ 'ActuatorGA' } )
    {
      $plugin_subscribe{ $this_controller{ 'ActuatorGA' } }{ $plugname } = 1;
    }
    # subscribe DisableGA
    if( defined $this_controller{ 'DisableGA'  } )
    {
      $plugin_subscribe{ $this_controller{ 'DisableGA'  } }{ $plugname } = 1;
      
      $ret_val .= $this_controller_name . ' disabled?';
      my $active = knx_read( $this_controller{ 'DisableGA' } ) || 1; # active if unreadable
      if ( !int($active) and defined $this_controller{ 'ActuatorGA' } ) {
        if (knx_read( $this_controller{ 'ActuatorGA' } ) ne 0) { # only if not already 0 
          knx_write( $this_controller{ 'ActuatorGA' }, 0, $this_controller{ 'ActuatorDPT' } );
        }
        $plugin_info{ $plugname . '_' . $this_controller_name . '_Integral' } = 0;
        $plugin_info{ $plugname . '_' . $this_controller_name . '_Actuator' } = 0;  # Reset
        $ret_val .= ' yes';
      } else {
        $ret_val .= ' no';
      }
    }
  }
}

# Set the update cycle to one minute
$plugin_info{$plugname.'_cycle'} = 60;

#############################################################################
# Handle the bus traffic
my $SetPointChange = 0;
if( $busActive )
{
  # Early exit during a response messeage - it's usually from us...
  if( $msg{'apci'} eq 'A_GroupValue_Response' )
  {
    return;
  }
  
  # a linear search isn't smart but OK for only a few states:
  for my $this_controller_name ( keys %controllers ) 
  {
    my %this_controller = (%{$controllers{ $this_controller_name }}, %default);
    if(   $msg{'apci'} eq 'A_GroupValue_Read' ) 
    {
      if(      $msg{'dst'} eq $this_controller{ 'SetPointGA' } and $this_controller{ 'SetPointLFlag' })
      {
        # A read request for this GA was sent on the bus and the L-flag is set
        my $value = $plugin_info{ $plugname . '_' . $this_controller_name . '_SetPoint'  };
        my $DPT   = $this_controller{ 'SetPointDPT' };
        knx_write( $msg{'dst'}, $value, $DPT, 1 ); # send response
        $ret_val .= 'read(' . $msg{'dst'} . '=' . $this_controller_name . ') SetPoint -> ' . $value;
      } elsif( $msg{'dst'} eq $this_controller{ 'ActuatorGA' } and $this_controller{ 'ActuatorLFlag' })
      {
        # A read request for this GA was sent on the bus and the L-flag is set
        my $value = $plugin_info{ $plugname . '_' . $this_controller_name . '_Actuator'  };
        my $DPT   = $this_controller{ 'ActuatorDPT' };
        knx_write( $msg{'dst'}, $value, $DPT, 1 ); # send response
        $ret_val .= 'read(' . $msg{'dst'} . '=' . $this_controller_name . ') Actuator -> ' . $value;
      }
    } 
    elsif($msg{'apci'} eq 'A_GroupValue_Write')
    {
      if( $msg{'dst'} eq $this_controller{ 'SetPointGA' } )
      {
        # A new(?) setpoint was sent on the bus => update internal state
        # read from eibd cache, so we'll get the cast for free:
        my $value = knx_read( $msg{'dst'}, 0, $this_controller{ 'SetPointDPT' } ); 
        $plugin_info{ $plugname . '_' . $this_controller_name . '_SetPoint'  } = $value;
        $SetPointChange = 1;
        $ret_val .= 'write(' . $msg{'dst'} . '=' . $this_controller_name . ') ' . $value . ' -> SetPoint';
      }
    }
  }
} # if( $busActive )

#############################################################################
# Update the controllers
if( !$busActive or $SetPointChange ) # only at init, cycle or set point change
{
  my $dt = time() - $plugin_info{ $plugname . '_tlast' };
  $plugin_info{ $plugname . '_tlast' } = time();
  $ret_val .= 'dt: ' . $dt . '; ';
  
  for my $this_controller_name ( keys %controllers ) 
  {
    my %this_controller = (%{$controllers{ $this_controller_name }}, %default);
    my $prefix = $plugname . '_' . $this_controller_name;
    
    my $Sensor   = knx_read( $this_controller{ 'SensorGA' }, 0, $this_controller{ 'SensorDPT' } );
    my $SetPoint = $plugin_info{ $prefix . '_SetPoint'  };
    my $old = $plugin_info{ $prefix . '_Actuator' };
  
    my $kp = 1.0 / $this_controller{ 'ProportionalGain' };
    my $error = $SetPoint - $Sensor;
    
    # caclulate the I part of the PI controller:
    $plugin_info{ $prefix . '_Integral' } = $plugin_info{ $prefix . '_Integral' } + $error * $dt;
    my $integral = $plugin_info{ $prefix . '_Integral' } / (60.0 * $this_controller{ 'IntegralTime' });
    
    # put together the PI controller:
    $plugin_info{ $prefix . '_Actuator' } = 100.0 * $kp * ($error + $integral);
    
    # clip at maximum to avoid windup:
    if( $plugin_info{ $prefix . '_Actuator' } > 100 )
    {
      $ret_val .= '[>]';
      $plugin_info{ $prefix . '_Actuator' } = 100;
      $plugin_info{ $prefix . '_Integral' } = (1.0 / $kp) * 60.0 * $this_controller{ 'IntegralTime' };
    }
    # clip at minimum
    if( $plugin_info{ $prefix . '_Actuator' } < 0 or $plugin_info{ $prefix . '_Integral' } < 0 )
    {
      $ret_val .= '[<]';
      $plugin_info{ $prefix . '_Actuator' } = 0 if $plugin_info{ $prefix . '_Actuator' } < 0;
      $plugin_info{ $prefix . '_Integral' } = 0;
    }
    #$plugin_info{ $prefix . '_Actuator' } = round( $plugin_info{ $prefix . '_Actuator' } );
    
    # If a GA is defined, send the new actuator value
    if( defined $this_controller{ 'ActuatorGA' } and (
        ($old ne $plugin_info{ $prefix . '_Actuator' }) or (time() - $plugin_info{ $prefix . '_lastSent' } > $this_controller{'MinUpdateRate'} )) )
    {
      knx_write( $this_controller{ 'ActuatorGA' }, $plugin_info{ $prefix . '_Actuator' }, $this_controller{ 'ActuatorDPT' } );
      $plugin_info{ $prefix . '_lastSent' } = time();
    }
    
    if( defined $this_controller{ 'SetPointRRD' } )
    {
      update_rrd( $this_controller{ 'SetPointRRD' }, '', $SetPoint );
    }
    if( defined $this_controller{ 'ActuatorRRD' } )
    {
      update_rrd( $this_controller{ 'ActuatorRRD' }, '', $plugin_info{ $prefix . '_Actuator' } );
    }
    
    $ret_val .= $this_controller_name . ': ' . $SetPoint . '<>' . $Sensor . '=>' . $plugin_info{ $prefix . '_Actuator' } . ' [' . ($error*$kp) . '/' . $integral*$kp . ']; ';
  }
}

if( $show_debug ) { return $ret_val; }
return;

#############################################################################
# Version history:
# ================
#
# 0.6:
# * Bug fix for setups where the WireGate didn't know the ActuatorGA
# * Force sending of actuator after x seconds/minutes so that the watchdog in 
#   the actuator doesn't time out
# 0.5:
# * initial release
#
#############################################################################
# ToDo:
# =====
# * Limit bus traffic by sending actuator values after a change that is bigger 
#   than x%
# * Add GA for sending delta values for the setpoint
# * External Config
# * Actuator overwrite ("Zwangsstellung")
# * Hard temperature limit (min, max)
#############################################################################
