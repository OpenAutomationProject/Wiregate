##########################################################

#################################################################
# do not change anything below, all config stays above
#################################################################
## GA´s
my $Garage_zu ='14/0/1';
my $Garage_zu_rueck = '14/0/4';
my $Garage_auf = '14/0/0';
my $Garage_auf_rueck = '14/0/3';
my $Garage_schalten = '14/0/6';


# subscribe plugin and call it only when necessary, script will be activated if telegrams to the deffined GA are send.
$plugin_subscribe{$Garage_zu}{$plugname} = 1;
$plugin_subscribe{$Garage_auf}{$plugname} = 1;
$plugin_subscribe{$Garage_zu_rueck}{$plugname} = 1;
$plugin_subscribe{$Garage_auf_rueck}{$plugname} = 1;
$plugin_info{$plugname.'_cycle'} = 0;



 
 
 
## tor zu
     if (($msg{'dst'} eq ($Garage_zu)) && ($msg{'apci'} eq 'A_GroupValue_Write'))
     {
      ## Status der GA´s holen
     my $status = knx_read($Garage_zu_rueck,0,1);
   
          if (($msg{'value'} == 01) && ($status == 00)) {
         knx_write($Garage_schalten,1,1);
          return "zu";
          }
          if (($msg{'value'} == 01) && ($status == 01)) {
         knx_write($Garage_zu,0,1);
          return "zu";
          }
    
   else {
          return;
     }}
# zu reset
   if (($msg{'dst'} eq ($Garage_zu_rueck)) && ($msg{'apci'} eq 'A_GroupValue_Write'))  
	{
	my $garage_soll = knx_read($Garage_zu,0,1);
	
	 if (($msg{'data'} == 01) && ($garage_soll == 01)) {
	 knx_write($Garage_zu ,0,1);
	}
	if (($msg{'data'} == 01) && ($garage_soll == 00)) {
	 knx_write($Garage_schalten ,1,1);
	}
	
	}

## auf reset 
	if (($msg{'dst'} eq ($Garage_auf_rueck)) && ($msg{'apci'} eq 'A_GroupValue_Write'))  
	{
	my $garage_soll = knx_read($Garage_auf,0,1);
	
	 if (($msg{'data'} == 01) && ($garage_soll == 01)) {
	 knx_write($Garage_auf ,0,1);
	}
	if (($msg{'data'} == 01) && ($garage_soll == 00)) {
	 knx_write($Garage_schalten ,1,1);}
	 
	}
	
## tor auf
if (($msg{'dst'} eq ($Garage_auf)) && ($msg{'apci'} eq 'A_GroupValue_Write'))
     {
      ## Status der GA´s holen
     my $status = knx_read($Garage_auf_rueck,0,1);
     
     
          if (($msg{'value'} == 01) && ($status == 00)) {
         knx_write($Garage_schalten,1,1);
          return "auf";
          }
          
           if (($msg{'value'} == 01) && ($status == 01)) {
         knx_write($Garage_auf,0,1);
          return "auf";
          }
         
      else {
          return;
     }
     }
   