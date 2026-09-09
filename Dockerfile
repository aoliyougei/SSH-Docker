FROM debian:12-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends openssh-server bash curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --shell /bin/bash aoliyougei \
 && passwd -d aoliyougei \
 && mkdir -p /run/sshd /etc/ssh/authorized_keys \
 && chmod 755 /etc/ssh/authorized_keys

COPY sshd_config /etc/ssh/sshd_config

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
