#!/bin/bash
#Download sgf archives from the KGS website to ./tar

perl kgshoover.pl

#Untar the downloaded files to ./sgf, then delete them

for i in $(find ./tar/*.tar.gz); do
  tar --directory=./sgf --strip-components 3 -xvf $i
done

rm ./tar/*.tar.gz -f

#Set a flag if removeTags.pl is found in the current directory

script="removeTags.pl"
let scriptFlag=0
if [ ! -f $script ]; then
  echo "$script does not exist in the current directory"
else
  scriptFlag=1
fi

#Run removeTags.pl then process the sgf file, adding the information to the database files

for j in 9 13 19; do
  for i in $(grep -Rl "SZ\[$j\]" ./sgf | sort); do
    if [ $scriptFlag -eq 1 ]; then
      perl $script $i
    fi
    perl kgsuserfile.pl $j $i 1
  done
done

#Clean up the ./sgf directory

rm ./sgf/*.* -f

