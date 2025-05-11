FROM ubuntu:22.04

# Configuração para systemd
ENV container=docker
STOPSIGNAL SIGRTMIN+3
ENV DEBIAN_FRONTEND=noninteractive

# Instala pacotes essenciais
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    wget \
    sudo \
    systemd \
    systemd-sysv \
    openssh-server \
    ufw \
    iptables \
    fail2ban \
    vim \
    ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Configuração para systemd
RUN cd /lib/systemd/system/sysinit.target.wants/ && \
    ls | grep -v systemd-tmpfiles-setup | xargs rm -f && \
    rm -f /lib/systemd/system/multi-user.target.wants/* && \
    rm -f /etc/systemd/system/*.wants/* && \
    rm -f /lib/systemd/system/local-fs.target.wants/* && \
    rm -f /lib/systemd/system/sockets.target.wants/*udev* && \
    rm -f /lib/systemd/system/sockets.target.wants/*initctl* && \
    rm -f /lib/systemd/system/basic.target.wants/* && \
    rm -f /lib/systemd/system/anaconda.target.wants/* && \
    rm -f /lib/systemd/system/plymouth* && \
    rm -f /lib/systemd/system/systemd-update-utmp*

# Configura SSH
RUN mkdir -p /var/run/sshd && \
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    systemctl enable ssh

# Cria usuário de teste com sudo
RUN useradd -m -s /bin/bash testuser && \
    echo "testuser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/testuser && \
    chmod 0440 /etc/sudoers.d/testuser

# Diretório de trabalho
WORKDIR /toolkit

# Cria diretório para scripts
RUN mkdir -p /toolkit/modules

# Volume para systemd
VOLUME ["/sys/fs/cgroup"]

# Expõe porta SSH
EXPOSE 22

# Entrypoint - Inicia o systemd como PID 1
ENTRYPOINT ["/usr/sbin/init"]

# Mantém o container rodando
CMD ["/usr/sbin/init"]
