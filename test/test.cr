require "../src/rucksack.cr"

checksums = {} of String => Slice(UInt8)

{% for path in `find ./fixtures -type f`.chomp.split('\n') %}
  c = Rucksack::Checksummer.new
  File.open({{path}}) do |fd|
    IO.copy(fd, c)
  end
  checksums[{{path}}] = c.final

  rucksack({{path}})
{% end %}

checksums.each do |file, checksum|
  c = Rucksack::Checksummer.new
  rucksack(file).read(c)
  if checksum != c.final
    puts
    puts "ERROR: Checksum mismatch #{file}"
    exit 1
  end

  if rucksack(file).size != File.size(file)
    puts
    puts "ERROR: Size mismatch #{file}"
    exit 1
  end
end

c = Rucksack::Checksummer.new
rucksack("./fixtures/cat3.txt").read(c)
if checksums["./fixtures/cat3.txt"] != c.final
  puts
  puts "ERROR: Meow. :("
  exit 1
end

raised = false
begin
  c = Rucksack::Checksummer.new
  file = "non_existing_file"
  rucksack(file).read(c)
rescue Rucksack::FileNotFound
  raised = true
end

unless raised
  puts
  puts "ERROR: Missing file not handled correctly"
  exit 1
end

puts "OK"
