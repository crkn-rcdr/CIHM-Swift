# CIHM::Swift

Perl code that interfaces with Swift.

## Testing

### With docker-compose

```
$ docker-compose -f docker-compose.test.yml up --abort-on-container-exit --build
```

### Locally (useful for quick development)

```
# install local dependencies
$ carton install

# pull and run picoswiftstack image
$ docker pull swiftstack/picoswiftstack:latest
$ docker run --name pico --rm -d -p 22222:8080 swiftstack/picoswiftstack:latest

# run tests
$ carton exec prove -lr t

# stop picoswiftstack
$ docker stop pico
```
