# Rucksack

[![CircleCI](https://img.shields.io/circleci/build/github/busyloop/rucksack?style=flat)](https://circleci.com/gh/busyloop/rucksack) [![GitHub](https://img.shields.io/github/license/busyloop/rucksack)](https://en.wikipedia.org/wiki/MIT_License) [![GitHub release](https://img.shields.io/github/release/busyloop/rucksack.svg)](https://github.com/busyloop/rucksack/releases)


Attach static files to your compiled crystal binary
and access them at runtime.

The attached files are not loaded into memory at any
point in time. Reading them at runtime has the same
performance characteristics as reading them from
the local filesystem.

Rucksack is therefore suitable for true Single File Deployments
with virtually zero runtime overhead.


## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     rucksack:
       github: busyloop/rucksack
   ```

2. Run `shards install`

3. Add the following lines to your `.gitignore`:

   ```
   .rucksack
   .rucksack.toc
   ```

## Usage

To get started best have a peek at the included [webserver example](examples/).

Here is the code:

```crystal
require "http/server"
require "rucksack"

server = HTTP::Server.new do |context|
  path = context.request.path
  path = "/index.html" if path == "/"
  path = "./webroot#{path}"

  begin
    # Here we read the requested file from the Rucksack
    # and write it to the HTTP response. By default Rucksack
    # falls back to direct filesystem access in case the
    # executable has no Rucksack attached.
    rucksack(path).read(context.response.output)
  rescue Rucksack::FileNotFound
    context.response.status = HTTP::Status.new(404)
    context.response.print "404 not found :("
  end
end

address = server.bind_tcp 8080
puts "Listening on http://#{address}"
server.listen

# Here we statically reference the files to be included
# once - otherwise Rucksack wouldn't know what to pack.
{% for name in `find ./webroot -type f`.split('\n') %}
  rucksack({{name}})
{% end %}

```

You can develop and test code that uses Rucksack in the same way as any other crystal code.



## Packing the Rucksack

After compiling your final binary for deployment, a small extra step
is needed to make it self-contained:

```
crystal build --release webserver.cr
cat .rucksack >>webserver
```

The `.rucksack`-file that we append here
is generated during compilation and contains all
files that you referenced with the rucksack()-macro.

The resulting `webserver` executable is now self-contained
and does not require the referenced files to be
present in the filesystem anymore.



## Startup and runtime behavior

By default Rucksack operates in mode 0 (see below).

You can alter its behavior by setting the env var `RUCKSACK_MODE`
to one of the following values:

### `RUCKSACK_MODE=0` (default)

* Rucksack index is read at startup (very fast)

* The rucksack() macro falls back to direct filesystem access
  if the rucksack is missing or doesn't contain the requested file

* File checksums are verified once on first access

* If a requested file can be found neither in the Rucksack nor
  in the local filesystem then `Rucksack::FileNotFound` is raised.

* This mode ensures your app works not only when the Rucksack has
  been appended to your executable but also when it's missing
  and the files are present in the filesystem.

  This is the preferred mode during development as e.g. `crystal spec` and `crystal run` will work as expected.


### `RUCKSACK_MODE=1` (for production)

* Rucksack index is read at startup (very fast)

* Application aborts with exit code 42 if Rucksack is missing or corrupt

* File checksums are verified once on first access

* If a requested file can not be found in the Rucksack
  then `Rucksack::FileNotFound` is raised

* **Prefer this mode for CI and production**. It ensures your app aborts
  at startup in case the Rucksack is missing, rather than later when
  trying to access the files.


### `RUCKSACK_MODE=2` (for the paranoid)

* This is like mode 1, except it also verifies the checksums
  of all attached files at startup
* Application aborts with exit code 42 if Rucksack is missing or corrupt
  or if any file in the Rucksack is corrupt
* If you are worried about potential corruption and can tolerate
  a slightly longer startup delay then this is the mode for you



## API

### `rucksack(path : String).read(output : IO)`

Packs the referenced file at compile time and writes it to the given I/O at runtime.

Example:

```crystal
rucksack("data/hello.txt").read(STDOUT)
```

Files that get referenced in multiple places are of course packed only once.

Please note that when looking up files dynamically at runtime then they need to be referenced
statically at least once elsewhere in your code, otherwise rucksack wouldn't know what to pack.

E.g.:

```
# Dynamic file lookup at runtime
rucksack(ARGV[0]).read(STDOUT)

# Tell rucksack which files should be packed
rucksack("data/hello.txt")
rucksack("data/world.txt")
```

Also keep in mind that Rucksack reads your files directly from the executable at runtime, they are not cached in memory. Do not modify the executable on disk while the app is running.

### `rucksack(path : String).size : UInt64`

Returns the size of a packed file.

### `rucksack(path : String).path : String`

Returns the original path of a packed file.

### `rucksack(path : String).checksum : Slice(UInt8)`

Returns the SHA256 of a packed file.


### Exceptions

#### `Rucksack::FileNotFound`

**In mode 0:**
Is raised when attempting to access a file that exists neither in the Rucksack nor in the filesystem.

**In mode 1 and 2:**
Is raised when attempting to access a file that does not exist in the Rucksack

#### `Rucksack::FileCorrupted`

Is raised when the accessed file doesn't match the stored checksum.
You will never see this in practice unless your executable gets truncated or modified after packing.

## Contributing

1. Fork it (<https://github.com/busyloop/rucksack/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

