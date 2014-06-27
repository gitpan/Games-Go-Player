use strict;
use warnings;
use Games::Go::Referee;
use Games::Go::Player;
use Games::Go::GTP;
use IPC::Open2;
use IO::Handle;

# Edit $kgsGTPpath to your kgsGtp directory
# Player is the code that generates moves
# See Games::Go::GTP for assumptions that are made about its methods.
# You will also need to to modify the kgsbot.ini file with your bot's name and password

my $boardsize = shift;
$boardsize ||= 19;
my $kgsGTPpath = './kgsGtp-3.4.3';

my $referee = new Games::Go::Referee;
$referee->pointformat('gtp');
$referee->exitonerror('off');
$referee->alternation('off');

my $player = new Games::Go::Player;
$player->size($boardsize);
$referee->size($boardsize);
$player->path('/media/BIG/DBs/');
$player->passifopponentpasses(1);

Games::Go::GTP::engineName('ppme');
Games::Go::GTP::engineVersion('0.08');
Games::Go::GTP::protocolVersion('2');

my $reader = IO::Handle->new;
my $writer = IO::Handle->new;
my $cmd = 'java -jar '.$kgsGTPpath.'/kgsGtp.jar kgsbot.ini';
my $pid = open2($reader, $writer, $cmd);
autoflush $reader;
autoflush $writer;

my $wanttogo = 0;
my $ingame = 0;

while (my $input = $reader->getline) {
  chomp $input;
  $input =~ s/#.*//;
  if (defined $input){
    push my @args, split(' ', $input);
    my ($res, $status) = Games::Go::GTP::gtpcommand(@args, $referee, $player);
    $ingame = $status if defined $status;
    last if (not $ingame and $wanttogo);
    $writer->print($res);
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

# sending the command: kill -SIGUSR1 `ps -C perl -o pid=`
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
