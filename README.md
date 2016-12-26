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

You can now do the same with modem2. To force the OTB to check for a new DHCP you can run this command:

```
docker exec otb pkill -USR1 udhcpc
```

## Tips

There's also an helper script to download, tag and push the latest stable image to the docker hub.

## Register your device using the API

### Create an app

Create an app on this page: https://eu.api.ovh.com/createApp/
Store the credentials in ~/.ovh.conf, here is the proper syntax: https://github.com/ovh/go-ovh#use-the-api-on-behalf-of-a-user

Launch the cli whith the ```generateCk``` option to create a consumer key. And add it to the the ```.ovh.conf``` file.

```
cd cli
go run *.go --generateCk
```

Get the list of you services:


```
go run *.go --listServices
```


Get the device_id from your docker:

```
docker exec otb uci show overthebox.me.device_id
```

Link the device with the service

```
go run *.go -deviceId YOUR_DEVICE_ID -serviceId YOUR_SERVICE_ID
```

Confirm the service on the device

```
./activate_device.sh
```
