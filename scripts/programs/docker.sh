#!/bin/bash

if ! command -v docker &> /dev/null; then
  echo "🐋 Installing Docker"
  sudo apt-get install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      gnupg-agent \
      software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  sudo add-apt-repository \
     "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
     $(lsb_release -cs) \
     stable"
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io
  sudo docker run hello-world
  # Add current user to docker group to run docker with current user without root permission
  sudo usermod -aG docker $USER

else
  echo "Already installed: docker"
fi
