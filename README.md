## Stream Video AI Demo iOS

A demo iOS app that connects to a [Node.js server](https://github.com/GetStream/openai-tutorial-node), that integrates Stream's Video SDK with OpenAI's Realtime API. 

This project showcases how to build AI-powered video applications with voice interactions.

Here's a screenshot of the end result:

<img src="https://github.com/user-attachments/assets/a314e9c5-4650-4a6c-8bcc-bc7182523fa7" alt="Simulator Screenshot" height="600">

### What This Repository Contains

The sample code demonstrates how to use Stream's Video SDK to create video calls and connect them with OpenAI's Realtime API for AI-powered voice interactions. 

This repo provides a sample app that showcases the following functionalities:
- connect to the Node.js server and fetch credentials to join a call
- add an AI agent to the call
- show beautiful visualizations of the AI audio levels

### Prerequisites

- You have followed the steps in the [Node.js server](https://github.com/GetStream/openai-tutorial-node) and you have a localhost running
  - Stream account with API key and secret
  - OpenAI API key with access to the Realtime API
- Xcode 15.3 or later
- Stream Video's iOS SDK (1.18.0 or above for the best experience)

### Usage

After you have started the localhost, open the Xcode project, wait for the packages to be downloaded and run it.

We are using “localhost” here (as defined in the `baseURL` property), the simplest way to test this is to run on simulator. 

You can also test this on a real device, to do that you need to set `baseURL` to your local network IP address instead. 

Additionally, your device and your computer should be on the same WiFi network and you need to allow “Arbitrary Loads” and “Local Networking” in your plist (the local server uses http and not https).
