require "spec_helper"
require "yaml"

describe "TensorBuzz build config path filter" do
  ROOT = File.expand_path("..", __dir__)

  def config
    YAML.load_file(File.join(ROOT, "tensorbuzz.yml"))
  end

  def negations(patterns)
    patterns.select { |pattern| pattern.start_with?("!") }
  end

  it "keeps the repository config in one file, named the way the trigger reads it" do
    expect(File.exist?(File.join(ROOT, "peak_flow.yml"))).to be false
    expect(File.exist?(File.join(ROOT, "tensorbuzz.yml"))).to be true
  end

  it "declares paths on every build and never at the root beside a builds map" do
    builds = config["builds"]
    expect(config["paths"]).to be nil
    expect(builds.size).to eq(4)
    expect(builds.values).to all(satisfy { |build| build["paths"].is_a?(Array) && !build["paths"].empty? })
  end

  it "starts every paths list with the fail-open ** rule" do
    config["builds"].each do |name, build|
      expect(build["paths"].first).to eq("**"), "build #{name} must start with ** so an unknown path still builds"
    end
  end

  it "keeps every negation quoted, because an unquoted !glob parses as an empty YAML tag and vanishes" do
    config["builds"].each do |name, build|
      expect(negations(build["paths"])).not_to be_empty
      expect(negations(build["paths"])).to all(be_a(String))
    end
  end

  it "negates only paths this repository proves no lane consumes" do
    unconsumed_by_every_lane = ["!**/*.md", "!.github/**", "!.gitignore", "!MIT-LICENSE"]

    config["builds"].each do |name, build|
      extra = negations(build["paths"]) - unconsumed_by_every_lane
      expect(extra).to be_subset(["!.rubocop.yml", "!/Rakefile"]), "build #{name} negates #{extra.inspect}, which is a file a lane reads"
    end
  end

  it "keeps the lint lane's own inputs unfiltered" do
    lint_paths = config["builds"]["build_4"]["paths"]
    expect(negations(lint_paths)).not_to include("!.rubocop.yml")
    expect(negations(lint_paths)).not_to include("!/Rakefile")
  end
end
