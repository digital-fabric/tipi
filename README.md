<p align="center"><img src="docs/tipi-logo.png" /></p>

# Tipi - the All-in-one Web Server for Ruby Apps

[![Gem Version](https://badge.fury.io/rb/tipi.svg)](http://rubygems.org/gems/tipi)
[![Modulation Test](https://github.com/digital-fabric/tipi/workflows/Tests/badge.svg)](https://github.com/digital-fabric/tipi/actions?query=workflow%3ATests)
[![MIT licensed](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/digital-fabric/tipi/blob/master/LICENSE)

## What is Tipi?

Tipi is an integrated, feature-complete HTTP/S server for Ruby applications.
Tipi is built on top of
[Polyphony](https://github.com/digital-fabric/polyphony), a robust,
high-performance library for building highly-concurrent applications in Ruby.
Tipi can be used to serve any Rack application or set of static files directly
without having to employ a reverse-proxy such as Nginx.

## Features

* High-performance, highly concurrent web server based on
  [Polyphony](https://github.com/digital-fabric/polyphony)
* Full support for HTTP/1, HTTP/2, WebSocket protocols
* Built-in SSL termination for secure, encrypted connections
* **Automatic SSL certificates** using ACME providers such as Let's Encrypt (WIP)
* Automatic ALPN protocol selection for serving HTTP/2
* Request and response body streaming for efficient downloads and uploads
* Full support for Rack-based apps

## Benchmarks

Here are the results of an ad-hoc benchmark showing throughput in requests/sec
for different Ruby web servers:

| |tipi|puma|falcon|unicorn|
|-|---:|---:|-----:|------:|
|HTTP/1.1|138629|34573|40714|7438|
|HTTPS/2|52814|?|34226|n/a|

### Methodology

- Each server was run with 4 forked worker processes:
  - Tipi: `examples/rack_server_forked.rb examples/hello.ru` and
    `examples/rack_server_https_forked.rb examples/hello.ru`
  - [Puma](https://github.com/puma/puma): `puma -w 4 examples/hello.ru`
  - [Falcon](https://github.com/socketry/falcon/): `falcon -n 4 -b
    http://localhost:9292/ -c examples/hello.ru`
  - [Unicorn](https://yhbt.net/unicorn/): `unicorn -c u.conf examples/hello.ru`
    with the configuration file containing the directive `worker_processes 4`
- All servers were run on Ruby 2.7.2p137
- The benchmark results were obtained using `wrk -d60 -t4 -c64 <url>`
- Machine specs: i5-8350U@1.7GHzx8 CPU, 8GB of RAM, running Linux kernel version 5.13.7
- Puma with HTTPS: In order to serve HTTPS, Puma needs certificates to be
  created. I'll get around to it eventually for the sake of completeness.
- Unicorn with HTTPS: as far as I could tell Unicorn does not support SSL
  termination. Please let me know if this is not the case.

```
wrk -d60 -t4 -c64 <url>
```

## Documentation

Documentation for Tipi is coming soon...
