#!/bin/sh
# Genere les videos de test synthetiques de l'etape 0 dans apps/step0-test/media/
# avec le ffmpeg livre par Stremio Desktop (ou celui passe dans $FFMPEG).
set -e
F="${FFMPEG:-$LOCALAPPDATA/Programs/Stremio/ffmpeg.exe}"
OUT="$(dirname "$0")/../apps/step0-test/media"
mkdir -p "$OUT"
cd "$OUT"
V="-f lavfi -i testsrc2=size=1280x720:rate=25:duration=60"
SINE="-f lavfi -i sine=frequency=440:duration=60"
PAN="[1:a]pan=5.1|FL=c0|FR=c0|FC=c0|LFE=c0|BL=c0|BR=c0[a]"
Q="-hide_banner -loglevel error -y"
X264="-c:v libx264 -preset veryfast -pix_fmt yuv420p"

printf '1\n00:00:01,000 --> 00:00:10,000\nSous-titre de test SRT numero 1\n\n2\n00:00:12,000 --> 00:00:30,000\nDeuxieme sous-titre (accents : e a c)\n' > test.srt
"$F" $Q $V $SINE $X264 -c:a aac -b:a 128k -movflags +faststart test.mp4
"$F" $Q $V $SINE -filter_complex "$PAN" -map 0:v -map "[a]" $X264 -c:a ac3 -b:a 384k h264_ac3.mkv
"$F" $Q $V $SINE -filter_complex "$PAN" -map 0:v -map "[a]" $X264 -c:a eac3 -b:a 384k h264_eac3.mkv
"$F" $Q $V $SINE -filter_complex "$PAN" -map 0:v -map "[a]" $X264 -c:a dca -strict -2 -b:a 768k h264_dts.mkv
"$F" $Q $V $SINE -i test.srt -filter_complex "$PAN" -map 0:v -map "[a]" -map 2:s \
    -c:v libx265 -preset fast -x265-params log-level=error -pix_fmt yuv420p -c:a ac3 -b:a 384k -c:s srt hevc_ac3_srt.mkv
ls -l
