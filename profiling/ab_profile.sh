rm branch_ab.csv
echo "Test,Start cycles,End cycles,Elapsed cyles,Threads,Samples,Bounces,Cubes,Pixel count,Region stride,Region count,Profile start frame,Profile end frame" > tests/branch_ab.csv

for i in {2..30..4}
do
    echo "%define OUTPUT_PROFILE 1
    %define UPDATE_GL 0
    %define MOUSE_CONTROL 0
    %define SAMPLE_COUNT $i
    %define TEST 0" > ../build/profile.asm
    echo -n "0,original," >> branch_ab.csv
    (cd ../ && EMPEDOCLES_PARAMS="-p ../build/profile.asm" make clean bin/empedocles)
    ../bin/empedocles >> branch_ab.csv

    echo "%define OUTPUT_PROFILE 1
    %define UPDATE_GL 0
    %define MOUSE_CONTROL 0
    %define SAMPLE_COUNT $i
    %define TEST 1" > ../build/profile.asm
    echo -n "1,branch_removed," >> branch_ab.csv
    (cd ../ && EMPEDOCLES_PARAMS="-p ../build/profile.asm" make clean bin/empedocles)
    ../bin/empedocles >> branch_ab.csv
done

# https://stackoverflow.com/questions/327576/how-do-you-plot-bar-charts-in-gnuplot
echo "set title 'Branch removal AB test'
set datafile separator \",\"
stat 'branch_ab.csv' using
set ylabel '~ms'
set boxwidth 0.5
set style fill solid
set term png
set output 'output.png'
plot 'branch_ab.csv' using 1:(\$5/4000000):xtic(2) with boxes" > plot
gnuplot plot
rm plot
