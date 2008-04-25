use strict;
use warnings;
use Games::Go::Referee;
use Games::Go::Player;
use Games::Go::GTP;
use IPC::Open2;
use IO::Handle;

# Run this script with the command perl kgsbot.pl
# Edit $kgsGTPpath to suit yourself
# Player is the code that generates moves
# See Games::Go::GTP for assumptions that are made about its methods.

my $boardsize = shift;
my $kgsGTPpath = './kgsGtp-3.3.22';

my $referee = new Games::Go::Referee;
$referee->pointformat('gmp');
$referee->exitonerror('off');
$referee->alternation('off');

my $player = new Games::Go::Player;
$player->size($boardsize);
$referee->size($boardsize);
#$player->debug(1);
#$referee->debug(1);
$player->path('/media/BIG/DBs/');

my $reader = IO::Handle->new;
my $writer = IO::Handle->new;
my $cmd = 'java -jar '.$kgsGTPpath.'/kgsGtp.jar ppme.ini';
my $pid = open2($reader, $writer, $cmd);
$reader->autoflush(1);
$writer->autoflush(1);

my $wanttogo = 0;
my $ingame = 0;

while (1) {
  my $input = $reader->getline();
  chomp $input;
  $input =~ s/#.*//;
  if (defined $input){
    print $input;
    if ($input) {
      push my @args, split(' ', $input);
      print "\n", $referee->showboard, "\n";
      my ($res, $status) = Games::Go::GTP::gtpcommand(@args, $referee, $player);
      print $player->showratings if $referee->debug;
      $ingame = $status if defined $status;
      last if (not $ingame and $wanttogo);
      print $res;
      $writer->print($res,"\n");
    }
  }
}

sub quitnicely {
  $SIG{USR1} = \&quitnicely;
  if ($ingame) {
    $wanttogo = 1;
  } else {
    die 'Interrupted';
  }
}

# sending the command: kill -10 `ps -C perl -o pid=`
# will make the bot leave KGS as soon as it has finished the current game,
# assuming you are running the bot on the only perl process you have

BEGIN {
  $SIG{USR1} = \&quitnicely;
}

END {
  $writer->close();
  $reader->close();
  kill $pid, 9;
}
