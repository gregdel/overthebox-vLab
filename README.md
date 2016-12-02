# Docker overthebox

This tool is made for development purposes only.


## Requirements

* docker (1.12.0+)
* docker-compose (1.7.0+)

## Run

The docker compose file will start two containers, one with the overthebox image and one with a dhcp server. They will both be on the same private network.

Just run docker compose to get everything started.

```
docker-compose up
```

Once the overthebox container is registered and associated with an overthebox service, the dhcp container can be stopped.

```
docker-compose stop modem1
```

## Tips

There's also an helper script to download, tag and push the latest stable image to the docker hub.
