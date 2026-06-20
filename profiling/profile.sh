echo "%define OUTPUT_PROFILE 1
%define UPDATE_GL 0
%define MOUSE_CONTROL 0" > ../build/profile.asm

echo "Test description,Start cycles,End cycles,Elapsed cyles,Threads,Samples,Bounces,Cubes,Pixel count,Region stride,Region count,Profile start frame,Profile end frame" > tests/xchg_ab.csv
echo -n "With XCHG," >> xchg_ab.csv
(cd ../ && EMPEDOCLES_PARAMS="-p ../build/profile.asm -d XCHG_REGIONS_COMPLETED" make clean bin/empedocles)
../bin/empedocles >> xchg_ab.csv
echo -n "With MOV," >> xchg_ab.csv
(cd ../ && EMPEDOCLES_PARAMS="-p ../build/profile.asm" make clean bin/empedocles)
../bin/empedocles >> xchg_ab.csv
