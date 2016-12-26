package main

import (
	"fmt"

	"github.com/ovh/go-ovh/ovh"
)

func (app *App) generateConsumerKey() {

	ckReq := app.NewCkRequest()

	// Allow GET method on /me
	ckReq.AddRules(ovh.ReadOnly, "/me")

	// Allow all methods on /overTheBox and all its sub routes
	ckReq.AddRecursiveRules(ovh.ReadWrite, "/overTheBox")

	// Run the request
	response, err := ckReq.Do()
	if err != nil {
		fmt.Printf("Error: %q\n", err)
		return
	}

	// Print the validation URL and the Consumer key
	fmt.Printf("Generated consumer key: %s\n", response.ConsumerKey)
	fmt.Printf("Please visit %s to validate it\n", response.ValidationURL)
}
