#!/usr/bin/perl -w
#
# nagd.pl by xbj9000 <xbj9000@comcast.net>
# Description: listen for nagios alerts coming from nagc.pl,
#   and send them as audio via phone call when appropriate.
# License: zlib
# 11/18/2010
#

use strict;
use IO::Socket;
use IO::Select;
use Proc::Daemon;
use Asterisk::AMI;

my $thresh = 5;    ## number of alerts required to place call
my $period = 30;   ## minutes in which notifications must occur
my $wait = 120;    ## seconds to listen for more issues before calling

my @alerts;
my $ami;

## run as daemon
Proc::Daemon::Init();

## open a network socket to listen for nagios input
my $in_pipe = IO::Socket::INET->new(Proto => 'tcp',
                                   Listen => '32',
                                LocalAddr => '555.87.6.5',
                                LocalPort => '6066');

## subroutine to send alerts via phone call
sub ami_send {
    $ami = Asterisk::AMI->new(PeerAddr => 'localhost',
                              PeerPort => '5044',
                              Username => 'admin',
                                Secret => 'poop');

    $ami->action({Action => 'Originate',
                 Channel => 'SIP/Main Trunk/5035559309',
                 Context => 'default',
             Application => 'Playback', 
                    Data => 'nags',
                Callerid => '9315551540',
                 Timeout => '30000',
                ActionId => 'DEF1337',
                Priority => '1'});

    $ami->disconnect();
}

## needed to check for new input before proceeding with call
my $in_check = IO::Select->new($in_pipe); 

LOOP: while (1) {
    ## recieve nagios input from socket
    my $link = $in_pipe->accept();
    my $data = <$link>;

    ## drop invalid input and go back to listening
    next if ($data !~ /^Notification Type:.*/);

    ## create a timestamp for the current input data
    my $now = substr(time,5,8);

    if ($data =~ /RECOVERY|ACKNOWLEDGEMENT/) {
        ## clear resolved issues
        $data =~ s/^.*(Host:.*Address).*$/$1/;
        @alerts = grep {$_ !~ /$data/} @alerts;
    } else {
        ## timestamp and push new issues to @alerts
        push @alerts, "$now : $data";
    }

    ## remove alerts older than $period
    @alerts = grep {($now - substr($_, 0, 5)) < $period*60} @alerts;

    ## place call if excessive alerts within $period
    if (@alerts >= $thresh) {

        ## wait a while for new alerts before placing call
        next LOOP if $in_check->can_read($wait);

        ## filter unimportant details
        for (@alerts) {
            s/^.*(Host:.*)Address.*(State:.*)
                Date\/Time.*(Additional.*$)/$1$2$3/x;
            s/ \=//; s/ \(.*$/./;
        }

        ## remove duplicate errors (note: is this needed?)
        my %filter = map {$_,1} @alerts;
        @alerts = keys %filter;

        ## save alerts to text file to be used by espeak
        open TXT, ">", "/tmp/nags.txt";
        print TXT "The following is a nagios alert.\n";
        print TXT "$_\n" for (@alerts);
        close TXT;

        ## convert text to speech
        system("espeak", '-p 30', '-s 135',
               '-f/tmp/nags.txt', '-w/tmp/nags.wav');

        ## convert wav to gsm for asterisk playback
        system("sox", '/tmp/nags.wav', '-r 8000',
               '/var/lib/asterisk/sounds/nags.gsm');

        ## place call and clear @alerts
        &ami_send; undef @alerts;
    }

}
