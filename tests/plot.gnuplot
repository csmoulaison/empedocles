set title 'Performance rendering 500 frames by thread count'
set xlabel 'Threads'
set ylabel 'Samples'
set zlabel '~ms'
set datafile separator ","
set term png
set output 'output.png'
set hidd front
set view 45,75
set xyplane at 0
set dgrid3d 10,10
set hidden3d
set pm3d
splot 'threads_samples.csv' using 4:5:($3/4000000)

