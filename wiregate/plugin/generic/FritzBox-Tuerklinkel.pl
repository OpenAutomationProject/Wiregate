#######################
# Fritz-Box GA-Wähler #
#######################
# Wiregate-Plugin
# (c) 2012 Amaridian under the GNU Public License
#
# Das Plugin löst bei einer 1 auf der definierten Gruppenadresse auf der 
# definierten FritzBox einen Anruf aus. Anruf-Absender und Empfänger können 
# dabei beide konfiguriert werden.
#

use LWP;
use Digest::MD5 'md5_hex';

# Definitionen
my $klingel_ga = "1/2/3";
my $fritz_ip = '192.168.2.1';
my $fritz_pw  = '0815';
my $call_from = '50'; #50 ist die vordefinierte Rundruf-Nummer
my $call_to = '**1'; #beliebige Nummer, für intern ** vorwählen

# Plugin an Gruppenadresse "anmelden"
$plugin_subscribe{$klingel_ga}{$plugname} = 1;
$plugin_info{$plugname.'_cycle'} = 0;

# Nur bei einer gesendeten 1 reagieren
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $klingel_ga) { 
	if (int($msg{'data'}) == 1 ) {
		
		# Login-Challenge und evtl. vorhandene Session-ID holen		
		my $user_agent = LWP::UserAgent->new;
		my $http_response = $user_agent->post('http://'.$fritz_ip.'/cgi-bin/webcm',
			[
				'getpage'	=> '../html/login_sid.xml',
				'sid'		=> defined($plugin_info{$plugname.'_sid'}) ? $plugin_info{$plugname.'_sid'} : '0',
			],
		);
		$http_response->content =~ /<SID>(\w+)<\/SID>\s*<Challenge>(\w+)<\/Challenge>/i and my $sid = $1 and my $challengeStr = $2;
				
		# Wenn noch eine gültige Session da ist, nehmen wir die
		if($sid eq '0000000000000000'){		
			# Challenge zusammen mit PW hashen laut http://www.avm.de/de/Extern/files/session_id/AVM_Technical_Note_-_Session_ID.pdf
			my $ch_Pw = "$challengeStr-$fritz_pw";
			$ch_Pw =~ s/(.)/$1 . chr(0)/eg;
			my $md5 = lc(md5_hex($ch_Pw)); #warum auch immer AVM hier UTF16LE haben möchte...
			my $challenge_response = "$challengeStr-$md5";
		
			# Mit der frisch errechneten Challenge-Response die Session-ID abholen
			$http_response = $user_agent->post('http://'.$fritz_ip.'/cgi-bin/webcm',			[
					"login:command/response" 	 => $challenge_response,
					'getpage'			 => '../html/de/menus/menu2.html',
				],
			);		
			$http_response->content =~ /<input type="hidden" name="sid" value="(\w+)" id="uiPostSid">/i and $sid = $1;
			$plugin_info{$plugname.'_sid'} = $sid;
		}
		
		# den gewünschten Wählbefehl absetzen
		$http_response = $user_agent->post('http://'.$fritz_ip.'/cgi-bin/webcm',
			[
				'getpage'	=> '../html/login_sid.xml',
				'sid'	=> $sid,
				'telcfg:settings/UseClickToDial' => 1,
	   			'telcfg:command/Dial'            => $call_to,
	   			'telcfg:settings/DialPort'       => $call_from,
			],
		);
		return " Klingel betätigt und Ruf abgesetzt"
	}
}