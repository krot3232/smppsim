# SMPPSim
SMPPSim is an SMPP (Short Message Peer-to-Peer) server simulator designed for development and testing of applications that communicate using the SMPP protocol.

It allows you to run a local SMPP SMSC without connecting to a real SMSC.

[![Docker](https://img.shields.io/docker/pulls/krot3232/smppsim?style=flat-square&logo=docker&logoColor=white)](https://hub.docker.com/r/krot3232/smppsim)

## Features

- SMPP server for testing clients, covering bind, `submit_sm`, `submit_multi`, `data_sm`, `deliver_sm`, `query_sm`, `cancel_sm`, `replace_sm`, `enquire_link`, `unbind` and outbind
- Simulated message life cycle: messages move through delivery states on configurable probabilities and produce delivery receipts
- Web interface with a form for injecting MO messages, a `?stats` endpoint and a shutdown command — see [HTTP Interface](#http-interface)
- MO traffic generated from a CSV file at a configurable rate
- Loopback and ESME to ESME routing, so submitted messages come back as `deliver_sm`
- Raw and decoded PDU capture to file, plus an optional byte stream callback to an external server — see [Callback Channel](#callback-channel)
- Everything driven by a properties file, so several instances with different behaviour can run side by side — see [Configuration](#configuration)
- Bundled `send_submit_sm.sh`, `send_deliver_sm.sh`, `send_query_sm.sh`, `send_cancel_sm.sh`, `send_replace_sm.sh`, `send_submit_multi.sh`, `send_data_sm.sh` and `send_enquire_link.sh` for exercising a running instance from the command line, with no SMPP client to install — see [smpp-bash](https://github.com/krot3232/smpp-bash/)
- Startup via shell script, `mise` task, `systemd` service or Docker

## Ports

| Port | Description |
|------|-------------|
| `2775` | SMPP server, set by `SMPP_PORT` |
| `8088` | Web interface, set by `HTTP_PORT` |

These are the defaults from `conf/smppsim.props`; both are per instance settings, so a second instance started with its own properties file can use different ones. When the byte stream callback is enabled, the simulator also connects out to `CALLBACK_PORT`, `3333` by default. The instances used by the test suite listen on 2775, 2776 and 2777 — see [Testing](#testing).

## Running

SMPPSim can be started in five different ways.

None of the shell scripts in the repository carry the execute bit, so set it once before using any of them:

```bash
chmod +x *.sh smpp-bash/*.sh
```

### 1. Using `startsmppsim.sh`

Start SMPPSim directly using the startup script:

```bash
./startsmppsim.sh
```

### 2. Using `startwith.sh`

Start SMPPSim with a configuration file of your choice, instead of the default `conf/smppsim.props`:

```bash
./startwith.sh conf/props.mo
```

Useful for running several instances side by side, each with its own ports and behaviour. See [Configuration](#configuration) for what a properties file can contain.

### 3. Using mise

`mise.toml` declares the required Java version and a task that starts the simulator with the default configuration:

```bash
mise install
mise run smppsim
```

### 4. Using systemd

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

### 5. Using Docker

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

What else that port answers — statistics, MO injection and a shutdown command — is in [HTTP Interface](#http-interface).

## Test Message Scripts

`smpp-bash/` holds a set of command line tools that drive the simulator over real SMPP — submitting messages, receiving them, querying, cancelling, replacing and pinging a session — so a running instance can be checked without installing an SMPP client. They are plain bash over `/dev/tcp`: no client library, no Java, nothing to install, and the exit status of each one distinguishes the failure modes, which makes them usable as smoke tests in CI.

```bash
smpp-bash/send_submit_sm.sh
```

```
connected to 127.0.0.1:2775
bound as smppclient1, smsc system_id=SMPPSim
submit_sm_resp: ESME_ROK, message_id=0
unbound
```

The full documentation — what each script does, every option, the exit codes and the simulator behaviour worth knowing about — is in [smpp-bash/README.md](https://github.com/krot3232/smpp-bash/blob/main/README.md).

## HTTP Interface

Besides the SMPP port the simulator runs a small HTTP server of its own: `HttpHandler`, a hand written HTTP/1.0 server, not a servlet container. It listens on `HTTP_PORT` (`8088` by default) with `HTTP_THREADS` threads all accepting on the same socket, serves the control panel out of `DOCROOT` and takes its commands from the query string.

| Request | What it does |
|---------|--------------|
| `GET /` or `GET /index.htm` | Control panel: version, start time, bound sessions, queue depths and an OK/error counter for every PDU type |
| `GET /?refresh` | The same page, and cancels a pending shutdown confirmation |
| `GET /?stats` | Two counters as plain text: `submittedok=N,deliveredok=M` |
| `GET /?shutdown` | Stops the simulator — takes two requests, see below |
| `GET /inject_mo?...` | Injects an MO message into the inbound queue |
| `GET /inject_mo.htm` | The injection form, which submits to `/inject_mo` by GET |
| `GET /user-guide.htm`, stylesheet, images | Static files, but only those listed in `AUTHORISED_FILES` |

Only the request line is looked at, and only its second token: the method is read and thrown away, headers and body are never read at all. A browser, `curl` and `curl -X POST` therefore all get the same answer, and nothing a request carries beyond the URI has any effect. Every response is HTTP/1.0 with no `Content-Length`, and the connection is closed once the response has been written.

There is no authentication, and the listener is bound to every interface, so anyone who can reach `HTTP_PORT` can inject messages and stop the instance. Keep it on a trusted network, or give the instance a properties file with a port nobody else can reach.

### Stopping the simulator

`?shutdown` is a two step command: the first request only arms it, the second one carries it out.

```bash
curl "http://localhost:8088/?shutdown"   # arms the shutdown
curl "http://localhost:8088/?shutdown"   # confirms it
```

The first response is the control panel with `Please confirm by selecting Shutdown again or select Refresh to cancel...` where the status message normally goes — the same page the Shutdown link of the web interface lands on. The second request calls `Smsc.stop()`, which stops the MO service, the queue services and the connection handlers and closes the listening sockets, and then exits the JVM two seconds later:

```
2026.09.14 16:19:36 634 INFO    71 Shutting down SMPPSim
2026.09.14 16:19:36 634 INFO    71 HTTP Handler exiting
2026.09.14 16:19:36 635 INFO    73 Lifecycle Service (OutboundQueue) is exiting
2026.09.14 16:19:36 637 INFO    71 Halting http server thread
```

Because the sockets are closed while that second response is still being written, the confirming request usually ends without a reply: `curl: (52) Empty reply from server`, or an HTTP code of `000` under `curl -s -w '%{http_code}'`. That is the normal outcome of a successful shutdown, not a failure — check the log or the port rather than the response.

Worth knowing about the confirmation:

- the two requests need not use the same path: `/?shutdown` followed by `/index.htm?shutdown` works, because the pending confirmation belongs to the handler, not to the page;
- anything that renders a page in between cancels it — `?refresh`, and an ordinary request for `/` or any other page as well — and the next `?shutdown` starts over by asking for confirmation again;
- the flag is per handler thread. With `HTTP_THREADS` above 1 the confirming request may be accepted by a different thread, which will just arm its own flag and ask again; leave `HTTP_THREADS` at the shipped `1` if a script is going to stop the instance this way;
- the command has to be the whole query string. Case does not matter, so `?SHUTDOWN` works, but `?shutdown=1` is not recognised;
- the shutdown does not depend on the page being there: even when `DOCROOT` is wrong and the response is a bare 404, the instance still stops.

### Statistics

`?stats` answers with a single line and no markup, which makes it the endpoint to poll from a test:

```bash
curl "http://localhost:8088/?stats"
```

```
submittedok=0,deliveredok=0
```

`submittedok` counts `submit_sm` PDUs accepted with `ESME_ROK`, `deliveredok` counts `deliver_sm` PDUs the simulator delivered to an ESME successfully — delivery receipts included, since those are `deliver_sm` too. The counters run from start-up and are never reset; `?refresh` redraws the control panel but does not zero anything. The full per PDU breakdown, including the error counters, is only on the control panel page.

### Injecting an MO message

`/inject_mo` takes the fields of the `deliver_sm` it should build straight from the query string, under their SMPP names. Nothing is mandatory — whatever is left out keeps the value of the previous injection, which is what makes the form remember what you typed:

```bash
curl "http://localhost:8088/inject_mo?source_addr=07711878787&destination_addr=1000&short_message=Hello&data_coding=0"
```

The message goes into the inbound queue and from there to a bound receiver whose `address_range` matches `destination_addr`; with no receiver bound it waits in the pending queue. `short_message` is URL decoded and then encoded according to `data_coding`, and if the request carries a `format` parameter at all — the form sends `format=yes` — the text is read as a hex string instead. `sm_length` is worked out from the message unless the request sets it. Optional parameters are supported as well, both named ones like `user_message_reference` or `message_payload` and up to seven raw TLVs through `tlv1_tag`, `tlv1_len` and `tlv1_val` up to `tlv7_*`; `www/inject_mo.htm` is the list of everything the form itself sends.

The response is the injection page again, rendered with the values just used and `Message added to SMPPSim InboundQueue OK` as its status message — see [About `INJECT_MO_PAGE`](#about-inject_mo_page) for why that page has to exist. A parameter the simulator cannot parse, a bad number or an unknown encoding, gets `HTTP/1.1 400 REQUEST NOT UNDERSTOOD BY SERVER` and no message is injected.

For MO traffic generated by the simulator itself rather than injected request by request, see [The MO service and `deliver_messages.csv`](#the-mo-service-and-deliver_messagescsv).

### Serving files

`AUTHORISED_FILES` is an allow list of exact paths, and it is the whole access control of the web server: `/` and `/inject_mo` are handled specially, everything else has to be in the list literally. A new page, stylesheet or image dropped into `www` stays invisible until its path is added there.

A request for a path that is not authorised, or one containing `..`, gets no response at all — the connection is simply closed, which `curl` reports as `curl: (52) Empty reply from server` rather than as 400 or 404. An authorised path whose file is missing under `DOCROOT` does get a real `HTTP/1.0 404 Not Found`, with an empty body.

One trap in `DOCROOT`: the handler uses only the last segment of it and resolves that against the working directory, so `DOCROOT=/opt/smppsim/www` makes the server look for `www/index.htm` under whatever directory the JVM was started in, and the control panel answers 404 everywhere else. Keep `DOCROOT=www` and start the simulator from the directory that holds `www`, as all the methods in [Running](#running) do.

## Callback Channel

The callback is a second way out of the simulator, next to the ESME session itself: with `CALLBACK=true` SMPPSim opens a TCP connection of its own to `CALLBACK_TARGET_HOST:CALLBACK_PORT` — `localhost:3333` by default — and pushes a copy of the PDU traffic into it. It is off in every shipped properties file, and it is meant for a test harness that wants to watch the wire without sitting between the client and the simulator, or without turning on the capture files.

The receiving end is a program you run yourself. One is bundled as an example:

```bash
./start_callback_server.sh
```

```
2026.09.14 17:12:27 426 INFO    1 Starting example Callback Server..
2026.09.14 17:12:27 494 INFO    1 Example Callback Server is listening on port 3333
2026.09.14 17:12:29 519 INFO    19 CallbackHandler has accepted a connection
```

Start it before the simulator, or at least expect the log line below until it appears. Then every PDU shows up as a hex dump with its type named:

```
2026.09.14 17:12:39 522 INFO    19 SMPPSim received from ESME
2026.09.14 17:12:39 523 INFO    19 Hex dump (73) bytes:
2026.09.14 17:12:39 524 INFO    19 00000049:0153494D:31000000:40000000:
2026.09.14 17:12:39 525 INFO    19 04000000:00000000:02000101:31323334:
2026.09.14 17:12:39 527 INFO    19 35000101:34343737:30303930:30303030:
2026.09.14 17:12:39 528 INFO    19 00000000:00000000:00000E63:616C6C62:
2026.09.14 17:12:39 528 INFO    19 61636B20:70726F62:65
2026.09.14 17:12:39 528 INFO    19 ====================================
2026.09.14 17:12:39 528 INFO    19 (PDU type was SubmitSm)
```

### The frame

Each PDU is wrapped in a nine byte envelope, so the stream can be cut into messages without parsing SMPP:

| Bytes | Meaning |
|---|---|
| 0–3 | Length of the whole frame, big endian: the PDU length plus 9 |
| 4 | Direction: `1` received from the ESME, `2` sent to the ESME |
| 5–8 | `CALLBACK_ID` in ASCII, which tells apart several instances writing to one receiver |
| 9… | The SMPP PDU exactly as it went over the session socket |

The dump above starts with `00000049` — 73 bytes, the 64 byte SUBMIT_SM plus the envelope — then `01` for the direction and `53494D31`, `SIM1`. The PDU itself begins at `0000004000000004`, a SUBMIT_SM of 64 bytes.

`CALLBACK_ID` has to be exactly four ASCII characters. A longer value is silently truncated to the first four — `SIMULATOR` arrives as `SIMU` — but a shorter one throws `ArrayIndexOutOfBoundsException` out of the middle of PDU processing, and the session it happened on gets no response at all: the client hangs until its own timeout and the simulator never recovers that session.

### What actually reaches the receiver

Despite the direction byte, only one direction is ever sent: everything the simulator receives from an ESME — the binds, SUBMIT_SM, DATA_SM, ENQUIRE_LINK, UNBIND and the rest, each PDU passed on before it is processed. The outbound call exists in `StandardConnectionHandler` but hands over a field that is never assigned, so it is always `null` and `Smsc.callback()` drops it. Nothing the simulator sends — no responses, and no DELIVER_SM from the inbound queue — appears on the callback connection, whatever the `CALLBACK` description in the table below suggests. Use the capture files (`CAPTURE_SMPPSIM_BINARY_TO_FILE` and the decoded log) when you need the other half of the conversation.

### Writing your own receiver

`com.seleniumsoftware.examples` is four small classes and is meant to be copied:

| Class | Role |
|---|---|
| `CallbackServer` | Listens on the port and starts ten `CallbackHandler` threads, all accepting on one socket |
| `CallbackHandler` | Reads the length prefix, reassembles one frame, looks at the direction byte and calls the receiver |
| `CallbackReceivable` | The interface to implement: `received(byte[] pdu)` and `sent(byte[] pdu)` |
| `CallbackReceiver` | The example implementation, which hex dumps the frame and names the PDU type |

The array handed to `received` is the whole frame, envelope included, which is why `CallbackReceiver` reads the `command_id` at offset 16 rather than 4. The example reads the socket a byte at a time and only detects end of file on the fourth length byte, so treat it as a starting point rather than as production code.

### When the receiver is not there

The connection is made from a thread of its own during start-up, so a missing receiver never stops the simulator from starting. It retries once a second and says so:

```
INFO: Callback server not accepting connections - retrying
```

Until it succeeds the callback is simply skipped and the simulator serves SMPP normally.

A receiver that disappears after the connection is up is a different matter. The copy is written from inside PDU processing, in a synchronized method, and on a failed write the simulator reconnects and retries the same frame until it gets through. So the session stalls: a SUBMIT_SM sent while the receiver is down gets no response and the client times out. Everything resumes as soon as the receiver is back, the pending frame goes out and the sessions carry on, but the stall lasts exactly as long as the outage — which makes the callback a poor fit for a receiver that comes and goes, and a reason not to leave `CALLBACK=true` in a properties file used for unattended runs.

## Configuration

SMPPSim takes exactly one command line argument: the path to a properties file. Every property below is read by `SMPPSim.initialise()`, and the effective values are echoed to the log at start-up.

Properties marked **Required** have no default: leaving them out aborts start-up with a parse error. Boolean properties are read with `Boolean.valueOf`, so anything other than `true` (case insensitive) means false, and an absent property means false. The examples are the values used by the shipped `conf/smppsim.props`.

| Property | Description | Example |
|---|---|---|
| `SMPP_PORT` | TCP port the SMPP server listens on. **Required.** | `2775` |
| `SMPP_CONNECTION_HANDLERS` | Number of connection handler threads, which is also the maximum number of concurrent SMPP sessions. **Required.** | `50` |
| `HTTP_PORT` | TCP port of the built-in web interface. **Required.** | `8088` |
| `HTTP_THREADS` | Number of threads serving the web interface. **Required.** | `1` |
| `DOCROOT` | Directory the web interface serves files from. | `www` |
| `AUTHORISED_FILES` | Comma separated whitelist of servable paths. Anything not listed is refused with HTTP 400, so a new web asset has to be added here. | `/css/style.css,/index.htm,/favicon.ico` |
| `INJECT_MO_PAGE` | Path of the MO injection form, redisplayed after every injection. See the note below. | `/inject_mo.htm` |
| `SMSCID` | `system_id` the simulator reports in bind responses. **Required.** | `SMPPSim` |
| `SYSTEM_IDS` | Comma separated list of accepted `system_id` values. | `smppclient1,smppclient2,smppclient3` |
| `PASSWORDS` | Passwords matched positionally against `SYSTEM_IDS`. A different number of elements in the two lists aborts start-up. | `password,password,password` |
| `CONNECTION_HANDLER_CLASS` | Class run by every connection handler thread. Instantiated by name with `Class.forName`, like the two below. | `com.seleniumsoftware.SMPPSim.StandardConnectionHandler` |
| `PROTOCOL_HANDLER_CLASS` | Class that decodes PDUs and builds responses. Point it at the bundled `TestProtocolHandler1`, `2` or `3` to simulate a misbehaving SMSC. | `com.seleniumsoftware.SMPPSim.StandardProtocolHandler` |
| `LIFE_CYCLE_MANAGER` | Class driving message state transitions. | `com.seleniumsoftware.SMPPSim.LifeCycleManager` |
| `MESSAGE_STATE_CHECK_FREQUENCY` | How often, in ms, the outbound queue is swept and message states are reassessed. Default `10000`. | `5000` |
| `MAX_TIME_ENROUTE` | After this many ms a message moves to a final state regardless of the probabilities below. Default `2000`. | `10000` |
| `PERCENTAGE_THAT_TRANSITION` | Probability in percent that a message changes state on a given sweep. Default `75`. | `100` |
| `PERCENTAGE_DELIVERED` | Share of transitions ending in DELIVERED. Default `90`. | `40` |
| `PERCENTAGE_UNDELIVERABLE` | Share ending in UNDELIVERABLE. Default `6`. | `20` |
| `PERCENTAGE_ACCEPTED` | Share ending in ACCEPTED. Default `2`. | `20` |
| `PERCENTAGE_REJECTED` | Share ending in REJECTED. Default `2`. | `20` |
| `DISCARD_FROM_QUEUE_AFTER` | Age in ms after which a message state is dropped from the outbound queue and stops being visible to QUERY_SM. Default `60000`. | `60000` |
| `SIMULATE_VARIABLE_SUBMIT_SM_RESPONSE_TIMES` | Delay SUBMIT_SM responses by a randomised, drifting amount instead of answering immediately. | `false` |
| `ENQUIRE_LINK_RESPONSE_DELAY` | Hold every ENQUIRE_LINK_RESP for this many ms before sending it. `0` answers immediately, which is the current behaviour. A negative value logs a warning and is treated as `0`. Default `0`. | `0` |
| `DROP_ENQUIRE_LINK_RESPONSES` | Never answer ENQUIRE_LINK at all. Takes precedence over the delay above. Defaults to `false` when absent or empty. | `false` |
| `INBOUND_QUEUE_MAX_SIZE` | Capacity of the inbound queue holding MO messages and delivery receipts. Default `1000`. | `1000` |
| `OUTBOUND_QUEUE_MAX_SIZE` | Capacity of the outbound queue holding the state of submitted messages. Default `1000`. | `1000` |
| `DELAYED_INBOUND_QUEUE_PROCESSING_PERIOD` | Interval in `seconds` between retries of messages an ESME rejected with ESME_RMSGQFUL. Default `60`. | `60` |
| `DELAYED_INBOUND_QUEUE_MAX_ATTEMPTS` | How many times such a message is retried before it is discarded. Default `10`. | `100` |
| `DELAY_DELIVERY_RECEIPTS_BY` | Hold receipts for this many ms before queueing them. `0` queues them immediately and the delay service is not started. Default `0`. | `1000` |
| `DELIVERY_RECEIPT_OPTIONAL_PARAMS` | Include the standard v3.4 optional parameters in receipts for clients that bound as 3.4 or later. Defaults to `true` when absent or empty. | `true` |
| `DELIVERY_RECEIPT_TLV` | Vendor TLV appended to every receipt, given as `tag/length/value` in hex. Empty disables it; a value that is not three slash separated parts aborts start-up. | `1403/0A/34343132333435363738` |
| `DELIVER_SM_INCLUDES_USSD_SERVICE_OP` | Carry the `ussd_service_op` TLV of the original submission over into the receipt. | `false` |
| `START_MESSAGE_ID_AT` | First `message_id` to hand out. The literal `random` starts from a random value. Absent from the shipped props file; defaults to `0`. | `random` |
| `MESSAGE_ID_PREFIX` | String prepended to every `message_id`. Absent from the shipped props file; defaults to empty. | `SM` |
| `LOOPBACK` | Turn every SUBMIT_SM into a DELIVER_SM sent back to the submitter, swapping source and destination addresses. Mutually exclusive with `ESME_TO_ESME`. | `FALSE` |
| `ESME_TO_ESME` | Turn every SUBMIT_SM into a DELIVER_SM routed to whichever receiver session's `address_range` matches the destination, leaving the addresses as they are. Mutually exclusive with `LOOPBACK`: enabling both aborts start-up. | `false` |
| `DELIVERY_MESSAGES_PER_MINUTE` | Rate at which canned MO messages are injected. `0` disables the service. **Required.** | `0` |
| `DELIVER_MESSAGES_FILE` | CSV of canned MO messages, one `source,destination,text` per line. Only read when the rate is above zero. | `deliver_messages.csv` |
| `OUTBIND_ENABLED` | Send an OUTBIND to a waiting ESME when an MO arrives with no receiver session bound. | `false` |
| `OUTBIND_ESME_IP_ADDRESS` | Address of that ESME. Read only when outbind is enabled. Default `127.0.0.1`. | `127.0.0.1` |
| `OUTBIND_ESME_PORT` | Port of that ESME. Falls back to `2776` if the value will not parse. | `2776` |
| `OUTBIND_ESME_SYSTEMID` | `system_id` sent in the OUTBIND. Default `smppclient1`. | `smppclient1` |
| `OUTBIND_ESME_PASSWORD` | Password sent in the OUTBIND. Default `password`. | `password` |
| `DECODE_PDUS_IN_LOG` | Log a decoded, field by field form of each PDU alongside the hex dump. | `true` |
| `CAPTURE_SME_BINARY` | Write the raw bytes of PDUs received from clients to a file. | `false` |
| `CAPTURE_SME_BINARY_TO_FILE` | Destination file for the above. | `sme_binary.capture` |
| `CAPTURE_SMPPSIM_BINARY` | Write the raw bytes of PDUs sent by the simulator to a file. | `false` |
| `CAPTURE_SMPPSIM_BINARY_TO_FILE` | Destination file for the above. | `smppsim_binary.capture` |
| `CAPTURE_SME_DECODED` | Write the decoded text form of received PDUs to a file. | `false` |
| `CAPTURE_SME_DECODED_TO_FILE` | Destination file for the above. | `sme_decoded.capture` |
| `CAPTURE_SMPPSIM_DECODED` | Write the decoded text form of sent PDUs to a file. | `false` |
| `CAPTURE_SMPPSIM_DECODED_TO_FILE` | Destination file for the above. | `smppsim_decoded.capture` |
| `CALLBACK` | Copy PDUs to an external TCP callback server. In practice only what the ESME sends reaches it — see [Callback Channel](#callback-channel). | `false` |
| `CALLBACK_TARGET_HOST` | Host of that server. Read only when `CALLBACK` is true. | `localhost` |
| `CALLBACK_PORT` | Port of that server. | `3333` |
| `CALLBACK_ID` | Four ASCII characters written into each callback frame to identify this instance. | `SIM1` |

Notes:

- The four `PERCENTAGE_DELIVERED` / `UNDELIVERABLE` / `ACCEPTED` / `REJECTED` values are cumulative thresholds and should add up to 100.
- All timings are in milliseconds except `DELAYED_INBOUND_QUEUE_PROCESSING_PERIOD`, which is in seconds.
- Capture files are deleted and recreated on every start-up.
- Log destinations are not configured here but through the `java.util.logging` file passed as `-Djava.util.logging.config.file` — see [Logging](#logging).
- A sample callback server is bundled as `com.seleniumsoftware.examples.CallbackServer`; start it with `./start_callback_server.sh` and see [Callback Channel](#callback-channel).

### About `INJECT_MO_PAGE`

The web interface serves its pages through a tiny template mechanism: before a page goes out, every `$$name$$` placeholder in it is replaced with a value. That is how the home page fills in its counters — `$$submit_sm_ok$$`, `$$deliver_sm_err$$` and the rest — and how the injection form remembers what you typed, through `$$source_addr$$`, `$$data_coding$$`, `$$esm_class$$` and a couple of dozen more. One placeholder, `$$message$$`, carries the control panel message, which is where `Message added to SMPPSim InboundQueue OK` appears after a successful injection.

`INJECT_MO_PAGE` names the page that takes part in this twice. Having handled `/inject_mo?...`, the simulator renders that page and returns it as the response, so the browser lands back on the form with the values and the result message filled in. And when the page itself is requested, the simulator recognises the path and forces the rendering path, which a request carrying a query string would otherwise miss and be answered with HTTP 400.

The value therefore has to name a file that exists under `DOCROOT` and is listed in `AUTHORISED_FILES`. Point it at something that is not there and the injection still happens — the message reaches the inbound queue as usual — but the browser gets an empty HTTP 404 instead of the form, which makes the endpoint look broken when it is not.

### The MO service and `deliver_messages.csv`

Besides the injection form, the simulator can originate MO traffic by itself, taking the messages from a file. Set `DELIVERY_MESSAGES_PER_MINUTE` above zero and the service reads `DELIVER_MESSAGES_FILE` at start-up and then sends one message at a time at that rate. The shipped `conf/smppsim.props` leaves the rate at `0`, so the file is unused there; `conf/props.mo` sets it to one a minute, which is the instance the [Testing](#testing) section starts on port 2777.

The service starts lazily, when a receiver session first binds, and stops when the last one goes away — there is no point generating messages nobody can receive.

Each line of the file is one message, with no header:

```
source_addr,destination_addr,short_message
```

The line is split on the first two commas only, so the text may contain commas of its own; the two addresses may not. A line prefixed with `0x` in the text field is read as hexadecimal bytes rather than characters, and the message then goes out with `data_coding` set to `4`, binary. Invalid hex is not fatal: the simulator logs a warning and sends the line as plain text. The bundled file exercises both forms:

```
07711878787,1000,A test message
07711878787,1000,SMPPSim!
07711878787,1000,0x313233343536373839
```

The last line arrives as `123456789` with `data_coding=4`.

Messages are picked at random, not in order, so a long run repeats some and skips others. Watch them arrive with the listening mode of the delivery script:

```bash
smpp-bash/send_deliver_sm.sh -P 2777 -i smppclient -l
```

```
deliver_sm #1: 07711878787 -> 1000, esm_class=0, data_coding=0, 14 bytes
  short_message: A test message
```

Note the destination in the shipped file: `1000`. A receiver only gets these messages if the `address_range` it bound with matches that address, which is why the example above lets the script fall back to its default of `.*`.

### Slow and silent keepalives

`ENQUIRE_LINK_RESPONSE_DELAY` and `DROP_ENQUIRE_LINK_RESPONSES` make the simulator answer the SMPP keepalive late or not at all, which is how a client's own enquire_link timeout and reconnect logic gets exercised.

Both act before the bind state of the session is checked, so the ESME_RINVBNDSTS answer an unbound session gets is delayed or dropped just like a normal one. Dropping wins over delaying: no response is sent and the handler returns straight away. The incoming PDU is still decoded, logged and written to the capture files either way; a dropped answer counts towards `enquire_link_err` in the statistics, since nothing was answered OK.

The delay blocks the connection handler thread of that one session, so while it lasts the simulator reads no further PDUs from that client — which is the point, since that is what a busy SMSC looks like. Other sessions are unaffected, but remember that `SMPP_CONNECTION_HANDLERS` is also the limit on concurrent sessions.

With `ENQUIRE_LINK_RESPONSE_DELAY=3000`, the bundled script shows the delay directly:

```bash
smpp-bash/send_enquire_link.sh -n 2
```

```
enquire_link #1: ESME_ROK, seq=2, 3016.6 ms
enquire_link #2: ESME_ROK, seq=3, 3021.4 ms
2 sent, 2 answered, 0 lost; min/avg/max 3016.6/3019.0/3021.4 ms
```

Lower its timeout below the delay, or set `DROP_ENQUIRE_LINK_RESPONSES=true`, and the pings are reported as lost and the script exits with status 5:

```
enquire_link #1: no answer within 1s
1 sent, none answered
```

## Logging

SMPPSim logs through `java.util.logging`. Its configuration is separate from the properties file and is passed on the command line:

```bash
java -Djava.util.logging.config.file=conf/logging.properties -jar smppsim.jar conf/smppsim.props
```

Every bundled start script already does this. Leave the property out and the JDK's own default applies instead: records go to the console only, in the two line `SimpleFormatter` style, and nothing is written to `log/`.

```
Sep 13, 2026 5:05:08 PM com.seleniumsoftware.SMPPSim.SMPPSim showLegals
INFO: =  SMPPSim Copyright (C) 2006 Selenium Software Ltd
```

With the shipped `conf/logging.properties` the same record is one line, and it is written to both the console and `log/smppsim0.log.0`:

```
2026.09.13 15:37:09 769 INFO    73 Assessing state of 1 messages in the OutboundQueue
```

That layout comes from `com.seleniumsoftware.SMPPSim.LogFormatter`: date, time with milliseconds, level padded to seven characters, the thread id, then the message. The thread id is what tells one SMPP session apart from another in a busy log.

### Parameters

| Property | Meaning | In `conf/logging.properties` |
|---|---|---|
| `handlers` | comma separated list of handlers to install | `FileHandler, ConsoleHandler` |
| `.level` | level for the root logger, the first filter every record passes | `INFO` |
| `<logger>.level` | level for one logger, overriding `.level`; SMPPSim logs everything under `com.seleniumsoftware.smppsim` | not set |
| `java.util.logging.FileHandler.pattern` | path of the log file | `./log/smppsim%u.log` |
| `java.util.logging.FileHandler.limit` | bytes per file before rotating; `0` means no limit | `5000000` |
| `java.util.logging.FileHandler.count` | how many files to rotate through | `10` |
| `java.util.logging.FileHandler.formatter` | how records are laid out | `com.seleniumsoftware.SMPPSim.LogFormatter` |
| `java.util.logging.FileHandler.level` | second filter, applied by the handler; defaults to `ALL` | not set |
| `java.util.logging.FileHandler.append` | append to an existing file instead of truncating it; defaults to `false` | not set |
| `java.util.logging.FileHandler.encoding` | character set of the file; defaults to the platform encoding | not set |
| `java.util.logging.ConsoleHandler.level` | second filter for the console | `INFO` |
| `java.util.logging.ConsoleHandler.formatter` | layout for the console | `com.seleniumsoftware.SMPPSim.LogFormatter` |

The placeholders in `pattern` are the standard ones: `%t` the temporary directory, `%h` the user's home, `%g` the generation number, `%u` a unique number and `%%` a literal percent sign.

Every property whose name ends in `level` takes one of the nine `java.util.logging` levels. Setting a level admits records of that severity and everything above it, so `INFO` also lets `WARNING` and `SEVERE` through:

| Level | Value | What SMPPSim puts here |
|---|---|---|
| `OFF` | — | nothing; switches the logger or handler off entirely |
| `SEVERE` | 1000 | start-up failures: a missing properties file, a port already in use, a malformed `DELIVERY_RECEIPT_TLV` |
| `WARNING` | 900 | rejected PDUs, failed authentication, full queues, exceptions that did not stop the simulator |
| `INFO` | 800 | the default working level: the configuration banner, every PDU as a hex dump and in decoded form, state transitions, queue sizes |
| `CONFIG` | 700 | unused by SMPPSim |
| `FINE` | 500 | two records only, when an object enters or leaves the outbound queue |
| `FINER` | 400 | unused by SMPPSim |
| `FINEST` | 300 | the detailed internal trace: life cycle thresholds, queue decisions, address matching, HTTP argument parsing |
| `ALL` | — | everything; the default for a handler that has no level of its own |

`OFF` and `ALL` are not levels a record can carry, only thresholds. Note how little sits between `INFO` and `FINEST`: dropping to `FINE` or `FINER` gains almost nothing over `INFO`, which is why the tracing recipe below goes straight to `FINEST`.

### Turning on detailed tracing

A record has to pass two filters: the logger level and then the level of each handler. To see the internal tracing — queue decisions, life cycle thresholds, HTTP argument parsing — lower the logger:

```
com.seleniumsoftware.smppsim.level = FINEST
```

That alone sends FINEST records to the file, because `FileHandler` has no level set and so defaults to `ALL`, while the console keeps its `INFO` and stays readable. Lower `java.util.logging.ConsoleHandler.level` as well if you want them on screen too.

```
2026.09.13 17:05:26 778 FINEST  1 transitionThreshold=1.01
2026.09.13 17:05:26 778 FINEST  1 maxTimeEnroute=10000
```

PDU hex dumps and their decoded form are not part of this: they are logged at `INFO` and are switched on and off with `DECODE_PDUS_IN_LOG` in the properties file instead. The `CAPTURE_*` properties write the same traffic to separate files — see [Configuration](#configuration).

### Things that bite

`FileHandler` does not create directories. If `pattern` points somewhere that does not exist, logging fails at start-up and the simulator runs on with console output only — which is why the [Testing](#testing) instructions create `test/test1` and friends before starting the instances.

The file on disk is `smppsim0.log.0`, not `smppsim.log`: `%u` resolves to `0` and, because `count` is greater than one, the generation number is appended as well. Set `count = 1` and the suffix disappears. A `.lck` file sits next to the log while the simulator is running.

`%u` only stays `0` for the first JVM. Start a second instance with the same configuration file and it cannot lock the first file, so it takes `smppsim1.log.0` — which is convenient when running several instances, and surprising when looking for the log of the one that started second.

## Building

The project builds with Ant; there is no Maven or Gradle setup. Dependencies are the prebuilt jars in `lib/`.


```bash
mkdir -p classes
ant -Dclasspath="classes:lib/smpp.jar:lib/junit.jar" \
    -Dant.build.javac.source=8 -Dant.build.javac.target=8 jar
```

This writes `smppsim.jar` to the repository root, replacing the copy that ships with the repo.

Both overrides are needed:

- `-Dclasspath` — the `classpath` property in `build.xml` is written in Windows notation (`${lib}\smpp.jar`, `;` separators) and resolves to nothing on Linux, so `src/java/tests` will not compile without it.
- `-Dant.build.javac.source` / `.target` — keeps the bytecode at class file version 52, so the jar still runs on the Temurin 8 image used by the Dockerfile. A recent JDK would otherwise emit class files the container cannot load.

`build.xml` does not create its output directory, hence the `mkdir`. The build prints about 17 warnings for deprecated constructors (`new Integer(...)` and friends); that is expected.

## Testing

The JUnit suite is an integration suite: it drives three running instances of SMPPSim over SMPP, so start them first. The bundled `starttestservers.sh` does not work as shipped — it assigns `CLASSPATH` without exporting it — so launch the instances directly:

```bash
mkdir -p test/test1 test/test2 test/test3
for n in 1:props.std_test 2:props.test1 3:props.mo; do
  i=${n%%:*}; f=${n#*:}
  nohup java -Djava.net.preferIPv4Stack=true \
    -Djava.util.logging.config.file=conf/logging.properties.test$i \
    -jar smppsim.jar conf/$f &
done
```

They listen on SMPP ports 2775, 2776 and 2777. The `test/test*` directories have to exist beforehand, because the test logging configuration writes there and `FileHandler` does not create missing directories.

Then run the suite, which needs the execute bit set as described under [Running](#running):

```bash
./runtests.sh
```

Expected output:

```
Time: 5.564

OK (25 tests)
```

The tests authenticate as `smppclient` / `password`, which only the `conf/props.*test*` files define — running them against the default `conf/smppsim.props` fails at bind.

Those three instances are worth keeping around for the [test message scripts](https://github.com/krot3232/smpp-bash/) too, because two of them behave differently from the default configuration. The one on 2776 runs `TestProtocolHandler1`, which refuses any destination that is not numeric and so makes `send_submit_multi.sh` report a partially refused response. The one on 2777 runs the MO service, which produces a message a minute from `deliver_messages.csv` for `send_deliver_sm.sh -l` to pick up:

```bash
smpp-bash/send_submit_multi.sh -P 2776 -i smppclient -D "447700900001,not-a-number"
smpp-bash/send_deliver_sm.sh   -P 2777 -i smppclient -l
```

```
deliver_sm #1: 07711878787 -> 1000, esm_class=0, data_coding=0, 4 bytes
  short_message: blah
```

Both need `-i smppclient`: the test configurations accept that account rather than the `smppclient1` the scripts default to.

## Fixes

Two long-standing bugs are fixed in this fork. The bundled `smppsim.jar` has been rebuilt and includes both.

### `address_range` is matched as a search, not as a whole-string match

`StandardProtocolHandler.addressIsServicedByReceiver` compared the destination address of a message against the session's `address_range` using `Matcher.matches()`, which requires the entire address to match the expression. SMPP defines `address_range` as a UNIX regular expression, and SMPPSim behaved that way until 2.6.11, when the dependency on the Apache Regexp library was dropped and the semantics changed by accident.

Consequence: a receiver bound with `address_range` `[0-9]` never received messages addressed to, say, `1000`, so those messages piled up in the pending queue. The bundled JUnit suite hung forever in `SmppsimDeliverSmTests`, which binds exactly such a receiver and waits for the MO messages defined in `deliver_messages.csv`.

Matching now uses `Matcher.find()`, restoring the documented behaviour.

### MO injection with `data_coding=0` no longer fails with HTTP 400

`PduUtilities.getJavaEncoding(0)` returned the string `"default"`, which is not a charset name, so `String.getBytes("default")` threw `UnsupportedEncodingException` while parsing the MO injection form. Injecting a message with the SMSC default alphabet — the default selection on `inject_mo.htm` — returned HTTP 400 and queued nothing.

DCS 0 now maps to `null`, which the calling code already handles as "use the platform default encoding".

### Result

The bundled test suite now runs to completion: `OK (25 tests)`.

## Link
+ Short Message Peer-to-Peer Protocol Specification https://smpp.org/SMPP_v5.pdf
+ SMPPSim official web site http://web.archive.org/web/20190916074856/http://www.seleniumsoftware.com/index.html
+ SMPPSim free simple tutorial https://www.youtube.com/watch?v=C2s6ixCgel0
