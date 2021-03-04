For immediate execution:



# Roadmap

- Update README (get rid of non-http stuff)
- Improve Rack spec compliance, add tests
- Homogenize HTTP 1 and HTTP 2 headers - downcase symbols

- Use `http-2-next` instead of `http-2` for http/2
  - https://gitlab.com/honeyryderchuck/http-2-next
  - Open an issue there, ask what's the difference between the two gems?

## 0.38

- Add more poly CLI commands and options:

  - serve static files from given directory
  - serve from rack up file
  - serve both http and https
  - use custom certificate files for SSL
  - set host address to bind to
  - set port to bind to
  - set forking process count

## 0.39 Working Sinatra application

- app with database access (postgresql)
- benchmarks!
