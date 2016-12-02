FROM alpine:3.4

RUN apk update && apk add --no-cache dnsmasq

ENTRYPOINT ["/usr/sbin/dnsmasq", "-C", "/etc/dnsmasq.conf", "--no-daemon"]
