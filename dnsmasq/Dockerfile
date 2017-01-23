FROM alpine:3.4

RUN apk update && apk add --no-cache dnsmasq supervisor iptables iproute2

COPY run.sh /usr/bin/run.sh
COPY dnsmasq.conf /etc/dnsmasq.conf
COPY dnsmasq-supervisor.conf /etc/supervisor.d/dnsmasq.ini

ENTRYPOINT ["/usr/bin/run.sh"]
