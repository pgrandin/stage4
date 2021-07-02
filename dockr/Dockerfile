FROM gentoo/stage3:systemd-20210702

ARG BUILD_DATE
LABEL org.label-schema.build-date=$BUILD_DATE

RUN emerge-webrsync
RUN emerge -q dev-vcs/git eix app-misc/jq
RUN eix-update
RUN echo "PYTHON_TARGETS=\"python3_8 python3_7\"" >> /etc/portage/make.conf
RUN emerge -q app-portage/gentoolkit
