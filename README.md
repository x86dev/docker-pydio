Pydio Dockerfile
=============

This repository contains Dockerfile of Pydio for Docker's automated build published to the public Docker Hub Registry.

# Base Docker Image
[dockerfile/supervisor](https://registry.hub.docker.com/u/dockerfile/supervisor/)

# Installation

## Install Docker.

Download automated build from public Docker Hub Registry: docker pull kdelfour/pydio-docker

(alternatively, you can build an image from Dockerfile: docker build -t="kdelfour/pydio-docker" github.com/kdelfour/pydio-docker)

## Usage

    docker run -it -d -p 80:80 kdelfour/pydio-docker
    
You can add a shared directory as a volume directory with the argument *-v /your-path/files/:/pydio-data/files/ -v /your-path/personal/:/pydio-data/personal/* like this :

    docker run -it -d -p 80:80 -v /your-path/files/:/pydio-data/files/ -v /your-path/personal/:/pydio-data/personal/ kdelfour/pydio-docker

A mysql server with a database is ready, you can use it with this parameters : 

  - url : localhost
  - database name : pydio
  - user name : pydio
  - user password : pydio
    
## Build and run with custom config directory

Get the latest version from github

    git clone https://github.com/kdelfour/pydio-docker
    cd pydio-docker/

Build it

    sudo docker build --force-rm=true --tag="$USER/pydio-docker:latest" .
    
And run

    sudo docker run -d -p 80:80 -p 443:443 -v /your-path/files/:/pydio-data/files/ -v /your-path/personal/:/pydio-data/personal/ $USER/pydio-docker:latest
    
Enjoy !!    