%define THREAD_COUNT            1
%define SAMPLE_COUNT            4
%define FSAMPLE_COUNT           4.0
%define BOUNCE_COUNT            32
%define CUBES_COUNT             8
%define HISTORY_FRAMES_PER_FRAME 200
%define HISTORY_FRAMES_COUNT    600

%define PIXELS_W                480
%define FPIXELS_W               480.0
%define PIXELS_H                480
%define FPIXELS_H               480.0
%define DEF_REGION_STRIDE       PIXELS_W * 2

%define OUTPUT_FRAMES_TO_FILE   1
%define OUTPUT_PROFILE          0
%define PROFILE_START_FRAME     200
%define PROFILE_END_FRAME       1000
%define UPDATE_GL               1
%define MOUSE_CONTROL           0
%define EXIT_AFTER_ROTATION     1

%if OUTPUT_PROFILE
    %define EXIT_AFTER_ROTATION 1
%endif
