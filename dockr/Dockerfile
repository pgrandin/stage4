FROM gentoo/stage3:systemd-20201118

RUN emerge-webrsync
RUN emerge -q dev-vcs/git eix jq app-portage/gentoolkit
RUN eix-update
