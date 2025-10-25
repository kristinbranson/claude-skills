#!/bin/bash

# avi2gif.sh input.mp4 output.gif [scale] [fps]
# scale: width in pixels. default: 400, height scaled proportionally
# fps: frame rate. default: 30
# based on  https://cassidy.codes/blog/2017/04/25/ffmpeg-frames-to-gif-optimization/

palette="/tmp/palette.png"

if (($# > 2))
then
    scale=$3
else
    scale=400
fi

if (($# > 3))
then
    fps=$4
else
    fps=30
fi


filters="fps=$fps,scale=$scale:-1:flags=lanczos"

echo $filters

ffmpeg -v warning -i $1 -vf "$filters,palettegen=stats_mode=diff" -y $palette

ffmpeg -i $1 -i $palette -lavfi "$filters,paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" -y $2
