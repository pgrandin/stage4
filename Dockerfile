# syntax=docker/dockerfile-upstream:1-labs
# ^- for HEREDOC syntax

FROM gentoo/stage3:latest as stage3
ARG today
ENV build_date=$today
LABEL org.label-schema.build-date=$build_date
RUN emerge-webrsync
RUN echo "PYTHON_TARGETS=\"python3_9 python3_10\"" >> /etc/portage/make.conf
# RUN FEATURES="-ipc-sandbox -network-sandbox -pid-sandbox" emerge -q app-portage/gentoolkit
COPY files /stage4/files
ENV stage4_fs="/mnt/gentoo"
RUN mkdir ${stage4_fs}
RUN BASEURL="http://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc/" && \
    STAGE3=`wget -q -O - ${BASEURL}|grep -o 'stage3-amd64-openrc-2[^<]\{15\}.tar.xz'|uniq` && \
    wget -nvc ${BASEURL}/$STAGE3 && \
    unxz -k $STAGE3 && tar xpf ${STAGE3%.*} -C ${stage4_fs}
RUN rsync -vrtza /stage4/files/common/ ${stage4_fs}/
COPY config.json ${stage4_fs}/
RUN echo "nameserver 9.9.9.9" > ${stage4_fs}/etc/resolv.conf


FROM stage3 as targeted
ARG target="Z390"
ENV target=$target
RUN rsync -vrtza /stage4/files/$target/ /
RUN env-update && source /etc/profile 
RUN eselect profile set default/linux/amd64/17.1
RUN USE=-perl emerge -q dev-vcs/git eix app-misc/jq


FROM targeted as kernel-config
RUN eix-update
# Prepare kernel config
RUN git clone https://github.com/pgrandin/kernel-configs.git /tmp/kernel-configs-master/
RUN echo kconfig_sha=$(cd /tmp/kernel-configs-master/ && git rev-parse HEAD) > /kernel_vars.txt
RUN echo kversion=$(eix gentoo-source|awk -F'[()]' '/ [~]?5.10/ {version=$2} END{print version}') >> kernel_vars.txt
RUN cat /tmp/kernel-configs-master/common_defconfig /tmp/kernel-configs-master/${target}_defconfig > ${target}_defconfig
COPY config.json /config.json
RUN <<-EOF
    source /kernel_vars.txt
    confs=$(cat /config.json | jq --arg HOST target -r '.configs[] | select (.["host"]=="'${target}'") | .kernel_configs |.[]' )
    for conf in $confs; do
        echo "# for ${conf}" >> ${target}_defconfig
        cat /tmp/kernel-configs-master/${conf}_defconfig >> ${target}_defconfig
    done
EOF
RUN [ -d /etc/portage/package.keywords/ ] || mkdir /etc/portage/package.keywords/
RUN source /kernel_vars.txt && echo "=sys-kernel/gentoo-sources-$kversion ~amd64" > /etc/portage/package.keywords/gentoo-sources
RUN source /kernel_vars.txt && FEATURES="-getbinpkg" emerge -q =gentoo-sources-$kversion
RUN source /kernel_vars.txt && cd /usr/src && ln -s linux-${kversion}-gentoo linux
ENV kpath="linux"
RUN cat ${target}_defconfig /usr/src/${kpath}/arch/x86/configs/x86_64_defconfig > /usr/src/${kpath}/arch/x86/configs/${target}_defconfig
RUN cd /usr/src/${kpath} && make defconfig ${target}_defconfig


FROM kernel-config as kernel-build
RUN cd /usr/src/${kpath} && make -j$(nproc)


FROM kernel-config as harfbuzz
RUN echo "PYTHON_TARGETS=\"python3_9 python3_10\"" >> /etc/portage/make.conf
RUN sed -i '/^PORTAGE_BINHOST/d' /etc/portage/make.conf
RUN USE=-harfbuzz emerge -1q freetype
RUN USE="-truetype -cairo -glib -introspection" emerge -1q harfbuzz
# Upgrade glibc 
RUN emerge --unmerge virtual/libcrypt && emerge -1q glibc
# Switch binutils profile
RUN new=$(binutils-config --list-profiles |awk '/\[2\]/ {print $2}') && binutils-config ${new}

# RUN USE=harfbuzz emerge -1q freetype
# RUN USE=truetype emerge -1q harfbuzz


FROM harfbuzz as system
RUN emerge -NDuq @system


FROM system as world
RUN emerge -NDuq @world