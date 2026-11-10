require "spec_helper"
require "yaml"

describe "TensorBuzz build config path filter" do
  def unconsumed_by_every_lane
    ["!**/*.md", "!.github/**", "!.gitignore", "!MIT-LICENSE"]
  end

  def unconsumed_by_rspec_lanes_only
    ["!.rubocop.yml", "!/Rakefile"]
  end

  def config
    YAML.load_file(File.expand_path("../tensorbuzz.yml", __dir__))
  end

  def config_file_exists?(name)
    File.exist?(File.expand_path("../#{name}", __dir__))
  end

  def negations(patterns)
    patterns.select { |pattern| pattern.start_with?("!") }
  end

  it "keeps the repository config in one file, named the way the trigger reads it" do
    expect(config_file_exists?("peak_flow.yml")).to be false
    expect(config_file_exists?("tensorbuzz.yml")).to be true
  end

  it "declares paths on every build and never at the root beside a builds map" do
    builds = config["builds"]
    expect(config["paths"]).to be_nil
    expect(builds.size).to eq(4)
    expect(builds.values).to all(satisfy { |build| build["paths"].is_a?(Array) && !build["paths"].empty? })
  end

  it "starts every paths list with the fail-open ** rule" do
    config["builds"].each do |name, build|
      expect(build["paths"].first).to eq("**"), "build #{name} must start with ** so an unknown path still builds"
    end
  end

  it "keeps every negation quoted, because an unquoted !glob is a YAML tag and not a rule" do
    config["builds"].each_value do |build|
      expect(negations(build["paths"])).not_to be_empty
      expect(negations(build["paths"])).to all(be_a(String))
    end
  end

  it "negates only paths this repository proves no lane consumes" do
    allowed = unconsumed_by_every_lane + unconsumed_by_rspec_lanes_only

    config["builds"].each do |name, build|
      unexpected = negations(build["paths"]) - allowed
      expect(unexpected).to be_empty, "build #{name} negates #{unexpected.inspect}, which a lane reads"
    end
  end

  it "keeps the lint lane's own inputs unfiltered" do
    lint_negations = negations(config["builds"]["build_4"]["paths"])
    expect(lint_negations).not_to include("!.rubocop.yml")
    expect(lint_negations).not_to include("!/Rakefile")
  end
end
