package main

import (
	"flag"
	"fmt"

	"github.com/ovh/go-ovh/ovh"
)

// App represents the app
type App struct {
	*ovh.Client
}

// NewApp returns a new app
func NewApp() (*App, error) {
	// Create a client using credentials from config files or environment variables
	client, err := ovh.NewEndpointClient("ovh-eu")
	if err != nil {
		return nil, err
	}

	return &App{
		Client: client,
	}, nil
}

func main() {
	app, err := NewApp()
	if err != nil {
		fmt.Printf("Error: %q\n", err)
		return
	}

	generateCk := flag.Bool("generateCk", false, "help generate a consumer key for the OVH API")
	listServices := flag.Bool("listServices", false, "list services from the API")
	deviceID := flag.String("deviceId", "", "device id")
	serviceID := flag.String("serviceId", "", "service id")
	flag.Parse()

	// Genearete a consumer key
	if *generateCk {
		app.generateConsumerKey()
		return
	}

	// List services
	if *listServices {
		app.listServices()
		return
	}

	// Link service and device
	if *deviceID != "" && *serviceID != "" {
		app.linkDeviceAndService(*deviceID, *serviceID)
		return
	}

	flag.PrintDefaults()
}
