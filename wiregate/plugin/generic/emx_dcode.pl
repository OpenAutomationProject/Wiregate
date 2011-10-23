# Plugin zur Erkennung eines Tastencodes
# License: GPL (v2)
# version von emax
#
# $Id$
#
# Das Plugin analysiert die Ereignisse einer gegebenen GA, und wertet die 
# Zeitabstaende zwischen den Telegrammen aus. Je nach erkanntem Muster wird 
# eine vorgegebene Funktion ausgefuehrt.
#
# Das Plugin ist z.B. als Notbehelf im Falle einer zugefallen Haustuer 
# gedacht.
#
# Funktionsweise:
# ---------------
# Mit jedem erkannten Tastendruck wird ein Zaehler inkrementiert, sofern der 
# letzte Tastendruck der betreffenden GA nicht laenger her ist als eine Sekunde
# (einstellbar). Wird eine Pause von mehr als einer Sekunde erkannt, wird 
# der Wert des Zaehlers gespeichert, und der Zaehler auf Null gesetzt.
# Entsprechen die so gesammelten Werte einem bestimmten Code, wird eine 
# vorgegebene Funktion ausgefuehrt.
#
# Auf diese Weise laesst sich jeder Lichtschalter z.B. als Tueroeffner 
# verwenden, wenn er in einem bestimmten Muster gedrueckt wird.
#
# Beispiel:
# - Taster wird drei mal kurz hintereinander gedrueckt
# - ueber eine Sekunde Pause
# - Taster wird vier mal kurz hintereinander gedrueckt
# - ueber eine Sekunde Pause
# - Taster wird fuenf mal kurz hintereinander gedrueckt
# - ueber eine Sekunde Pause
#
# wird dekodiert zu '345'. 10 Tastendruecke entsprechen einer '0', mehr als 10 
# Tastendruecke werden als Falscheingabe gewertet.
#
# Wird eine Pause von mehr als vier (einstellbar) Sekunden gemacht, wird der 
# Code als vollstaendig angesehen und ausgewertet. Nach der Auswertung werden 
# alle Zaehler wieder auf Null gesetzt, und von vorne begonnen.
#
# Nach drei Falscheingaben (einstellbar) wird die Auswertung fuer eine Minute 
# (einstellbar) blockiert. Nach jeder weiteren Falscheingabe verdoppelt sich 
# die Blockadezeit.
#
# Die GA kann weiterhin fuer andere Aufgaben verwendet werden, da das Script 
# nur zusammenhaengenede Eingaben auswertet, und Einzeleingaben ignoriert.
#
# Copyright: Edgar (emax) Hermanns, forum at hermanns punkt net
#--------------------------------------------------------------------
#  CHANGE LOG:
#  ##  who  yyyymmdd   bug#  description
#  --  ---  --------  -----  ----------------------------------------
#   .  ...  ........  .....  vorlage 
#   0  edh  20111023  -----  erste Version

use POSIX;

#-----------------------------------------------------------------------------
# Defaults fuer konfigurierbare Werte, siehe conf.d/emx_dcode.conf
#-----------------------------------------------------------------------------

my $pauseSec       = 1.0;  # Pausenzeit, nach der eine Ziffer komplett ist
my $completeAfter  = 4;    # Wartezeit in Sekunden, nach der der Code ausgewertet wird
my $maxFails       = 3;    # Anzahl Fehlversuche
my $blockPeriod    = 30;   # anfaengliche Blockadezeit in Sekunden.
my $maxBlockPeriod = 3600; # maximale Blockadezeit

my @Codes = ();

#-----------------------------------------------------------------------------
# ENDE Einstellungen
#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# ACHTUNG: die Versionsnummer IMMER veraendern, wenn das script geaendert wurde.
# Der Wert muss numerisch sein, egal ob hoeher oder niedriger als die
# Vorversion. Es ist auch egal, ob die Version bereits verwendet wurde,
# es kommt nur darauf an, das der Wert sich AENDERT.
#-----------------------------------------------------------------------------
my $version = 3;
my $oneDay         = (24 * 3600);

use POSIX;
my $dbg = ''; # :dJ:'; # ':ALL:dSS:dWS:dBS:state:code:cycle:counter:msg:cC:dJ:'; # ALL:alles, 
my %varInit =  (initialized=>1, lastRun=>0, blockEnd=>0, curBlockPeriod=>0, curCode=>'', fails=>0, state=>'sleeping');
my ($seconds, $uSec, $tStamp, $state, $lastRun, $dTime, $piPrefix, $minCodeLength);


sub debug()
{
    my ($tag, $text) = (@_);
    my $caller = (caller(1))[3];
    ($dbg =~ /:ALL:|$tag/) and plugin_log($plugname, "DBG$tag$caller:"."$text");
    return 1;
} # debug()

sub readConf
{
    my $confFile = '/etc/wiregate/plugin/generic/conf.d/'.basename($plugname,'.pl').'.conf';
    if (! -f $confFile)
    {
        plugin_log($plugname, " no conf file [$confFile] found."); 
    }
    else
    {
        plugin_log($plugname, " reading conf file [$confFile]."); 
        open(CONF, $confFile);
        my @lines = <CONF>;
        close($confFile);
        my $result = eval("@lines");
        ($result) and plugin_log($plugname, "conf file [$confFile] returned result[$result]");
        if ($@) 
        {
            plugin_log($plugname, "conf file [$confFile] returned:");
            my @parts = split(/\n/, $@);
            plugin_log($plugname, "--> $_") foreach (@parts);
        }
    }
} # readConf

sub doInit
{
    &debug(':DFR:', 'entering');

    # Kontrollierte Startkonditionen setzen
    # Die Funktion wird aufgerufen, wenn es der erste Lauf einer Plugin-Version 
    # ist. Es werden alle Werte aus alten Versionen aus %plugin_info geloescht. 
    # "$plugname.$version.initialized" wird gesetzt, und auch alle anderen
    # kuenftig verwendeten plugin_info-Variablen angelegt.

    plugin_log($plugname, "Starting plugin version $version.");

    # obsolete Versionen von $plugin_info bereinigen
    foreach (keys %plugin_info)
    {
        if (/^$plugname\.\d+\./)
        {
            delete $plugin_info{$_};
            plugin_log($plugname, "deleted obsolete plugin_info[$_]");
        }
    }

    # Variablen zuruecksetzen
    &reset();

    # Die minimale Codelaenge wird unten ermittelt. 
    # Kuerzere Codes werden verworfen.
    $minCodeLength = 999; 

    foreach my $code (@Codes)
    {
        if (defined $code->{FromGA})
        {
            if (defined $code->{FromGA} && defined $code->{ToGA} &&
                $code->{FromGA} eq $code->{ToGA})
            {
                plugin_log($plugname, "ERROR: source GA[$code->{FromGA}] and destination GA[$code->{FromGA}] are the same, entry ignored.");
                next;
            }

            my $GA = $code->{FromGA};

            if (defined $code->{Active} &&
                $code->{Active} == 1)
            {
                plugin_log($plugname, "subscribing to GA[$GA]");
                $plugin_subscribe{$GA}{$plugname} = 1;

                # Ermitteln der minimalen Code-laenge. 
                # Alle codes, die kuerzer sind, werden ignoriert,
                # und fuehren auch nicht zu Fehlern.                
                (length($code->{Code}) < $minCodeLength) and $minCodeLength = length($code->{Code});                 
            }
            elsif (exists $plugin_subscribe{$GA}{$plugname})
            {
                plugin_log($plugname, "deleting obsolete subscription to GA[$GA]");
                delete $plugin_subscribe{$GA}{$plugname};
            }
        } # defined FromGA
    } # each $code

    $plugin_info{"$piPrefix.minCodeLength"} = $minCodeLength;
        
    # debug
    if ($dbg =~/:ALL:|:dFR:/) 
    {
        foreach (keys %plugin_subscribe)
        {
            &debug(':DFR:', "pluginSubscribeKey[$_]");
        }
    } # debug     
    $plugin_info{$plugname.'_cycle'} = $oneDay;
} # doFirstFRun

sub setBlockingPeriod()
{
    &debug(":sBT:", "entering");
    my $fails = $plugin_info{"$piPrefix.fails"} + 1;
    plugin_log($plugname, "invalid code #[$fails]");
    $plugin_info{"$piPrefix.fails"} = $fails;
    if ($fails >= $maxFails)
    {
        my $curBlockPeriod = $plugin_info{"$piPrefix.curBlockPeriod"};
        my $newBlockPeriod = ($curBlockPeriod == 0) ? $blockPeriod : $curBlockPeriod + $curBlockPeriod;
        ($newBlockPeriod > $maxBlockPeriod) and $newBlockPeriod = $maxBlockPeriod;
        plugin_log($plugname, "setting blocking period for GA[".$plugin_info{"$piPrefix.GA"}.
                   " from [$curBlockPeriod] sec to [$newBlockPeriod] sec");
        $plugin_info{"$piPrefix.curBlockPeriod"} = $newBlockPeriod;        
        $plugin_info{"$piPrefix.blockEnd"} = $tStamp + $newBlockPeriod;
        $plugin_info{"$piPrefix.state"} = 'blocked';
        ($plugin_info{"$plugname".'_cycle'} < $newBlockPeriod) and $plugin_info{"$plugname".'_cycle'} = $newBlockPeriod;
    }
    else 
    { 
        # Wenn die maximale Anzahl Fehleingaben noch nicht erreicht wurde,
        # werden diese Variablen zurueckgesetzt.
        $plugin_info{"$piPrefix.curCode"} = '';
        $plugin_info{"$piPrefix.state"} = 'sleeping';
        $plugin_info{"$plugname".'_cycle'} = $oneDay;        
   }
} # setBlockingPeriod

sub checkCode()
{
    &debug(':cC:', 'entering');
    # Es werden alle %Codes Eintraege auf einen passenden code ueberprueft.
    # Da meherere Codes je GA verarbeitet werden koennen, ist der Eintrag 
    # abhaengig von
    # - sendender GA
    # - ermitteltem Code
    # Wenn diese beiden Werte uebereinstimmen, wird der %Codes-Eintrag zurueckgegeben.
    # Stimmt kein Eintrag ueberein, wird 'undef' zurueckgegeben.

    my $curCode = $plugin_info{"$piPrefix.curCode"};
    &debug(':cC:', "curCode[$curCode]");
    my $idx = -1;
    foreach my $code (@Codes)
    {
        ++$idx;
        if (defined $code->{FromGA} && defined $code->{ToGA} &&
            $code->{FromGA} eq $code->{ToGA})
        {
            plugin_log($plugname, "ERROR: source GA[$code->{FromGA}]and destination GA[$code->{FromGA}] are the same, entry ignored.");
            next;
        }

        (!defined $code->{Active} || !$code->{Active}) and 
            &debug("cC:", "not Active") and next;
        (!defined $code->{Code} ||    $code->{Code} ne $plugin_info{"$piPrefix.curCode"}) 
            and &debug("cC:", "no Code") and next;
        (!defined $code->{FromGA} ||  $code->{FromGA} ne $plugin_info{"$piPrefix.GA"}) 
            and &debug("cC:", "not FromGA")and next;
        (defined $code->{FromPA} &&  $code->{FromPA} ne $plugin_info{"$piPrefix.PA"}) 
            and &debug("cC:", "not FromPA")and next;
        &debug(':cC:', "found Code[$curCode]");
        return $idx;
    }
    return undef;
}

sub doJob()
{
    &debug(':dJ:', 'entering');
    my $codeIdx = shift;
    my $codeCount = @Codes;

    &debug(":dJ:", "codeCount[$codeCount]");
    
    # Hier werden alle %Codes ausgefuehrt, die den aktuellen parametern entsprechen.
    # Es koennen hinterainander mehrere Kommandos fuer den gleichen Code ausfuehrt
    # werden. Ebenso unterschiedliche Kommandos vom gleichenm Taster, je nach Code.

    for (; $codeIdx < $codeCount; ++$codeIdx)
    {
        # es werden alle Eintraege verarbeitet, die dem Filter entsprechen
        my $code = $Codes[$codeIdx];
        (!defined $code->{Active} || !$code->{Active}) and next;
        (!defined $code->{Code} ||    $code->{Code} ne $plugin_info{"$piPrefix.curCode"}) and next;
        (!defined $code->{FromGA} ||  $code->{FromGA} ne $plugin_info{"$piPrefix.GA"}) and next;
        (defined $code->{FromPA} &&  $code->{FromPA} ne $plugin_info{"$piPrefix.PA"}) and next;
        (defined $code->{Log} && $code->{Log}) and 
            plugin_log($plugname, 'executing from PA['.$plugin_info{"$piPrefix.PA"}.
                       '] From GA['.$plugin_info{"$piPrefix.GA"}.
                       '], sending ['.$code->{Value}.
                       '] to  ['.$code->{ToGA}.'].');
        knx_write($code->{ToGA},$code->{Value}, $code->{DPT});
    }
} # doJob

sub reset()
{
    &debug(':RES:', 'entering');
    # Alle Variablen und '$state' zuruecksetzen
    foreach (keys %varInit)
    {
        &debug(':RES:',"(re)setting [$piPrefix.$_] to [$varInit{$_}]");
	$plugin_info{"$piPrefix.$_"} = $varInit{$_} 
    }

    $plugin_info{"$plugname".'_cycle'} = $oneDay;
} # reset()

sub doSleepingState()
{
    &debug(':dSS:', 'entering');
    $plugin_info{"$piPrefix.lastRun"} = $tStamp;

    # Wird ausgefuehrt, wenn das Plugin das erste Mal getriggert wird nach
    # - der Initialisierung
    # - einem vollstaendigen Code oder
    # - dem Status 'blocked'

    # Wenn keine GA geliefert wurde, geschah der Aufruf aufgrund eines _cycle Timeouts.
    # Dann ist nichts weiter zu tun.
    if (!defined $msg{'dst'}) 
    {
        # refresh _cycle
        $plugin_info{"$plugname".'_cycle'} = $oneDay;
        return;
    };

    &debug(':dSS:', 'setting GA/PA filters');

    # GA & PA merken.
    # Bis der Code vollstaendig ist, werden nur noch Telegramme dieser GA und von 
    # dieser PA ausgwertet. Alle anderen telegramme werden so lange ingnoriert.
    $plugin_info{"$piPrefix.GA"} = $msg{'dst'};
    $plugin_info{"$piPrefix.PA"} = $msg{'src'};
    $plugin_info{"$piPrefix.counter"} = 1;
    $plugin_info{"$piPrefix.curCode"} = '';
    $plugin_info{"$plugname".'_cycle'} = $completeAfter;
    $plugin_info{"$piPrefix.state"} = 'waiting';
} # doSleepingState

sub doWaitingState()
{
    &debug(':dWS:', 'entering');
    
    # errechne abgelaufene Zeit
    $lastRun =  $plugin_info{"$piPrefix.lastRun"};
    $dTime = $tStamp - $lastRun;
    &debug(':dWS:', "dTime[$dTime]");

    if (!defined $msg{'dst'})
    {
        &debug(':dWS:', 'no GA');
        if ($dTime < $pauseSec)
        {
            # Aus einem mir unbekannten Grunde passiert es, dass
            # das Script aufgerufen wird, ohne das eine GA geliefert wird,
            # obwohl kein _cycle Timeout stattfand.
            # Solche Ereignisse werden ignoriert.
            return;
        }

        $plugin_info{"$piPrefix.lastRun"} = $tStamp;

        # Keine GA, aber _cycle Timeout
        # Wenn zwischenzeitlich Tastendruecke gezaehlt wurden, 
        # diese zum Code hinzufuegen.
        if ($plugin_info{"$piPrefix.counter"})
        {
            ($plugin_info{"$piPrefix.counter"} == 10) and $plugin_info{"$piPrefix.counter"} = 0;
            $plugin_info{"$piPrefix.curCode"} .= $plugin_info{"$piPrefix.counter"};
            $plugin_info{"$piPrefix.counter"} = 0;
            plugin_log($plugname, 'current code['.$plugin_info{"$piPrefix.curCode"}.']');
        }

        &debug(':dWS:', "curCode[".$plugin_info{"$piPrefix.curCode"}.']');
        if (length($plugin_info{"$piPrefix.curCode"} < $minCodeLength))
        {
            plugin_log($plugname, 'code too short, discarded.');
            &reset();
            return;
        }

        my $codeIdx = &checkCode();
        if (defined $codeIdx)
        {
            plugin_log($plugname, 'code accepted.');
            &doJob($codeIdx);
            &reset();
        }
        else
        {
            plugin_log($plugname, 'code rejected.');
            &setBlockingPeriod();
        }
        return;
    } # ... no GA 

    $plugin_info{"$piPrefix.lastRun"} = $tStamp;

    # Ein GA-Event
    # Ausfiltern, sofern nicht die aktuelle GA oder nicht von der gleichen PA
    if ($msg{'dst'} ne $plugin_info{"$piPrefix.GA"} ||
        $msg{'src'} ne $plugin_info{"$piPrefix.PA"})
    {
        # Das Event wird ignoriert.
        # Verwerfen und neue _cycle zeit ausrechnen, damit der naechste 
        # Aufruf zum (halbwegs) richtigen Zeitpunkt stattfindet.
        $plugin_info{$plugname.'_cycle'} = $completeAfter - $dTime;
        return;
    }

    # Das Ereignis kam von 'unserer' Quelle und ist fuer 'unsere' Zieladresse.
    if ($dTime < $pauseSec)
    {
        if ($plugin_info{"$piPrefix.counter"} == 10)
        {
            # error
            &debug(':dWS:', "counter too big[".$plugin_info{"$piPrefix.counter"}.']');
            &setBlockingPeriod();
        }
        else
        { 
            ++$plugin_info{"$piPrefix.counter"};
        }
        return;
    }
    else       # Pause entdeckt
    {
        &debug(':dWS:', 'pause detected, counter is '.$plugin_info{"$piPrefix.counter"});
        # sofern zwischenzeitlich Ereignisse gezaehlt wurde, diese dem Code 
        # hinzufuegen und den Zaehler zuruecksetzen.
        if ($plugin_info{"$piPrefix.counter"})
        {
            &debug(':dWS:', "assembling code");
            ($plugin_info{"$piPrefix.counter"} == 10) and $plugin_info{"$piPrefix.counter"} = 0;
            $plugin_info{"$piPrefix.curCode"} .= $plugin_info{"$piPrefix.counter"};
            plugin_log($plugname, 'current code['.$plugin_info{"$piPrefix.curCode"}.']');
        }
        $plugin_info{"$piPrefix.counter"} = 1;
        &debug(':dWS:', "after pause curCode[".$plugin_info{"$piPrefix.curCode"}.']');
    }
} # doWaitingState

sub doBlockedState()
{
    &debug(':dBS:', 'entering');
    $plugin_info{"$piPrefix.lastRun"} = $tStamp;

    if ($tStamp >= $plugin_info{"$piPrefix.blockEnd"})
    {
        plugin_log($plugname, 'blocking time expired, going to sleep');
        &debug(':dBS:', 'blocking time expired, resetting block');
        $plugin_info{"$piPrefix.curCode"} = '';
        $plugin_info{"$piPrefix.state"} = 'sleeping';
        $plugin_info{"$plugname".'_cycle'} = $oneDay;
    }
} # doBlockedState

#=============================================================================
# main() 
#=============================================================================

&readConf();

($seconds,$uSec) = gettimeofday();
$tStamp = $seconds + $uSec/1000000; 
$lastRun = 0;
$piPrefix = "$plugname.$version";

my $oldCycleTime = $plugin_info{"$plugname".'_cycle'};
$minCodeLength = $plugin_info{"$piPrefix.minCodeLength"};

# ggf. neue Version initialiseren
if (!defined $plugin_info{"$piPrefix.initialized"})
{
    &doInit();
    return;
}

$state = $plugin_info{"$piPrefix.state"};
&debug(':state:', "on entry state[$state]");

&debug(':msg:', "msg debug -------------");
&debug(':msg:', "msg[$_]=$msg{$_}") foreach (keys %msg);
&debug(':msg:', "/msg debug ------------");

if    ($state eq 'sleeping') { &doSleepingState(); } 
elsif ($state eq 'waiting')  { &doWaitingState();  }
elsif ($state eq 'blocked')  { &doBlockedState();  }
else { 
    plugin_log($plugname, "FATAL: unknown state[$state], resetting");
    &doInit();
}

&debug(':state:',   "on exit state[".$plugin_info{"$piPrefix.state"}.']');
&debug(':counter:', "on exit counter[".$plugin_info{"$piPrefix.counter"}.']');
&debug(':code:',    "on exit code[".$plugin_info{"$piPrefix.curCode"}.']');
&debug(':cycle:',   "on exit cycle[".$plugin_info{"$plugname".'_cycle'}.']');

($oldCycleTime != $plugin_info{"$plugname".'_cycle'}) and 
    plugin_log($plugname, 'cycle time set to '.$plugin_info{"$plugname".'_cycle'}.' seconds');
