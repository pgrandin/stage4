docker build -t test-stage4 -f Dockerfile-stage4 .
docker run -ti --privileged --rm test-stage4 /bin/bash /chroot.sh