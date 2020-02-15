# Compile with:
#
# crystal build --release webserver.cr && cat .rucksack >>webserver

# The resulting binary is then self-contained
# and does not need the referenced files to be
# present in the filesystem anymore.

require "http/server"
require "rucksack"

server = HTTP::Server.new do |context|
  path = context.request.path
  path = "/index.html" if path == "/"
  path = "./webroot#{path}"

  begin
    rucksack(path).read(context.response.output)
  rescue Rucksack::FileNotFound
    context.response.status = HTTP::Status.new(404)
    context.response.print "404 not found :("
  end
end

address = server.bind_tcp 8080
puts "Listening on http://#{address}"
server.listen

# Since we look up files dynamically above
# we have to statically reference them once,
# otherwise Rucksack wouldn't know what to pack.
{% for name in `find ./webroot -type f`.split('\n') %}
  rucksack({{name}})
{% end %}

