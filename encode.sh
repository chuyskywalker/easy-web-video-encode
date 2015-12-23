#!/bin/bash

# Get the directory and filename
DIR=$(dirname "$1")
FILE=$(basename "$1")

# Go into the directory so the container will work locally
cd $DIR

# Temporarily install the actual encode script
# Gets "mounted into" the container with FFMPEG and tackles all the real encoding
cat <<'EOF' > encode-inner.sh
IN=$1
OUT=$(echo $1 | sed 's/^\(.*\)\.[a-zA-Z0-9]*$/\1/')

echo "--- Encoding: $1"

# We need to detect whether the video is rotated or not in order to
# set the "scale" factor correctly, otherwise we can hit a fatal error
# However, ffmpeg will automatically apply the rotation for us, so we
# just need to ensure the scale is right, not also apply rotation.
ROTATION=$(ffprobe $IN 2>&1 | \grep rotate | awk '{print $3}')
if [ "$ROTATION" == "" ]; then
    # No rotation, use normal scale (height 720, width auto)
    SCALE="-1:720"
    echo "--- No rotation detected"
else
    # Rotated video; we need to specify the scale the other way around
    # to avoid a fatal "width not divisible by 2 (405x720)" error
    # Instead we'll use (height auto, width 720)
    SCALE="720:-1"
    echo "--- Rotation detected; changed scale param"
fi

# Count cores, more than one? Use many!
# Uses one less than total (recomendation for webm)
# Doesn't apply to x264 where 0 == auto (webm doesn't support that)
CORES=$(grep -c ^processor /proc/cpuinfo)
if [ "$CORES" -gt "1" ]; then
  CORES="$(($CORES - 1))"
fi

echo "--- Using $CORES threads for webm"

echo "--- webm, First Pass"
ffmpeg -i $IN \
    -hide_banner -loglevel error -stats \
    -codec:v libvpx -threads $CORES -slices 4 -quality good -cpu-used 0 -b:v 1000k -qmin 10 -qmax 42 -maxrate 1000k -bufsize 2000k -vf scale=$SCALE \
    -an \
    -pass 1 \
    -f webm \
    -y /dev/null

echo "--- webm, Second Pass"
ffmpeg -i $IN \
    -hide_banner -loglevel error -stats \
    -codec:v libvpx -threads $CORES -slices 4 -quality good -cpu-used 0 -b:v 1000k -qmin 10 -qmax 42 -maxrate 1000k -bufsize 2000k -vf scale=$SCALE \
    -codec:a libvorbis -b:a 128k \
    -pass 2 \
    -f webm \
    -y $OUT.webm

echo "--- x264, First Pass"
ffmpeg -i $IN \
    -hide_banner -loglevel error -stats \
    -codec:v libx264 -threads 0 -profile:v main -preset slow -b:v 1000k -maxrate 1000k -bufsize 2000k -vf scale=$SCALE \
    -an \
    -pass 1 \
    -f mp4 \
    -y /dev/null

echo "--- x264, Second Pass"
ffmpeg -i $IN \
    -hide_banner -loglevel error -stats \
    -codec:v libx264 -threads 0 -profile:v main -preset slow -b:v 1000k -maxrate 1000k -bufsize 2000k -vf scale=$SCALE \
    -codec:a libfdk_aac -b:a 128k \
    -pass 2 \
    -f mp4 \
    -y $OUT.mp4
EOF

# Run the container. Note that we set the workingdir to /tmp since there are a few cruft files
# the two stage encoding produces that we don't want to leave around in `pwd`
docker run -t --rm \
  -v `pwd`:/app \
  -w /tmp \
  --entrypoint='bash' \
  jrottenberg/ffmpeg@75bab46f78b9 \
  /app/encode-inner.sh /app/$FILE

# Remove that temp script
rm -f encode-inner.sh
