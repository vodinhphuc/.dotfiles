#!/bin/bash

if ! command -v warp-cli &> /dev/null; then
  echo "Installing warp-cli..."

    # Add cloudflare gpg key
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

    # Add this repo to your apt repositories
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list

    # Install
    sudo apt-get update && sudo apt-get install cloudflare-warp
    warp-cli registration new

    # Connect
    warp-cli connect

    # Check 
    curl https://www.cloudflare.com/cdn-cgi/trace/ | grep 'warp='
else
  echo "Already installed: warp-cli"
fi

