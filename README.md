# Rucksack

Attach static files to your compiled crystal binary
and access them at runtime.

The attached files are not loaded into memory at any
point in time. Reading them at runtime has about the
same performance characteristics as reading them from
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
  rescue
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

## Contributing

1. Fork it (<https://github.com/busyloop/rucksack/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

