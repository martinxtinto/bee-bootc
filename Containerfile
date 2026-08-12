FROM quay.io/fedora/fedora-bootc:44

# rpm fusion repos
RUN dnf5 install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# tailscale
RUN dnf5 install -y dnf5-plugins
RUN dnf5 config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
RUN dnf5 install -y tailscale
COPY files/tailscale-bootstrap.sh /usr/local/bin/tailscale-bootstrap.sh
COPY files/tailscale-bootstrap.service /usr/lib/systemd/system/tailscale-bootstrap.service
RUN chmod +x /usr/local/bin/tailscale-bootstrap.sh
RUN systemctl enable tailscaled
RUN systemctl enable tailscale-bootstrap.service

# drbd install
RUN dnf5 install -y drbd

# intel CPU and GPU support
RUN dnf5 install -y \
    # CPU
    kernel-tools \
    # GPU: VAAPI stack for HW transcode
    intel-media-driver \
    libva \
    libva-utils \
    # QSV
    intel-compute-runtime \
    oneVPL-intel-gpu
RUN groupadd -f render

# disk health and sensors
RUN dnf5 install -y \
    smartmontools \
    lm_sensors

# k0s
RUN dnf5 remove -y zram-generator-defaults || true
RUN curl -sSLf https://get.k0s.sh | sh
RUN mkdir -p /usr/lib/modules-load.d && \
    printf 'overlay\nbr_netfilter\n' > /usr/lib/modules-load.d/k0s.conf
RUN mkdir -p /usr/lib/sysctl.d && \
    printf 'net.bridge.bridge-nf-call-iptables=1\nnet.ipv4.ip_forward=1\n' \
    > /usr/lib/sysctl.d/90-k0s.conf
COPY files/k0s-bootstrap.sh /usr/local/bin/k0s-bootstrap.sh
COPY files/k0s-bootstrap.service /usr/lib/systemd/system/k0s-bootstrap.service
RUN chmod +x /usr/local/bin/k0s-bootstrap.sh
RUN systemctl enable k0s-bootstrap.service

# disable selinux
RUN mkdir -p /usr/lib/bootc/kargs.d
COPY files/10-disable-selinux.toml /usr/lib/bootc/kargs.d/10-disable-selinux.toml

# custom writable dirs
RUN rmdir /opt
RUN ln -s -T /var/opt /opt
COPY files/90-custom-vardirs.conf /usr/lib/tmpfiles.d/90-custom-vardirs.conf

# cleanup
RUN dnf5 clean all && \
    rm -rf \
        /var/log/dnf5.log* \
        /var/cache/dnf5 \
        /var/cache/libdnf5 \
        /var/cache/libX11 \
        /var/cache/ldconfig/aux-cache \
        /var/lib/dnf/repos \
        /var/lib/dnf/system-repo.lock \
        /run/selinux-policy \
        /run/dnf

# checks
RUN bootc container lint
