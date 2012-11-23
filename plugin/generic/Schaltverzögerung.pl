# Schaltverzögerung
# 0.1 
# 2012-11-23 JuMi2006 -> http://knx-user-forum.de

#####################
### Konfiguration ###
#####################

my $ga_in  = "0/0/201"; #GA Eingang
my $ga_out = "0/0/202"; #GA Ausgang
my $delay = 5;          #Delay in Sekunden
my $start_value = 1;	#Verzögerung bei 1 -> 1 (Einschaltverzögerung)
						#Verzögerung bei 0 -> 0 (Ausschaltverzögerung)
						
##########################
### Ende Konfiguration ###
##########################

$plugin_info{$plugname.'_cycle'} = 0;
$plugin_subscribe{$ga_in}{$plugname} = 1;	

if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $ga_in)
{
my $val_in = knx_read($ga_in,300,1);
    
    if ($val_in == !$start_value)   	
    {
    knx_write($ga_out,$val_in,1);  
    plugin_log($plugname,"Telegrammweiterleitung");
    $plugin_info{$plugname.'_delay_active'} = 0;
    }
    
    if ($val_in == $start_value)   
    {
    $plugin_info{$plugname.'_last'} = time;
    $plugin_info{$plugname.'_cycle'} = $delay;  
    $plugin_info{$plugname.'_delay_active'} = 1;
    plugin_log($plugname,"Delay aktiv. Wiederausführung in $delay Sekunden");
    }
}

else

{
    if ($plugin_info{$plugname.'_delay_active'} == 1)
    {
    knx_write($ga_out,$start_value,1);                          
    $plugin_info{$plugname.'_delay_active'} = 0;    
    plugin_log($plugname,"Delay von $delay Sekunden ausgeführt");
    $plugin_info{$plugname.'_last'} = time;
    $plugin_info{$plugname.'_cycle'} = 0;
    }
}

return;
