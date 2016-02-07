# WireGate Plugin 1-Wire Monitor
# Monitor 1-Wire Bus and record new / deleted sensors in rsslog database
# Use with WireGate & CometVisu to display 1-Wire bus status
#
# V0.4 by Dirk Hedderich / http://knx-user-forum.de/members/dirk42.html
# Use at your own risk and under terms of GPLv2
#
# Please change config.d/1-Wire Monitor.conf to configure this tool
#

# COMPILE_PLUGIN

### Start Main Routine ###

my $PluginCycle = 0;
my $RssLog = '';
my $OWFS = '';
my $OWFS_Output = '';
my $ShowIButtons = 0;
my $Result = '';


# Read configuration conf.d/1-Wire Monitor.conf
# From swiss' "ComfoAir Steuerung ueber RS232"
# http://knx-user-forum.de/code-schnipsel/21359-comfoair-steuerung-ueber-rs232.html
my $confFile = '/etc/wiregate/plugin/generic/conf.d/'.basename($plugname,'.pl').'.conf';
if (! -f $confFile)
{
	plugin_log($plugname, " no conf file [$confFile] found."); 
}
else
{
	# plugin_log($plugname, " reading conf file [$confFile]."); 
	open(CONF, $confFile);
	my @lines = <CONF>;
	close($confFile);
	my $result = eval("@lines");
	# ($result) and plugin_log($plugname, "conf file [$confFile] returned result[$result]");
	if ($@) 
	{
		plugin_log($plugname, " conf file [$confFile] returned:");
		my @parts = split(/\n/, $@);
		plugin_log($plugname, " --> $_") foreach (@parts);
	}
}


# Set PlugIn cycle in seconds
$plugin_info{$plugname.'_cycle'} = $PluginCycle;
my $Info = "";
if ($PluginCycle < 300) { $Info = "NOT4PROD! " };

# Did the size of the OWFS output change?
my $FileSize = -s $OWFS_Output;
my $OldFileSize = $plugin_info{$plugname.'_FileSize'};

#$OldFileSize += 1;    # For testing...

# OWFS output filesize did not change - so just download new output
if (($FileSize == 0) || ($OldFileSize eq $FileSize)) { goto WGET_OWFS }

plugin_log($plugname,$Info . " Old size: $OldFileSize - new size: $FileSize");
$plugin_info{$plugname.'_FileSize'} = $FileSize;

# Now analyse the OWFS output
# Since the OWFS output is simple & stable we analyse it with
# regular expressions
open FILEHANDLE, $OWFS_Output or die $!;
my $Output = do { local $/; <FILEHANDLE> };

# Check if the file is corrupt / file should end with </HTML>
if ($Output !~ /\<\/HTML\>$/)
{
    $Result = "ERROR: OWFS Output corrupt - increase cycle?";
    plugin_log($plugname,$Info . $Result);
    # Write this also to rsslog database
    system("wget", "--tries", "1", "--timeout", "30", "-O", "-", "$RssLog?c=$Result&t[]=1-Wire, Error");
    goto WGET_OWFS;
}

my @SensorLinks = ($Output =~ /(?:<A HREF='\/uncached\/)([0-9A-F]{2})(?:.)/g);

# Count number of occurences for each sensor type
my %CountHash;
map { $CountHash{$_}++ } @SensorLinks;

# Analyse the count
my $Sensors_DS1420 = 0;        # Busmaster (81)
my $Sensors_DS1820 = 0;        # Temp (10 / 28)
my $Sensors_DS1990 = 0;        # iButton (01)
my $Sensors_DS2413 = 0;        # I/O (3A)
my $Sensors_DS2431 = 0;        # Professional Busmaster (2D) (3 sensors per PBM)
my $Sensors_DS2433 = 0;        # EEPROM (23) (e.g. used in WireGate PBM / Koppler)
my $Sensors_DS2438 = 0;        # Multi (26) (Smart Battery Monitor, used for e.g. temperature, humidity, voltage, EEPROM )
my $Sensors_Other = "";
      
# Sorted loop over all sensor codes
for my $SensorCode(sort keys %CountHash)
{
    my $SensorCount = $CountHash{$SensorCode};

    given ($SensorCode)
    {
        when ("01") { $Sensors_DS1990 = $SensorCount }
        when ("10") { $Sensors_DS1820 += $SensorCount }	# 10 and 28 are both DS1820 variants
		when ("23") { $Sensors_DS2433 = $SensorCount }
		when ("26") { $Sensors_DS2438 = $SensorCount }
		when ("28") { $Sensors_DS1820 += $SensorCount } # 10 and 28 are both DS1820 variants
        when ("2D") { $Sensors_DS2431 = $SensorCount }
        when ("3A") { $Sensors_DS2413 = $SensorCount }
        when ("81") { $Sensors_DS1420 = $SensorCount }
        
        default { $Sensors_Other = "$SensorCode: $SensorCount, " }
    }    
}

# Build result string
$Result = "";
if ($Sensors_DS1420 > 0) { $Result .= "Busmaster (DS1420): $Sensors_DS1420, " }
if ($Sensors_DS1820 > 0) { $Result .= "Temp (DS1820): $Sensors_DS1820, " }
if ($Sensors_DS2413 > 0) { $Result .= "I/O (DS2413): $Sensors_DS2413, " }
if ($Sensors_DS2431 > 0) { $Result .= "P-Busmaster (DS2431): $Sensors_DS2431, " }
if ($Sensors_DS2433 > 0) { $Result .= "EEPROM (DS2433): $Sensors_DS2433, " }
if (($ShowIButtons)&&($Sensors_DS1990 > 0)) { $Result .= "iButton (DS1990): $Sensors_DS1990, " }
if ($Sensors_DS2438 > 0) { $Result .= "Multi (DS2438): $Sensors_DS2438, " }
if ($Sensors_Other ne "") { $Result .= "Other: $Sensors_Other"; }        
$Result =~ s/,\s+$//;

# If iButtons are ignored: Check if only the iButtons changed
if (!$ShowIButtons)
{
    plugin_log($plugname, $Info . " Ignore iButtons!");
    
    if ($Result eq $plugin_info{$plugname.'_SensorList'})
    {
        goto WGET_OWFS;
    }
    $plugin_info{$plugname.'_SensorList'} = $Result;
}

# Write result to rsslog database
system("wget", "--tries", "1", "--timeout", "30", "-O", "-", "$RssLog?c=$Result&t[]=1-Wire");
plugin_log($plugname, $Info . " $Result");


WGET_OWFS:
# OWFS status is retrieved asynchronous since the response might take
# longer than allowed for WireGate plugins
# --tries=1 - Only try to download once
# --timeout 30 seconds
# --output-document: Write OWFS output to file set in $OWFS_Output
system("wget", "--tries", "1", "--timeout", "30", "--output-document",$OWFS_Output, $OWFS);

return $Result;
