#!/usr/bin/perl 

##########################################################################
#
# Script name : Git Deployer Server
# Author : 	Guillaume Seigneuret
# Date : 	16/01/12
# Last update : 18/04/13
# Type : 	Deamon
# Version : 	1.3.14
# Description : Receive hook trigger from Git and call the git deployer 
# script
#
# Usage : 	gds [-p pidfile] [-l logfile] [-d]
# 		-d for daemonize
#
##   Copyright (C) 2012-2013 Guillaume Seigneuret (Omega Cube)
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>
############################################################################

use strict;
use IO::Socket;
use Config::Auto;
use Data::Dumper;
use Getopt::Std;
use Proc::Daemon;
use Term::ANSIColor qw(:constants);
use lib qw(.);

my %opts	= ();
my $config 	= Config::Auto::parse();
my $ADDRESS 	= trim($config->{"engine-conf"}->{"listen"});
my $PORT 	= trim($config->{"engine-conf"}->{"port"});
my $PID_file	= trim($config->{"engine-conf"}->{"pidfile"});
my $LOG_file	= trim($config->{"engine-conf"}->{"logfile"});
my $gitdeployer = trim($config->{"engine-conf"}->{"git-deployer"});
my $debug 	= 0;
my $hostname	= trim($config->{"engine-conf"}->{"hostname"});
$debug 		= 1 if (trim($config->{"engine-conf"}->{"debug_mode"}) eq "on");


{
	# Autoflush
	$| = 1;
	local $Term::ANSIColor::AUTORESET = 1;

	# Get command line options
	getopts('dl:p:', \%opts);

	# Global vars for git-deploy
	our $_PROJECT   = "";
	our $_BRANCH	= "";

	$PID_file = $opts{p} if defined $opts{p};
	die "A git deployment server is already running\n" if(-e $PID_file);

	my $standard_out;

	if (defined $opts{d}) {
		Proc::Daemon::Init();
		
		# Write the PID file
		die "Unable to open $PID_file for writing" unless open (PIDf,">$PID_file");
		print PIDf $$;
		close(PIDf);

		# Open the log file
		$LOG_file = $opts{l} if defined $opts{l};
		chmod oct("0777"), $LOG_file;
		open(LOGFILE, ">>", $LOG_file) or die "Unable to open ".$LOG_file;
		$standard_out = select(LOGFILE);
	}

	my $server = IO::Socket::INET->new(
					LocalHost 	=> $ADDRESS,
					LocalPort	=> $PORT,
					Proto		=> 'tcp',			
					Listen		=> 10 )   # or SOMAXCONN
		or die "Couldn't be a tcp server on port $PORT : $@\n";

	print "GDS started, waiting for connections...\n";
	
	while (my $client = $server->accept()) {

		# Don't want zombie process just because we are bad parrents
		# and we don't care about our chidren :p
		$SIG{CHLD} = "IGNORE";

	        unless (my $masterpid = fork() ){
		       	# We are in the child
			#Child doesn't need the listner
			close ($server);
	  		printf "[%12s]", time;

			# Git is a precious child and he can't live without good parents ...
			# So our forked process will wait carefully for its own chidren.
			$SIG{CHLD} = undef;
			 
			print " Connection from: ".inet_ntoa($client->peeraddr)."\n";
			if($debug) {
				print $client "***********************************************\r\n";
                        	print $client "**               Welcome to GDS              **\r\n";
                        	print $client "***********************************************\r\n";
                        }
			print $client BOLD GREEN "[$hostname]: Connexion OK. please make your request.\r\n";

	  		while(my $rep = <$client>) {
			
				printf "[%12s] Asked to interpret : %s", time, $rep;

				if ( $rep =~ /^QUIT/i) {
					print $client BOLD GREEN "[$hostname]: ";				
					print $client "Bye!\n";
					close($client);
					print "\n*** Fin de connexion sur PID $$ ***\n";
				} 
				else {
					if($rep =~ /Project: .*\/([\w\-\.]+)\.git Branch: ([\w\-]+)/ 
						or $rep =~ /Project: ([\w\-\.]+)\.git Branch: ([\w\-]+)/) 
					{
						# Send the STDout to the client.
						$standard_out = select($client);

						if($debug) {
							print "Recognized Project : $1\r\n";
							print "Recognized Branch : $2\r\n";
						}
						print BOLD GREEN "[$hostname]: ";
						print BOLD WHITE "$1/$2\r\n";
						$_PROJECT 	= $1;
						$_BRANCH	= $2;

						# Launch git-deployer
						unless(-e $gitdeployer) {
							print "No git deployer found :( Check your config file.\n";
							# restore the stdout
							select($standard_out);
							close($client);
						}
						
						print BOLD GREEN "[$hostname]: ";
						print BOLD WHITE "Launching Git Deployer...\n";
                        eval {
    						require "$gitdeployer";
                            1;
                        } or do {
                            my $error = $@;
                            print LOGFILE "Error: $error\n";
                            print BOLD RED "Error: ";
                            print RED "$error";                            
                            print RESET "\r\n";
                        };
						
						# restore the stdout
						select($standard_out);
						close($client);
					}
					else {
						print BOLD GREEN "[$hostname]:";
						print $client "Query malformed.\r\n";
						close($client);
					}
	    			}
			}
			printf "[%12s]", time; 
			print " Connection closed for ".inet_ntoa($client->peeraddr)." PID $$ \n";
			close($client);
	    		exit 0;
		}
	}
	print "Close Server Called.\n";
	close($server);
}

sub trim
{
    my @out = @_;
    for (@out)
    {
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out : $out[0];
}
