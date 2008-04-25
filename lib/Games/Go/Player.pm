package Games::Go::Player;

use strict;
use warnings;
use DB_File;
use Carp;
our $VERSION = 0.07;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = {};
  $self->{_pathtoDBs} = './'; # This is altered with the path method
  $self->{_DBnameprefix} = 'patterns';
  $self->{_Maxnameprefix} = 'max';
  $self->{_size} = 18; # default board size
  $self->{_veclengths} = {};
  $self->{_maxmove} = { # maximum move number to consider when learning pattern
    2 => 500, # ie no effective maximum
    3 => 500,
    4 => 500,
    6 => 20,
    8 => 10,
    9 => 30,
   12 => 15,
   18 => 10,
  };
  $self->{_matrices} = { # symmetrys of the square (identity not included)
    1 => [0,-1,1,0],
    2 => [-1,0,0,-1],
    3 => [0,1,-1,0],
    4 => [0,1,1,0],
    5 => [1,0,0,-1],
    6 => [0,-1,-1,0],
    7 => [-1,0,0,1],
  };
  $self->{_gradegroups} = { # relative rank of k (kyu), d (dan) and p (pro)
    k => 2,
    d => 1,
    p => 0,
  };
  $self->{_pattern}    = {}; # the current pattern
  $self->{_rating}     = {}; # the current ratings
  $self->{_psym}       = {}; # to hold symmetries of the current pattern
  $self->{_rsym}       = {}; # to hold symmetries of the current ratings
  $self->{_ratings}    = {}; # a board for Black to find the best move
  $self->{_KGScleanup} = 0;  # KGS cleanup mode (limited passing)
  $self->{_weakest}    = '4k'; # lowest rank to learn from ( '30k' implies learn from, even if no rank information is present )
  $self->{_timeleftB}  = 100; # some initial high number so it won't pass at the beginning
  $self->{_timeleftW}  = 100;
  $self->{_psizenow}   = 0;
  $self->{_ratingIncrement} = 1; # may be set (higher) by the user, for example when learning joseki
  $self->{_debug}      = 0;
  bless $self, $class;
  return $self;
}

sub size {
  my $self = shift;
  my $size = shift if @_;
  $size--;
  if ($size) {
    if ($size =~ /\d+/) {
      $self->{_size} = $size;
      $self->{_veclengths} = {
        2 => 3,  # for all board sizes
        3 => 4,  # for all board sizes
        4 => 7,  # for all board sizes
      };
      for ($size) {
        if    ($_ == 8)  { $self->{_veclengths}{8}  = 21; last}
        elsif ($_ == 12) { $self->{_veclengths}{6}  = 13;
                           $self->{_veclengths}{12} = 43; last
                         }
        elsif ($_ == 18) { $self->{_veclengths}{9}  = 25;
                           $self->{_veclengths}{18} = 91; last
                         }
        croak 'Unsupported board size'."\n";
      }
      # how many 8 bit repetitions do i need? (1 holds 4 points)
      # For 9x9 games use 2, 3, 4, 8
      # For 13x13 games use 2, 3, 4, 6, 12
      # For 19x19 games use 2, 3, 4, 9, 18
      # To create your own pattern size, the rule is square it, divide it by 4, round up.
      # So for example you could add 5 to create 6x6 patterns.
      # Then place an entry in for your new size in $self->{_maxmove}, eg 5 => 500
    } else {
      croak 'Illegal value ', $size;
    }
  }
  return $self->{_size}
}

sub path {
  my $self = shift;
  my $path = shift if @_;
  if ((-e $path) and (-w $path)){
    $self->{_pathtoDBs} = $path;
    for my $colour ('B', 'W') {
      my $hashfilename = $self->{_pathtoDBs}.$self->{_Maxnameprefix}.$colour;
      $self->{$hashfilename} = {};
      tie_up($hashfilename, $self->{$hashfilename});
      for (keys %{$self->{_veclengths}}) {
        $hashfilename = $self->{_pathtoDBs}.$self->{_DBnameprefix}.$colour.$_;
        $self->{$hashfilename} = {};
        tie_up($hashfilename, $self->{$hashfilename});
      }
    }
  } else {
    croak 'Path does not exist or is not writeable: ', $path;
  }
  return $self->{_pathtoDBs}
}

sub tie_up {
  my ($filename, $hashref) = @_;
  tie %{$hashref}, "DB_File", $filename   # tie hash to database
  or die "Can't open $filename:$!\n";
}

sub teacher {
  my $self = shift;
  my $rank = shift;
  $self->{_weakest} = $rank if defined $rank and $rank =~ /^(\d{1,2})(k|d|p)\?*$/;
  return $self->{_weakest}
}

sub increment {
  my $self = shift;
  my $increment = shift;
  $self->{_ratingIncrement} = $increment if defined $increment and $increment =~ /\d+/;
  return $self->{_ratingIncrement}
}

sub debug {
  my $self = shift;
  my $debug = shift;
  $self->{_debug} = $debug if defined $debug and $debug =~ /0|1/;
  return $self->{_debug}
}

sub _iterboard (&$) {
  my ($sub, $size) = @_;
  for my $y (0..$size){
    for my $x (0..$size){
      $sub->($x, $y);
    }
  }
}

sub initboard {
  my ($self, $referee) = @_;
  updateratings($self, $referee, 'B', $self->{_size});
  updateratings($self, $referee, 'W', $self->{_size});
}

sub update {
  my ($self, $colour, $referee) = @_;
  resetratings($self);
  for (sort { $b <=> $a } keys %{$self->{_veclengths}}) { # biggest first
    my $match = updateratings($self, $referee, $colour, $_);
    my ($legal, $candidate) = matchedlegal($self, $colour, $referee);
    myprint ('Pattern size: ', $_, 'Match? ', $match, 'Legal? ', $legal) if $self->{_debug};
    if ($match and $legal) {
      last;
    }
  }
}

# is there at least one legal, non eye-filling move in the $self->{_ratings} keys?

sub matchedlegal {
  my ($self, $colour, $referee) = @_;
  for (grep $self->{_ratings}{$_}, keys %{$self->{_ratings}}) {
    /(.*),(.*)/;
    my ($x, $y) = ($1, $2);
    my $candidate = $referee->insertpoints($x, $y);
    myprint ('Checking legality of', $x, $y, $candidate) if $self->{_debug};
    if ($referee->islegal($colour, $candidate)) {
      myprint ($candidate, 'is legal') if $self->{_debug};
      return 1, $candidate unless fillingeye($self, $referee, $x, $y, $colour);
    }
  }
}

# Return an ordered list of candidate moves

sub choosemove {
  my ($self) = @_;
  my @filtered = grep $self->{_ratings}{$_}, keys %{$self->{_ratings}};
  my @keys = sort {$self->{_ratings}{$b} <=> $self->{_ratings}{$a}} @filtered;
  return @keys
}

sub chooselegalmove {
  my ($self, $colour, $referee) = @_;
  my ($point, $goodenough);
  my @suggested = choosemove($self);

 # if KGScleanup is on, don't reject a move because its rating is low
  if ($self->{_KGScleanup}) {
    $goodenough = 0;
  } else {
    $goodenough = -50;
  }

  for (@suggested) {
    /(.*),(.*)/;
    my ($x, $y) = ($1, $2);
    my $candidate = $referee->insertpoints($x, $y);
    myprint ('Testing move:', $x, $y, $candidate) if $self->{_debug};
    if ($referee->islegal('B', $candidate)) {
      myprint ('Is legal:', $x, $y, $candidate) if $self->{_debug};
      unless (fillingeye($self, $referee, $x, $y, $colour)) {
        if ($self->{_ratings}{$x.','.$y} > $goodenough) {
          $point = $candidate;
        }
        last;
      }
    }
  }
  return $point || pass($self, $referee)
}

sub fillingeye {
  my ($self, $referee, $x, $y, $colour) = @_;
  my $me = ($colour eq 'B') ? 'x' : 'o';
  my $surroundings = $referee->getboardsection($x - 1, $y - 1, 2);
  my $count = 0;

  for (1,3,5,7) {
    if ((substr($surroundings, $_, 1) eq $me) or (substr($surroundings, $_, 1) eq '-')) {
      $count++;
    }
  }

  if ($count == 4) {
    $count = 0;
    $me = ($colour eq 'B') ? 'o' : 'x';
    for (0,2,6,8) {
      $count++ if substr($surroundings, $_, 1) eq $me;
      $count += 0.5 if substr($surroundings, $_, 1) eq '-';
    }
    return 1 if $count < 2
  }
  return 0
}

sub learn {
  my ($self, $colour, $point, $referee, $counter, $rank) = @_;

  if (($colour eq 'B' or $colour eq 'W') and isteacher($self, $rank)) {
    unless ($referee->ispass($point)) {
      my ($x, $y) = $referee->extractpoints($point);

      for (keys %{$self->{_veclengths}}) {
        unless ($counter > $self->{_maxmove}{$_}) {
        $self->{_psizenow} = $_;
        myprint ('Pattern size is', $_) if $self->{_debug};
        myprint ('x is', $x, ', y is', $y) if $self->{_debug};

          _iterboard {
            my ($i, $j) = @_;
            my $xoffset = $x + $i - $_;
            my $yoffset = $y + $j - $_;
            if (inrange($self, $xoffset, $yoffset)) {
              myprint ('Inrange') if $self->{_debug};
              clearhashes($self);
              board2pattern($self, $xoffset, $yoffset, $referee);
              unless (($_ == 2 or $_ == 3 or $_ == 4) and isempty($self, $self->{_pattern})) {
                my $hashname = $self->{_pathtoDBs}.$self->{_DBnameprefix}.$colour.$_;
                myprint ('DB pathname is', $hashname) if $self->{_debug};
                genpattern($self, $_ - $i, $_ - $j, $colour, $hashname);
                unless ($_ == 8 or $_ == 12 or $_ == 18) { # don't reverse if whole board pattern
                  swappatterncolours($self);
                  $colour = swapcolour($self, $colour);
                  $hashname = $self->{_pathtoDBs}.$self->{_DBnameprefix}.$colour.$_;
                  genpattern($self, $_ - $i, $_ - $j, $colour, $hashname);
                }
              }
            }
          } $_;

        }
      }

    }
  }
}

sub genpattern {
  my ($self, $i, $j, $colour, $hash) = @_;
  my $maxhash = $self->{_pathtoDBs}.$self->{_Maxnameprefix}.$colour;
  my ($max, $mcode) = findmaxvec($self);
  if (not exists $self->{$maxhash}{$$max}) {
    myprint ('Pattern not maxxed') if $self->{_debug};
    my $invcode = getinvert($mcode);
    my ($r, $s) = transformpoint($self, $invcode, $i, $j);
    my $ismaxxed = match2vec($self, $hash, $max, $r, $s);
    $self->{$maxhash}{$$max} = undef if $ismaxxed;
  }
}

sub updateratings{
  my ($self, $referee, $colour, $psize) = @_;
  my $hashname = $self->{_pathtoDBs}.$self->{_DBnameprefix}.$colour.$psize;
  $self->{_psizenow} = $psize;
  my $match;
  _iterboard {
    my ($i, $j) = @_;
    my $xoffset = $i - $psize + 2;
    my $yoffset = $j - $psize + 2;
    if (inrange($self, $xoffset, $yoffset)) {
      clearhashes($self);
      board2pattern($self, $xoffset, $yoffset, $referee);
      my ($max, $mcode) = findmaxvec($self);
      my $invcode = getinvert($mcode);
      my $vec = $self->{$hashname}{$$max};
      if ($vec) {
        $match = 1;
        # load _rating with move values
        vec2vpattern($self, $vec, $self->{_rating});
        # transform to _rsym
        transform($self, $invcode, $self->{_rsym}, $self->{_rating});
        # transform to _psym
        transform($self, $invcode, $self->{_psym}, $self->{_pattern});
        loadratings($self, $xoffset, $yoffset);
      }
    }
  } $self->{_size};
  return $match
}

# here you can define how pattern scores in the database are converted into a point's score

sub loadratings {
  my ($self, $x, $y) = @_;
#  my ($av, $sd, $max) = stats($self, $self->{_rsym}, $self->{_psym});
#  $av ||= 1;
  my $density = density($self, $self->{_psym});
  _iterboard {
    my ($i, $j) = @_;
    my $r = $i + $x;
    my $s = $j + $y;
    unless (offboard($self, $r, $s)) {
      $self->{_ratings}{$r.','.$s} += ($self->{_rsym}{$i.','.$j} * $density);
    }
  } $self->{_psizenow};
}

# Get information about a particular pattern (for debugging)

sub retrieve {
  my ($self, $db, $str) = @_;
  clearhashes($self);
  if (defined $str) {
    my $iveclength = sqrt (length $str) - 1;
    if (exists $self->{_veclengths}{$iveclength}) {
      $self->{_psizenow} = $iveclength;
      str2temp($self, $str, $self->{_pattern});
      myprint(showpattern($self, $self->{_pattern}));
      myprint('Symmetrys ', @{findsymmetrys($self)});
      my ($vec, $tcode) = findmaxvec($self);
      vec2pattern($self, $$vec, $self->{_rsym});
      myprint('Max of pattern ');
      myprint(showpattern($self, $self->{_rsym}));
      my $ratings = $self->{$db}{$$vec};
      if ($ratings) {
        $str = ratings2string($self, $ratings);
        myprint('Ratings');
        myprint($str);
        vec2vpattern($self, $ratings, $self->{_rating});
        myprint('Stats ', stats($self, $self->{_rating}, $self->{_pattern}));
        myprint('Maxxed') if mymax($self, $self->{_rating}) == 255;
      } else {
        myprint('No ratings found');
      }
    } else {
      myprint('Pattern of unrecognised length: ', length $str);
    }
  } else {
    myprint('No pattern supplied'); 
  } 
}

sub DBdump {
  my ($self, $patternhash) = @_;
  clearhashes($self);

  $patternhash =~ /[a-zA-Z]*(\d+)$/;
  $self->{_psizenow} = $1;
  myprint ('Pattern size:', $self->{_psizenow}) if $self->{_debug};
  while (my ($key, $value) = each %{$self->{$patternhash}}) {
    vec2pattern($self, $key, $self->{_pattern});
    myprint(showpattern($self, $self->{_pattern}));
    myprint(ratings2string($self, $value));
  }
}

# get info about a pattern database (for debugging)

sub tiestats {
  my ($self, $patternhash) = @_;
  my $count;

  while (each %{$self->{$patternhash}}) {
    $count++;
  }

  myprint('Total: ', $count) if defined $count;
}

# load the pattern hash with the board at origin x,y (size = _psize)

sub board2pattern {
  my ($self, $x, $y, $referee) = @_;
  my $pointcontents;
  $self->{_pattern} = {};
  _iterboard {
    my ($i, $j) = @_;
    my $r = $i + $x;
    my $s = $j + $y;
    if (offboard($self, $r, $s)) {
      $pointcontents = '-';
    } else {
      $pointcontents = $referee->point($r, $s);
    }
    die $x, $y, $r, $s unless defined $pointcontents;
    $self->{_pattern}{$i.','.$j} = $pointcontents;
  } $self->{_psizenow};
}


# for all patterns, symmetrise their ratings and update the hash of maxxed values

sub symmetrise {
  my $self = shift;
  
  for my $colour ('B', 'W') {
    my $maxhash = $self->{_pathtoDBs}.$self->{_Maxnameprefix}.$colour;

    for (keys %{$self->{_veclengths}}) {
      my $count = 0;
      my $patternhash = $self->{_pathtoDBs}.$self->{_DBnameprefix}.$colour.$_;
      $self->{_psizenow} = $_;

      while (my ($key, $value) = each %{$self->{$patternhash}}) {
        $count++;
        vec2pattern($self, $key, $self->{_pattern});
        my $symref = findsymmetrys($self);
        if (@{$symref}) {
          vec2vpattern($self, $value, $self->{_rating});
          my %temp;

          _iterboard {
            my ($i, $j) = @_;
            $temp{$i.','.$j} = $self->{_rating}{$i.','.$j};
          } $self->{_psizenow};

          for (@$symref) {
            transform($self, $_, $self->{_rsym}, $self->{_rating});
            _iterboard {
              my ($i, $j) = @_;
              $temp{$i.','.$j} += $self->{_rsym}{$i.','.$j};
            } $self->{_psizenow};
          }

          my $ismaxxed = renormaliseratingpattern($self, \%temp);
          $self->{$patternhash}{$key} = vpattern2vec($self, \%temp);
          $self->{$maxhash}{$_} = undef if $ismaxxed;
        }
        print sprintf("%08d", $count), "\b\b\b\b\b\b\b\b";
      }
    }
  }

}

# Search the Dbs for maxxed ratings and update the maxxed DB accordingly

sub updateMax {
  my $self = shift;

  for my $colour ('B', 'W') {

    my $maxhash = $self->{_pathtoDBs}.$self->{_Maxnameprefix}.$colour;
    for (keys %{$self->{_veclengths}}) {

      my $patternhash = $self->{_pathtoDBs}.$self->{_DBnameprefix}.$colour.$_;
      $self->{_psizenow} = $_;
      while (my ($key, $value) = each %{$self->{$patternhash}}) {
        unless (exists $self->{$maxhash}{$key}) {
          $self->{$maxhash}{$key} = undef if ismaxxed($self, $value);
        }
      }
    }
  }

}

# for a pattern, find its symmetrys

sub findsymmetrys {
  my ($self) = @_;
  my @syms;
  my $holdingref = pattern2vec($self, $self->{_pattern});

  for (1..7) {
    transform($self, $_, $self->{_psym}, $self->{_pattern});
    my $vecref = pattern2vec($self, $self->{_psym});
    if ($$holdingref eq $$vecref) {
      push @syms, $_;
    }
  }

  return \@syms
}

# for a pattern, find its stringwise maximum vector

sub findmaxvec {
  my $self = shift;
  my $index = 0;
  my $holdingref = pattern2vec($self, $self->{_pattern});
  $self->{_psym} = $self->{_pattern};

  for (1..7) {
    my $hashref = {};
    transform($self, $_, $hashref, $self->{_pattern});
    my $vecref = pattern2vec($self, $hashref);
    if ($$holdingref lt $$vecref) {
      $self->{_psym} = $hashref;
      $holdingref = $vecref;
      $index = $_;
    }
  }

  return $holdingref, $index
}

sub transformpoint {
  my ($self, $matrixcode, $x, $y) = @_;
  return $x, $y if $matrixcode == 0; # save time if its the identity matrix
  my $offset = $self->{_psizenow}/2;
  $x -= $offset;
  $y -= $offset;
  my $mref = $self->{_matrices}{$matrixcode};
  my $trx = ($mref->[0] * $x) + ($mref->[1] * $y);
  my $try = ($mref->[2] * $x) + ($mref->[3] * $y);
  return $offset + $trx, $offset + $try
}

sub transform {
  my ($self, $matrixcode, $copy, $template) = @_;
  _iterboard {
    my ($i, $j) = @_;
    my ($trx, $try) = transformpoint($self, $matrixcode, $i, $j);
    $copy->{$i.','.$j} = $template->{$trx.','.$try};
  } $self->{_psizenow};
}

# update a ratings vector when a pattern match is found
# and notify of maxxed vectors

sub match2vec {
  my ($self, $hash, $vecref, $x, $y) = @_;
  my ($res, $rvec);
  my $vec = $$vecref;
  if (exists $self->{$hash}{$vec}) {
    $rvec = $self->{$hash}{$vec};
  } else {
    $rvec = chr(0) x p_area($self);
    vec($rvec, p_area($self), 8) = 0;  
  }
  my $offset = $y * ($self->{_psizenow} + 1) + $x;
  if (vec($rvec, $offset, 8) > (255 - $self->{_ratingIncrement})) {
    vec($rvec, $offset, 8) = 255;
    $res = 1;
  } else {
    vec($rvec, $offset, 8) += $self->{_ratingIncrement};
  }
  $self->{$hash}{$vec} = $rvec;
  return $res;
}

# turn a pattern hash into a string

sub showpattern{
  my ($self, $ref) = @_;
  my $h = '';
  my $size = $self->{_psizenow};
  _iterboard {
    my ($x, $y) = @_;
    $h .= $ref->{$x.','.$y};
    $h .= "\n" if $x == $size;
  } $size;
  return $h
}

# turn a ratings hash into a string

sub showratings{
  my ($self) = @_;
  my $h = '';
  my $size = $self->{_size};
  _iterboard {
    my ($x, $y) = @_;
    my $value = $self->{_ratings}{$x.','.$y};
    $value ||= ' . ';
    unless ($value eq ' . ') {
      $value = int $value if $value =~ /\d/;      
    }
    $h .= '['.$value.']';
    $h .= "\n" if $x == $size;
  } $size;
  return $h
}

# turn a pattern hash into a pattern vector

sub pattern2vec {
  my ($self, $ref) = @_;
  my $vec = chr(0) x $self->{_veclengths}{$self->{_psizenow}};
  my $offset = 0;
  my $piece;
  _iterboard {
    my ($i, $j) = @_;
    for ($ref->{$i.','.$j}){
      if ($_ eq '.') { $piece = 0; last }
      if ($_ eq 'o') { $piece = 1; last }
      if ($_ eq 'x') { $piece = 2; last }
      if ($_ eq '-') { $piece = 3; last }
      croak 'Unknown symbol:', $_;
    }
    vec($vec, $offset, 2) = $piece;
    $offset += 1;
  } $self->{_psizenow};
  return \$vec;
}

# turn a ratings hash into a ratings vector

sub vpattern2vec {
  my ($self, $ref) = @_;
  my $offset = 0;
  my $vec = chr(0) x p_area($self);
  my $piece;
  _iterboard {
    my ($i, $j) = @_;
    vec($vec, $offset, 8) = $ref->{$i.','.$j};
    $offset += 1;
  } $self->{_psizenow};
  return $vec;
}

# turn a ratings vector into a (pattern) hash

sub vec2vpattern {
  my ($self, $vec, $ref) = @_;
  my $offset = 0;
  _iterboard {
    my ($i, $j) = @_;
    $ref->{$i.','.$j} = vec($vec, $offset, 8);
    $offset += 1;
  } $self->{_psizenow};
}

# turn a pattern vector into a pattern hash

sub vec2pattern {
  my ($self, $vec, $ref) = @_;
  my $offset = 0;
  my $piece;
  _iterboard {
    my ($i, $j) = @_;
    for (vec($vec, $offset, 2)){
      if ($_ == 0) { $piece = '.'; last }
      if ($_ == 1) { $piece = 'o'; last }
      if ($_ == 2) { $piece = 'x'; last }
      if ($_ == 3) { $piece = '-'; last }
      die 'Unknown code';
    }
    $ref->{$i.','.$j} = $piece;
    $offset += 1;
  } $self->{_psizenow};
}

# turn a ratings vector into a string for debugging

sub ratings2string {
  my ($self, $vec) = @_;
  my $offset = 0;
  my $h = '';
  my $ubound = p_area($self) - 1;
  for my $i (0..$ubound) {
    $h .= ' '.vec($vec, $offset, 8);
    $h .= "\n" if ($i + 1) % ($self->{_psizenow} + 1) == 0;
    $offset += 1;
  }
  return $h
}

# turn a string into a pattern for debugging

sub str2temp {
  my ($self, $str, $ref) = @_;
  my $piece;
  _iterboard {
    my ($i, $j) = @_;
    $ref->{$i.','.$j} = substr($str, $j * ($self->{_psizenow} + 1) + $i, 1);
  } $self->{_psizenow};
}

sub getinvert {
  my ($transnum) = @_;
  $transnum =~ tr/13/31/;
  return $transnum
}

sub resetratings {
  my ($self) = @_;
  _iterboard {
    my ($i, $j) = @_;
    $self->{_ratings}{$i.','.$j} = undef; #if $self->{_ratings}{$i.','.$j} ne 'i';
  } $self->{_size};
}

# You may consider using this measure when updating the ratings

sub getaverage {
  my ($self, $type) = @_;
  my $sum = 0;
  my $counter;
  _iterboard {
    my ($i, $j) = @_;
    if ($self->{$type}{$i.','.$j} =~ /\d/) {
      $sum += $self->{$type}{$i.','.$j};
      $counter++;
    }
  } $self->{_size};
  $counter ||= 1;
  return $sum/$counter
}

# change a pattern's ratings so that the highest = 255
# if the maximum value is over 255

sub renormaliseratingpattern {
  my ($self, $ref) = @_;
  my $result = 1;
  my $max = mymax($self, $ref);
  if ($max > 255) {
    my $ratio = 255/$max;
    _iterboard {
      my ($x, $y) = @_;
      $ref->{$x.','.$y} = int(($ref->{$x.','.$y} * $ratio) + 0.5);
    } $self->{_psizenow};
  } else {
    $result = 0;
  } return $result
}

sub mymax {
  my ($self, $ref) = @_;
  my $max = 0;
  _iterboard {
    my ($x, $y) = @_;
    $max = $ref->{$x.','.$y} if $ref->{$x.','.$y} > $max;
  } $self->{_psizenow};
  return $max
}

sub ismaxxed {
  my ($self, $vec) = @_;
  my $ubound = $self->{_psizenow}**2 - 1;
  for (0..$ubound){
    return 1 if vec($vec, $_, 8) == 255;
  }
  return 0
}

# You may consider using this measure when updating the ratings

sub density {
  my ($self, $ref) = @_;
  my $count = 0;
  my $empty = 0;
  _iterboard {
    my ($x, $y) = @_;
    for ($ref->{$x.','.$y}) {
      if ($_ eq 'o' or $_ eq 'x') {$count++; last}
      if ($_ eq '.') {$empty++; last}
    }
  } $self->{_psizenow};
  return ($count + 1)/($count + $empty)
}

sub offboard {
  my ($self, $x, $y) = @_;
  my $size = $self->{_size};
  return 1 if ($x < 0 or $x > $size or $y < 0 or $y > $size);
  return 0
}

# so the pattern is an edge or centre pattern, not inbetween

sub inrange {
  my ($self, $x, $y) = @_;
  my $bsize = $self->{_size};
  myprint ('Testing range of', $x, $y) if $self->{_debug};
  for ($self->{_psizenow}) {
    if ($_ == 2) {
      return 1 if inregion($x, $y, 2, $bsize - 6);
      last
    }
    if ($_ == 3) {
      return 1 if inregion($x, $y,  2, $bsize - 7);
      return 1 if inregion($x, $y, -1, $bsize - 1) and not inregion($x, $y,  0, $bsize - 3);
      last
    }
    if ($_ == 4) {
      return 1 if inregion($x, $y,  2, $bsize - 8);
      return 1 if inregion($x, $y, -2, $bsize ) and not inregion($x, $y,  0, $bsize - 4);
      last
    }
    if ($_ == 6 and $bsize == 12) {
      return 1 if isquarter($x, $y, $bsize/2);
      last
    }
    if ($_ == 9 and $bsize == 18) {
      return 1 if isquarter($x, $y, $bsize/2);
      last
    }
    if ($_ == $bsize) {
      return 1 if $x == 0 and $y == 0;
      last
    }
    croak 'Unknown pattern size'."\n";
  }
  return 0
}

sub inregion {
  my ($x, $y, $offset, $length) = @_;
  return 0 if (($x < $offset) or
               ($x > ($offset + $length)) or
               ($y < $offset) or
               ($y > ($offset + $length)));
  return 1
}

sub isquarter {
  my ($x, $y, $q) = @_;
  return 1 if ($x == -1 and $y == -1) or
              ($x == -1 and $y == $q + 1) or
              ($y == -1 and $x == $q + 1) or
              ($x == $q + 1 and $y == $q + 1);
  return 0
}

sub stats {
  my ($self, $rref, $pref) = @_;
  my $sum = 0;
  my $sumsquares = 0;
  my $count = 1;
  my $max = 0;
  my $current;
  _iterboard {
    my ($i, $j) = @_;
    if ($pref->{$i.','.$j} eq '.') {
      $current = $rref->{$i.','.$j};
      $sum += $current;
      $sumsquares += $current**2;
      $count++;
      $max = $current if $current > $max;
    }
  } $self->{_psizenow};
  my $av = $sum/$count;
  return $av, sqrt(($sumsquares/$count) - $av**2), $max
}

sub isteacher {
  my ($self, $rank) = @_;
  my $result = 0;
  my ($integerrank, $integergrade, $weakestteacherintegerrank, $weakestteacherintegergrade);
  ($integerrank, $integergrade) = parserank($self, $rank);
  ($weakestteacherintegerrank, $weakestteacherintegergrade) = parserank($self, $self->{_weakest});
  
  if (($integergrade lt $weakestteacherintegergrade) or
      ($integergrade == $self->{_gradegroups}{'k'} and 
       $integerrank <= $weakestteacherintegerrank and 
       $integergrade eq $weakestteacherintegergrade) or
      (($integergrade == $self->{_gradegroups}{'d'} or $integergrade == $self->{_gradegroups}{'p'}) and 
       $integerrank >= $weakestteacherintegerrank and 
       $integergrade eq $weakestteacherintegergrade)) {
    $result = 1;
  }

  myprint ('Is teacher?', $result) if $self->{_debug};
  return $result
}

# If rank is undefined, a rank equivalent to 30k is returned

sub parserank {
  my ($self, $rank) = @_;
  my $integergradegroup;
  my $integerrank;
  if (defined $rank) {
    if ($rank =~ /^(\d{1,2})(K|k|D|d|P|p)\?*$/) {
      $integerrank = $1;
      $integergradegroup = $self->{_gradegroups}{lc $2};
    } else {
      croak 'Unknown rank format'."\n";
    }
  } else {
    $integerrank = '30';
    $integergradegroup = $self->{_gradegroups}{'k'};    
  }
  return $integerrank, $integergradegroup  
}

sub isempty {
  my ($self, $ref) = @_;
  for (values %{$ref}) {
    return 0 if /o|x/;
  }
  return 1
}

sub pass {
  my ($self, $referee) = @_;
  if ($referee->{_const}{pointformat} eq 'sgf') {
    return ''
  } else {
    return 'pass'
  }
}

# swap black and white stones in pattern

sub swappatterncolours {
  my ($self) = @_;
  _iterboard {
    my ($x, $y) = @_;
    for ($self->{_pattern}{$x.','.$y}) {
      if ($_ eq 'x') {
        $self->{_pattern}{$x.','.$y} = 'o'
      } elsif ($_ eq 'o') {
        $self->{_pattern}{$x.','.$y} = 'x'
      }
    }
  } $self->{_psizenow}
}

sub swapcolour {
  ($_[1] eq 'B') ? 'W' : 'B'
}

sub dist {
  sqrt(($_[0] - $_[2])**2 + ($_[1] - $_[3])**2)
}

# return the area of the pattern size

sub p_area {
  my ($self) = @_;
  my $res = ($self->{_psizenow} + 1)**2;
  return $res
}

sub clearhashes {
  my ($self) = @_;
  $self->{_pattern} = {};
  $self->{_psym}    = {};
  $self->{_rating}  = {};
  $self->{_rsym}    = {};
}

sub myprint {
  my @messages = @_;
  if (exists $messages[0]) {
	  open(LOG, ">>", './playerlogfile.txt') or die 'Can\'t open'."\n";
		  print LOG (join ' ', @messages, "\n");
	  close(LOG);
  }
}

1;

=head1 NAME

Games::Go::Player - plays a game of Go.

=head1 SYNOPSIS

This program generates a move on a Go board according to patterns 
that it learns from game records in SGF.

It puts patterns into a database (called pattern<colour><size>).
Which databases are updated depends on $self->{_veclengths}.
Pattern information is stored in a hash, where the key is the pattern,
(compressed using vec) and the value contains a score for each point
on the pattern from 0 to 255.
A pattern point is either empty, black, white, or 'not on the board'

For an example script that instructs Player to learn from a particular
directory, see pluserdir.pl in the scripts folder.

To play a move:

  my $move = $player->chooselegalmove($colour, $referee);
  $referee->play($colour, $move);
  $player->update($colour, $referee);

Or see kgspot.pl which is included in the scripts folder.

Before learning, the following parts of the 'new' method can (and 
in some cases, should) be edited:

$self->{_maxmove} For example, its probably not worth looking beyond move 10 when matching
whole board 19x19 games.

$self->{_weakest} For example, if matching patterns from a 9 handicap game between a 3 kyu
and a 12 kyu, you may want to disregard the moves of the 12kyu

The function loadratings can be tweaked as you see fit. For example, at the moment it gives
a higher score to a move close to the centre of a pattern than one on the edge.

=head1 Debugging

The tiestats method can be called on a particular pattern file.
It counts the number of patterns in the file, and how many are 'maxxed'
ie Have a point in them that has been matched 255 times (and so are not updated again).

The retrieve method examines a pattern file for a particular pattern.
The pattern is expressed as a string of 'o', 'x', '.' and '-'
Where 'o' represents a white stone, 'x' a black one, '.' an empty point and '-' the edge of the board.
eg '-----...-...-..x' represents the top left corner pattern - 

----
-...
-...
-..x

For example: 

use File::Basename;
use Games::Go::Player;

my ($pathname, $pattern) = @_;
my $player  = new Player;
my ($filename, $dirname) = fileparse($pathname);
$filename =~ /(\d+)/;
$player->size($1);
$player->path($dirname);
$player->tiestats($filename);
$player->retrieve($pathname, $pattern) if defined $pattern;

=head1 Maintenance

The symmetrise method can be used to give a symmetrical pattern a symmetrical rating pattern.
I suggest using it on databases when a large proportion of their patterns are maxxed.

=head1 BUGS/CAVEATS

There is a memory leak (?) in learn mode that gobbles up about 1Mb/minute on a 1.86GHz machine
(which processes about 10 sgf files every 5 minutes). 
If you ask it to play on a boardsize that it has not learnt any patterns for, and it is
Black in a handicap game, it will pass as its handicap moves(!). 
KGS doesn't seem to handle this situation well, and neither does this program.

=head1 Ideas

When learning, information on the closest move (in terms of the sequence of the game) could
be stored.
Have an additional piece of information in a pattern's ratings - how often this pattern has
occurred after both players pass in a scored game.

=head1 AUTHOR (version 0.01)

Daniel Gilder

=head1 THANKS

To Ricardo Signes for explaining some of the workings of Games::Goban

=cut
