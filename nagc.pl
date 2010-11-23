#!/usr/bin/perl -w
#
# nagc.pl by xbj9000 <xbj9000@comcast.net>
# Description: send nagios alerts to nagd.pl, which will
#   send them as audio via phone call when appropriate.
# License: zlib
# 11/18/2010
#

use strict;
use IO::Socket;
use IO::Select;

my $out_pipe;

## network socket connection to asterisk
sub connect {
    $out_pipe = IO::Socket::INET->new(PeerAddr => '555.87.6.5',
                                      PeerPort => '6066',
                                         Proto => 'tcp') or &sleep;
}

## subroutine to wait and try again if unsuccessful
sub sleep {
    sleep(1); &connect;
}

## connect to asterisk, send data, and disconnect
&connect;
print $out_pipe "@ARGV";
$out_pipe->flush;
$out_pipe->close;
exit;
