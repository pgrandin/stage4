docker build -t test-stage4 -f Dockerfile-stage4 .
docker run -ti --privileged --name stage4-builder test-stage4 /bin/bash /chroot.sh
docker cp stage4-builder:/stage4.tgz stage4.tgz
