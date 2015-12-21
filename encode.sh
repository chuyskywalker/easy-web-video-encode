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
echo "--- webm, First Pass"
ffmpeg -i $IN \
    -codec:v libvpx -quality good -cpu-used 0 -b:v 1000k -qmin 10 -qmax 42 -maxrate 1000k -bufsize 2000k \
    -threads 0 -vf scale=-1:720 \
    -an -pass 1 -f webm -y \
    /dev/null

echo "--- webm, Second Pass"
ffmpeg -i $IN \
    -codec:v libvpx -quality good -cpu-used 0 -b:v 1000k -qmin 10 -qmax 42 -maxrate 1000k -bufsize 2000k \
    -threads 0 -vf scale=-1:720 \
    -codec:a libvorbis -b:a 128k \
    -pass 2 -f webm \
    $OUT.webm

echo "--- x264, First Pass"
ffmpeg -i $IN \
    -codec:v libx264 -profile:v main -preset slow -b:v 1000k -maxrate 1000k -bufsize 2000k -vf scale=-1:720 \
    -threads 0 -pass 1 \
    -an -f mp4 -y \
    /dev/null

echo "--- x264, Second Pass"
ffmpeg -i $IN \
    -codec:v libx264 -profile:v main -preset slow -b:v 1000k -maxrate 1000k -bufsize 2000k -vf scale=-1:720 \
    -threads 0 -pass 2 \
    -codec:a libfdk_aac -b:a 128k -f mp4 \
    $OUT.mp4
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
