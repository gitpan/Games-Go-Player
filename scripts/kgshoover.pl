# This script will download player's games from the KGS archives
# It requires a file containing simply a list of kgs usernames, seperated by
# a newline. Names can be commented out by preceeding them with a '#'.
# The name of this file is stored in $playerfile (see below)
# The directory where the archives
# will be saved, is stored in $localbaseurl
# A player's index page is also stored there as user.html
# It assumes a player's games (eg Abc's), are stored at
# http://www.gokgs.com/servlet/archives/en_US/Abc-2008-3.zip
# for March 2008, and that the link to April's zip is written
# gameArchives.jsp?user=Abc&amp;year=2008&amp;month=4

use strict;
use warnings;
use HTML::TokeParser;
use LWP::UserAgent;

# Change these two variables as necessary
#------------------------------------------
my $localbaseurl = '/home/dan/Desktop/KGS/tar/';
my $playerfile   = '/home/dan/Desktop/KGS/kgsplayers.txt';
#------------------------------------------

my $webbaseurl = 'http://www.gokgs.com/';
my $ua = LWP::UserAgent->new;
my $tarlist = '';

open(my $tarlistFH, "<", $localbaseurl.'tarlist.txt') or die "Couldn't open tarlist.txt\n";
while (<$tarlistFH>) {
  chomp;
  $tarlist .= $_;
}
close($tarlistFH) or die "Couldn't close tarlist.txt\n";
open(INPUT, "<", $playerfile) or die "Couldn't open $playerfile\n";
open($tarlistFH, ">>", $localbaseurl.'tarlist.txt') or die "Couldn't open tarlist.txt\n";
while (<INPUT>) {
  chomp;
  unless (/^#/) {
    print $_,"\n";
    my $elapsedtime = time;
    getuserpage($tarlistFH, $tarlist, $_);
    # wait at least 4 seconds between calls to getuserpage
    # as requested by William Shubert (creator of KGS)
    # Do not delete the following line
    sleep($elapsedtime - time + 4) if time - $elapsedtime < 4;
  }
}
close($tarlistFH) or die "Couldn't close tarlist.txt\n";
close(INPUT) or die "Couldn't close $playerfile\n";

sub getuserpage {
  my ($tarlistFH, $tarlist, $user) = @_;
  my $url = 'gameArchives.jsp?user='.$user.'&oldAccounts=y';
  my $mylocalurl = $localbaseurl.'user.html';
  open(OUTFILE, ">",$mylocalurl) or die 'Can\'t open '.$mylocalurl;
    my $reply = myconnect($url);
    print OUTFILE $reply->content;
  close OUTFILE or die 'Can\'t close '.$mylocalurl;

  my $p = HTML::TokeParser->new($mylocalurl);

# Skip to start of user data

  $p->get_tag("table");
  $p->get_tag("table");
  while (1) {
    my $elapsedtime = time;
    my $a_token = $p->get_tag("a");
    my $str = $a_token->[1]{href};
    last unless defined $str && $str =~ /year=(.+)&month=(.+)/;
    my $file = $user.'-'.$1.'-'.$2.'.tar.gz';
    my $target = $webbaseurl.'servlet/archives/en_US/'.$file;
    unless ($tarlist =~ /$file/) {
      system("lwp-download $target $localbaseurl");
      print $tarlistFH $file."\n";
      # wait at least 4 seconds between calls to archives
      # as requested by William Shubert (creator of KGS)
      # Do not delete the following line
      sleep($elapsedtime - time + 4) if time - $elapsedtime < 4;
    }
  }
}

sub myconnect {
  my $url = shift;
  my $reply = $ua->get($webbaseurl.$url);
  # Check the outcome of the response
  $reply->is_success or die 'Couldn\'t connect to '.$url.' Stopped '."$!";
  return $reply;
}

