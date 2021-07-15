FROM gentoo/stage3:systemd-20210228

ARG BUILD_DATE
LABEL org.label-schema.build-date=$BUILD_DATE

RUN emerge-webrsync
RUN FEATURES="-pid-sandbox" emerge -q dev-vcs/git eix app-misc/jq
RUN eix-update
RUN echo "PYTHON_TARGETS=\"python3_9\"" >> /etc/portage/make.conf
RUN emerge -q app-portage/gentoolkit
