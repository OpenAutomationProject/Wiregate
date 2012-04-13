###################################################################################### 
# 
# Oder Verknüpfung
# V0.1 2012-04-05 
# by Michi26206 - www.knx-user-forum.de
#
###################################################################################### 

######################### 
### BEGINN DEFINITION ### 
######################### 

# Aufruf-Zyklus auf 300 Sekunden setzen
$plugin_info{$plugname.'_cycle'} = 300;


#GA´s
my $Oder1GA = '0/3/2';
my $Oder2GA = '0/3/3';
my $Oder3GA = '0/3/9';
my $Oder4GA = '0/3/10';
my $Oder5GA = '0/3/11';
my $AusgangOderGA = '0/3/1';


#Plugin auf GAs anmelden
$plugin_subscribe{$Oder1GA}{$plugname} = 1;
$plugin_subscribe{$Oder2GA}{$plugname} = 1;
$plugin_subscribe{$Oder3GA}{$plugname} = 1;
$plugin_subscribe{$Oder4GA}{$plugname} = 1;
$plugin_subscribe{$Oder5GA}{$plugname} = 1;


######################### 
###  ENDE DEFINITION  ### 
######################### 

# Plugin aufgrund eines eintreffenden Telegramms oder zyklisch bearbeiten
# bei eintreffenden Telegrammen auf "Write" reagieren

if ($msg{'apci'} eq "A_GroupValue_Write") {
   if ($msg{'dst'} eq $Oder1GA) {
      $plugin_info{$plugname.'_Oder1'} = int($msg{'data'});
   }

   if ($msg{'dst'} eq $Oder2GA) {
      $plugin_info{$plugname.'_Oder2'} = int($msg{'data'});
   }
   
   if ($msg{'dst'} eq $Oder3GA) {
      $plugin_info{$plugname.'_Oder3'} = int($msg{'data'});
   }

   if ($msg{'dst'} eq $Oder4GA) {
      $plugin_info{$plugname.'_Oder4'} = int($msg{'data'});
   }

   if ($msg{'dst'} eq $Oder5GA) {
      $plugin_info{$plugname.'_Oder5'} = int($msg{'data'});
   }
} else { # zyklischer Aufruf
   #$plugin_info{$plugname.'_Oder1'} = knx_read($Oder1GA,300,1);
   #$plugin_info{$plugname.'_Oder2'} = knx_read($Oder2GA,300,1);
   #$plugin_info{$plugname.'_Oder3'} = knx_read($Oder3GA,300,1);
   #$plugin_info{$plugname.'_Oder4'} = knx_read($Oder4GA,300,1);
   #$plugin_info{$plugname.'_Oder5'} = knx_read($Oder5GA,300,1);
}

#Oder-Funktion
if (($plugin_info{$plugname.'_Oder1'} == 1) || ($plugin_info{$plugname.'_Oder2'} == 1) || ($plugin_info{$plugname.'_Oder3'} == 1) || ($plugin_info{$plugname.'_Oder4'} == 1) || ($plugin_info{$plugname.'_Oder5'} == 1)) {
	knx_write($AusgangOderGA,1,1);
	$plugin_info{$plugname.'_Ausgang'} = 1;
} else {
	knx_write($AusgangOderGA,0,1);
	$plugin_info{$plugname.'_Ausgang'} = 0;
}

return;