use 5.008008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Games::Go::Player',
    VERSION_FROM      => 'lib/Games/Go/Player.pm', # finds $VERSION
    PREREQ_PM         => {
                            DB_File    => 0,
                            Carp       => 0,
                            Test::More => 0
                          },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Games/Go/Player.pm', # retrieve abstract from module
       AUTHOR         => 'Daniel Gilder <deg@cpan.org>') : ()),
);
