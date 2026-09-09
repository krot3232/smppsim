# SMPPSim
SMPPSim is an SMPP (Short Message Peer-to-Peer) server simulator designed for development and testing of applications that communicate using the SMPP protocol.

It allows you to run a local SMPP SMSC without connecting to a real SMSC.

[![Docker](https://img.shields.io/docker/pulls/krot3232/smppsim?style=flat-square&logo=docker&logoColor=white)](https://hub.docker.com/r/krot3232/smppsim)

## Features

- SMPP server for testing clients
- SMPP port: `2775`
- Web interface: `8088`
- Shell script startup
- `systemd` service support
- Docker support

## Ports

| Port | Description |
|------|-------------|
| `2775` | SMPP server |
| `8088` | Web interface |

## Running

SMPPSim can be started in three different ways.

### 1. Using `startsmppsim.sh`

Start SMPPSim directly using the startup script:

```bash
./startsmppsim.sh
```

If the script does not have execute permissions:

```bash
chmod +x startsmppsim.sh
./startsmppsim.sh
```



### 2. Using systemd

SMPPSim can be run as a `systemd` service using `smppsim.service`.

Git clone:
```bash
git clone git@github.com:krot3232/smppsim.git /opt/smppsim
```
Create a user and grant permissions for the directory:
```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin smppsim
sudo chown -R smppsim:smppsim /opt/smppsim
```
Copy the service file to the systemd directory:

```bash
sudo cp /opt/smppsim/smppsim.service /etc/systemd/system/
```

Reload the systemd configuration:

```bash
sudo systemctl daemon-reload
```

Start SMPPSim:

```bash
sudo systemctl start smppsim
```

Enable automatic startup on system boot:

```bash
sudo systemctl enable smppsim
```

Check the service status:

```bash
sudo systemctl status smppsim
```

View logs:

```bash
sudo journalctl -u smppsim
```

Follow logs in real time:

```bash
sudo journalctl -u smppsim -f
```

Stop SMPPSim:

```bash
sudo systemctl stop smppsim
```

Restart SMPPSim:

```bash
sudo systemctl restart smppsim
```

### 3. Using Docker

Build the Docker image:

```bash
docker build -t krot3232/smppsim .
```

Run the container:

```bash
docker run -d \
  --name smppsim1 \
  -p 2775:2775 \
  -p 8088:8088 \
  krot3232/smppsim
```

Check the running container:

```bash
docker ps
```

View container logs:

```bash
docker logs smppsim1
```

Follow logs in real time:

```bash
docker logs -f smppsim1
```

Stop the container:

```bash
docker stop smppsim1
```

Start the existing container again:

```bash
docker start smppsim1
```

Remove the container:

```bash
docker rm smppsim1
```


## Checking Ports

Check the SMPP port:

```bash
nc -zv localhost 2775
```

Check the Web interface port:

```bash
nc -zv localhost 8088
```

You can also check the Web interface using `curl`:

```bash
curl http://localhost:8088
```


## Link
+ Short Message Peer-to-Peer Protocol Specification https://smpp.org/SMPP_v5.pdf
+ SMPPSim offical web site http://web.archive.org/web/20190916074856/http://www.seleniumsoftware.com/index.html
+ SMPPSim free simple tutorial https://www.youtube.com/watch?v=C2s6ixCgel0
