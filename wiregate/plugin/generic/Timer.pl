# Timer
# v 0.2 
# 2013-01-31 JuMi2006 -> http://knx-user-forum.de

#####################
### Konfiguration ###
#####################

my $ga  = "0/0/7";     #GA
my $delay = 900;          #Delay in Sekunden
my $start_value = 1;    #Timerstart bei 1 -> 1 (Aus-Timer)
            #Timerstart bei 0 -> 0 (An-Timer)
            
##########################
### Ende Konfiguration ###
##########################

$plugin_info{$plugname.'_cycle'} = 60;
$plugin_subscribe{$ga}{$plugname} = 1;    
my $val_in = knx_read($ga,300,1);
my $time = time;

if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $ga)
{      
    if ($val_in == $start_value)   # wenn Start von GA erkannt
    {
    plugin_log($plugname,"Timer aktiv");
    $plugin_info{$plugname.'_timer_active'} = 1;# setzt eine Variable zur Fehlervermeidung
    $plugin_info{$plugname.'_last_start'} = time;
    }
    
    if ($val_in == !$start_value)   # wenn Stop von GA erkannt
    {       
    $plugin_info{$plugname.'_timer_active'} = 0;    # setzt eine Variable zur Fehlervermeidung
    plugin_log($plugname,"Timer deaktiviert");
    }
}

else

{
    if (($plugin_info{$plugname.'_timer_active'} == 1) && ($time > ($plugin_info{$plugname.'_last_start'} + $delay)))
    {
    knx_write($ga,!$start_value,1);                 # negiert senden
    $plugin_info{$plugname.'_timer_active'} = 0;    # setzt eine Variable zur Fehlervermeidung
    plugin_log($plugname,"Timer abgelaufen");
    }
}

return;