GIT_COMMIT_NAME=$(git log -1 --pretty=%s)
echo "Start cycles,End cycles,Elapsed cyles,Threads,Samples,Bounces,Cubes,Pixel count,Region stride,Region count,Profile start frame,Profile end frame" > tests/threads_samples.csv
for i in {1..8}
do
    for j in {1..5..2}
    do
        echo "%define THREAD_COUNT $i
        %define SAMPLE_COUNT $j
        %define OUTPUT_PROFILE 1
        %define UPDATE_GL 0
        %define MOUSE_CONTROL 0" > ../build/profile.asm
        (cd ../ && EMPEDOCLES_PARAMS="-p ../build/profile.asm" make clean bin/empedocles)
        ../bin/empedocles >> other_test.csv
    done
done
