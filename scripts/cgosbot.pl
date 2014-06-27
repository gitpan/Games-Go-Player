use strict;
use warnings;
use IO::Handle;
use Games::Go::Referee;
use Games::Go::Player;
use Games::Go::GTP;

my $boardsize = shift;

my $referee = new Games::Go::Referee;
$referee->pointformat('gtp');
$referee->exitonerror('off');
$referee->alternation('off');

my $stdin = new IO::Handle;
my $stdout = new IO::Handle;
autoflush $stdin;
autoflush $stdout;

my $player = new Games::Go::Player;
$player->size($boardsize);
$referee->size($boardsize);
$player->path('/media/BIG/DBs/');
$player->passpropensity(-100);

$stdin->fdopen(fileno(STDIN),'r') or die "Can't open STDIN: $!";
$stdout->fdopen(fileno(STDOUT),'w') or die "Can't open STDOUT: $!";

while (my $input = $stdin->getline) {
  chomp $input;
  $input =~ s/#.*//;
  if (defined $input){
    push my @args, split(' ', $input);
    $stdout->print(Games::Go::GTP::gtpcommand(@args, $referee, $player));
  }
}

$stdout->close;
$stdin->close;

