#! /usr/bin/env ruby
Dir.chdir(ARGV[0]) do
  fail 'Not a Git working directory root! Usage: gitviz [directory]' unless Dir.exist? '.git'
end

# General Git object
#
# contains:
# - hash (1)
class GObject
  attr_accessor :grayed

  def initialize(hash, delta = nil)
    Dir.chdir(ARGV[0]) do
      @content = `git cat-file -p #{hash}`
    end
    @hash = hash
    @delta = delta
    @grayed = false
  end
end

# Commit object
#
# contains:
# - hash (1)
# - tree (1)
# - parents (*)
# - message (1) - only first line stored
class Commit < GObject
  def initialize(hash, delta = nil)
    super
    @parents = []
    @content.lines.each do |line|
      case line
      when /^tree/
        @tree = line.match(/tree ([a-f0-9]{40})/)[1]
      when /^parent/
        @parents << line.match(/parent ([a-f0-9]{40})/)[1]
      end
    end
    @message = @content.match(/\n\n(.*)\n/)[1]
  end

  def commit_s
    dot = "subgraph cluser_#{@hash} {\n"
    dot << "label = \"#{@hash[0..5]}\""

    dot << "\n}\n"

    dot = "\"#{@hash[0..5]}\" [label = \"#{@hash[0..5]}\\n#{@message[0..10].delete('"')}..\", pos=\"0.0,1.0!\"];\n"
    @parents.each do |parent|
      dot << "\"#{@hash[0..5]}\" -> \"#{parent[0..5]}\";\n"
    end
    dot
  end

  def to_s
    "\"#{@hash[0..5]}\" -> \"#{@tree[0..5]}\";\n"
  end
end

# Tree object
#
# has to contain:
# - hash (1)
# - children (+)
class Tree < GObject
  def initialize(hash, delta = nil)
    super
    @children = {}
    @content.lines.each do |line|
      data = line.match(/([a-f0-9]{40})\t(.*)$/)
      @children[data[2]] = data[1]
    end
  end

  def to_s
    dot = "\"#{@hash[0..5]}\" [label = \"#{@hash[0..5]}\", shape = triangle"
    dot << ', color = gray' if @grayed
    dot << "];\n"
    @children.each do |label, target|
      dot << "\"#{@hash[0..5]}\" -> \"#{target[0..5]}\" [label = \"#{label}\"];\n"
    end
    dot << "\"#{@delta[0..5]}\" -> \"#{@hash[0..5]}\" [label = \"diff\", color = gray, constraint = false];\n" unless @delta.nil?
    dot
  end
end

# Blob object
#
# has to contain:
# - hash
# (content of the blob is not used nor shown)
class Blob < GObject
  def to_s
    dot = "\"#{@hash[0..5]}\" [label = \"#{@hash[0..5]}\", shape = note"
    dot << ', color = gray' if @grayed
    dot << "];\n"
    dot << "\"#{@delta[0..5]}\" -> \"#{@hash[0..5]}\" [label = \"diff\", color = gray, constraint = false];\n" unless @delta.nil?
    dot
  end
end

p 'Processing objects'

obj = {}

# Loose objects
Dir.chdir(ARGV[0]) do
  hashes = Dir['.git/objects/[a-f0-9][a-f0-9]/*'].collect { |p| p.split('/').last(2).join }

  hashes.each do |hash|
    type = `git cat-file -t #{hash}`.strip.capitalize
    obj[hash] = Object.const_get(type).new(hash)
    p hash[0..5]
  end
end

# Packed objects
Dir.chdir(ARGV[0]) do
  packs = Dir['.git/objects/pack/*.idx']

  packs.each do |pack|
    content = `git verify-pack -v #{pack}`
    content.lines.each do |line|
      data = line.match(/^([a-f0-9]{40}) (.{6}) \d* \d* \d*( \d* ([a-f0-9]{40}))?/)
      break if data.nil?
      obj[data[1]] = Object.const_get(data[2].strip.capitalize).new(data[1], data[4])
      obj[data[1]].grayed = true unless data[4].nil?
      p data[1][0..5]
    end
  end
end

File.open('graph', 'w') do |file|
  file.write "digraph G {\n"

  file.write "subgraph cluster {\n"
  file.write obj.select { |_, o| o.class == Commit }.collect { |_, o| o.commit_s }.join
  file.write "}\n"

  file.write "subgraph cluster1 {\n"
  file.write obj.collect { |_, o| o.to_s }.join
  file.write "}\n"
  file.write "}\n"
end

`dot graph -T pdf -o graph.pdf`
