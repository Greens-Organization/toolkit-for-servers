FROM almalinux:9

ENV container=docker
STOPSIGNAL SIGRTMIN+3

RUN dnf -y update && \
    dnf -y install epel-release && \
    dnf -y install \
    curl --allowerasing \
    wget \
    sudo \
    systemd \
    systemd-sysv \
    openssh-server \
    firewalld \
    iptables \
    fail2ban \
    vim \
    ca-certificates \
    pam \
    initscripts \
    --allowerasing && \
    dnf clean all

# Remove serviços desnecessários
RUN (cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i = systemd-tmpfiles-setup.service ] || rm -f $i; done); \
    rm -f /lib/systemd/system/multi-user.target.wants/*; \
    rm -f /etc/systemd/system/*.wants/*; \
    rm -f /lib/systemd/system/local-fs.target.wants/*; \
    rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
    rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
    rm -f /lib/systemd/system/basic.target.wants/*; \
    rm -f /lib/systemd/system/anaconda.target.wants/*

RUN systemctl enable sshd
RUN systemctl enable firewalld

RUN useradd -m -s /bin/bash testuser && \
    echo "testuser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/testuser && \
    chmod 0440 /etc/sudoers.d/testuser

WORKDIR /toolkit
RUN mkdir -p /toolkit/modules

VOLUME ["/sys/fs/cgroup"]

EXPOSE 22

ENTRYPOINT ["/usr/sbin/init"]
