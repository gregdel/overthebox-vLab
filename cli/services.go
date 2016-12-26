package main

import "fmt"

// Service represents a service
type Service struct {
	Status         string `json:"status"`
	Name           string `json:"serviceName"`
	ReleaseChannel string `json:"releaseChannel"`
	Description    string `json:"customerDescription"`
}

func (app *App) listServices() {
	serviceNames := []string{}
	if err := app.Get("/overTheBox", &serviceNames); err != nil {
		fmt.Println(err)
		return
	}

	if len(serviceNames) == 0 {
		fmt.Println("No services")
		return
	}

	services := make([]*Service, len(serviceNames))
	for i, name := range serviceNames {
		s := &Service{}
		if err := app.Get("/overTheBox/"+name, s); err != nil {
			fmt.Println(err)
			return
		}

		services[i] = s
	}

	fmt.Println("Services:")
	for i, s := range services {
		fmt.Printf("%d: %s (%s)[%s] - %s\n", i, s.Name, s.Status, s.ReleaseChannel, s.Description)
	}
}

func (app *App) linkDeviceAndService(device, service string) {
	params := map[string]string{
		"deviceId": device,
	}
	if err := app.Post("/overTheBox/"+service+"/linkDevice", params, nil); err != nil {
		fmt.Println(err)
		return
	}

	fmt.Printf("Device %q linked to the service %q\n", device, service)
}
