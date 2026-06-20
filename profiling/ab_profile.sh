rm interleave_ab.csv
echo "Test,Start cycles,End cycles,Elapsed cyles,Threads,Samples,Bounces,Cubes,Pixel count,Region stride,Region count,Profile start frame,Profile end frame" > tests/interleave_ab.csv

for i in {0..50}
do
    echo "%define OUTPUT_PROFILE 1
    %define UPDATE_GL 0
    %define MOUSE_CONTROL 0
    %define TEST 0" > ../build/profile.asm
    echo -n "0,original," >> interleave_ab.csv
    (cd ../ && EMPEDOCLES_PARAMS="-p ../build/profile.asm" make clean bin/empedocles)
    ../bin/empedocles >> interleave_ab.csv

    echo "%define OUTPUT_PROFILE 1
    %define UPDATE_GL 0
    %define MOUSE_CONTROL 0
    %define TEST 1" > ../build/profile.asm
    echo -n "1,interleaved," >> interleave_ab.csv
    (cd ../ && EMPEDOCLES_PARAMS="-p ../build/profile.asm" make clean bin/empedocles)
    ../bin/empedocles >> interleave_ab.csv
done

# https://stackoverflow.com/questions/327576/how-do-you-plot-bar-charts-in-gnuplot
echo "set title 'Interleave AB test'
set datafile separator \",\"
stat 'interleave_ab.csv' using
set ylabel '~ms'
set boxwidth 0.5
set style fill solid
set term png
set output 'output.png'
plot 'interleave_ab.csv' using 1:(\$5/4000000):xtic(2) with boxes" > plot
gnuplot plot
rm plot
