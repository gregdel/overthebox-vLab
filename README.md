# Docker overthebox

This tool is made for development purposes only.


## Requirements

* docker (1.12.0+)
* docker-compose (1.7.0+)

## Run

The docker compose file will start three containers, one with the overthebox image and two with a dhcp server. They will all be on the same private network.
You can bind a public IP on each modem using the ```add_wan.sh``` script.


```
docker-compose up -d otb
docker-compose up -d modem1
```

Wait for the OTB to get an IP on the first network. And then stop the DHCP server on the modem1.

```
docker exec modem1 supervisorctl stop dnsmasq
```

You can now do the same with modem2.

## Tips

There's also an helper script to download, tag and push the latest stable image to the docker hub.
