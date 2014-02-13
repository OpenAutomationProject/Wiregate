# http://knx-user-forum.de/wiregate/33115-anwesenheitssimu.html
# by uxtuner (Uwe)

use Time::Local;

$plugin_info{$plugname.'_cycle'} = 60;   # Aufruf Zyklus auf 120s setzen

my @ga = qw(4/0/0 4/4/4 1/1/1 1/1/12 1/1/18 1/1/8);  # Diese GAs werden geschalten

my $starttime = "18:30:00";               # Beginn Simulation
my $durationmin = "240";                  # Ende der Simulation nach xxx Minuten

my $holidaystart = "13.02.2014 00:00:00"; # In dieser Zeit Simu
my $holidayend   = "16.02.2014 23:59:00"; # In dieser Zeit Simu
my $weekdaystart = "1,2..4";              # Falls kein Urlaub, trotzdem an diesen Tagen die Simu starten (Mon => "1"  So => "7")

my ($second, $minute, $hour, $dayOfMonth, $month, $year, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings);
my ($timestamp, $datestamp, $isTime, $isSimuDay, $isHoliday, $endtime, $switchofftime, $currentunix, $u_starttime);
my ($wuerfel,$msg,$status);

########################
sub get_time() {
########################

  ($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();

  $year = 1900 + $yearOffset;
  $month = $month+1;
  $minute = "0".$minute if ($minute < 10);
  $hour = "0".$hour if ($hour < 10);
  $month = "0".$month if ($month < 10);
  $dayOfMonth = "0".$dayOfMonth if ($dayOfMonth < 10);

  $timestamp = "$year$month$dayOfMonth $hour:$minute:$second";
  $datestamp = "$dayOfMonth.$month.$year $hour:$minute:$second";

  $u_starttime = &unixdatum("$dayOfMonth.$month.$year $starttime");
  $durationmin *= 60;
  $endtime = ($u_starttime+$durationmin);
  $switchofftime = ($endtime-2*$plugin_info{$plugname.'_cycle'});

}

########################
sub unixdatum() {
########################

  my $dvalue = "@_";

  my ($datum,$uhrzeit) = split(/ /,$dvalue);
  my ($tag,$monat,$jahr)=split(/\./,$datum);
  my ($std,$min,$sek)  = split(/:/,$uhrzeit);
  my $unixtime = timelocal($sek,$min,$std,$tag,$monat,$jahr);

  return $unixtime;

}

########################
sub check_start() {
########################

  my @weekarray=eval $weekdaystart;
  $currentunix=&unixdatum($datestamp);

  $isTime = "true" if (($currentunix ge $u_starttime) and ($currentunix le $endtime));

  foreach my $weekarray (@weekarray) {
    next unless ($weekarray eq $dayOfWeek);  
    $isSimuDay="true";
  }  

  if  (( &unixdatum($datestamp) ge &unixdatum($holidaystart) ) and ( &unixdatum($datestamp) le &unixdatum($holidayend) )) {
        $isHoliday = "true";               
  }           

}

########################
sub switch_on_off() {
########################
  my $action = "@_";

  my $anz_ga = $#ga;
  my $number = int(rand $anz_ga+1);
  my $random_ga = $ga[$number];

  foreach my $current_ga (@ga) {     

      ###### alle ausschalten
      if ( $action eq "off" ) {;
            knx_write($current_ga,0,1);
            $msg="switching all off ...";
            next;
      }

      ###### random an-/ausschalten
      if ( ("$current_ga" eq "$random_ga") and ($action eq "random") ) {
             my $laststate = knx_read($current_ga,3600,1);
             knx_write($current_ga,0,1) if ($laststate eq "1");
             $msg="switching $current_ga off ..." if ($laststate eq "1");
             knx_write($current_ga,1,1) if ($laststate eq "0");
             $msg="switching $current_ga on ..." if ($laststate eq "0");
      }
  }  

}

###################################
# MAIN
###################################

&get_time;
&check_start;
#print "isSimuDay: $isSimuDay \nisHoliday: $isHoliday \nisTime:    $isTime \n"; 

$status = "active";

if ( ($isSimuDay ne "true") and ($isHoliday ne "true") ) {
    $msg = "inactive ...";
    $status = "inactiv";
}

if ($isTime ne "true") {
    $msg =  "active today at $starttime ...";
    $status = "inactiv";
}             

if ($currentunix ge $switchofftime) {
    &switch_on_off("off") if ($status eq "active");
} elsif ($status eq "active") {
    # Zufallszahl zwischen 0 und 5 erzeugen, je hoeher die random zahl desto seltener wird geschalten
    $wuerfel = int(rand 6);            
    if ($wuerfel eq "0") {
       &switch_on_off("random");
    } else {
       $msg="active ...";
    }         
}

print "$msg \n";
return $msg;

