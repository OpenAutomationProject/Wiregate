# Timer
# v 0.1 
# 2012-11-23 JuMi2006 -> http://knx-user-forum.de

#####################
### Konfiguration ###
#####################

my $ga  = "0/0/201"; 	#GA
my $delay = 5;          #Delay in Sekunden
my $start_value = 0;	#Timerstart bei 1 -> 1 (Aus-Timer)
						#Timerstart bei 0 -> 0 (An-Timer)
			
##########################
### Ende Konfiguration ###
##########################

$plugin_info{$plugname.'_cycle'} = 0;
$plugin_subscribe{$ga}{$plugname} = 1;	
my $val_in = knx_read($ga,300,1);

if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $ga)
{	  
    if ($val_in == $start_value)   # wenn Start von GA erkannt
    {
    plugin_log($plugname,"Timer aktiv");
    $plugin_info{$plugname.'_delay_active'} = 1;# setzt eine Variable zur Fehlervermeidung
    $plugin_info{$plugname.'_last'} = time;
    $plugin_info{$plugname.'_cycle'} = $delay;  # Plugin-Wiederholung nach X Sekunden
    }
    
    if ($val_in == ~$start_value)   # wenn Stop von GA erkannt
    {
    $plugin_info{$plugname.'_last'} = time;
    $plugin_info{$plugname.'_cycle'} = 0;  		
    $plugin_info{$plugname.'_timer_active'} = 0;	# setzt eine Variable zur Fehlervermeidung
    plugin_log($plugname,"Timer deaktiviert");
    }
}

else

{
    if ($plugin_info{$plugname.'_timer_active'} == 1)
    {
    knx_write($ga,!$start_value,1);                 # negiert senden
    $plugin_info{$plugname.'_timer_active'} = 0;    # setzt eine Variable zur Fehlervermeidung
    plugin_log($plugname,"Timer abgelaufen");
    $plugin_info{$plugname.'_last'} = time;
    $plugin_info{$plugname.'_cycle'} = 0;
    }
}

return;