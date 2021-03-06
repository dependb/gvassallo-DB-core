# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser/yarn_lockfile_parser"

RSpec.describe Dependabot::NpmAndYarn::FileParser::YarnLockfileParser do
  subject(:yarn_lockfile_parser) do
    described_class.new(lockfile: yarn_lockfile)
  end
  let(:yarn_lockfile) do
    Dependabot::DependencyFile.new(
      name: "yarn.lock",
      content: yarn_lockfile_content
    )
  end
  let(:yarn_lockfile_content) do
    fixture("yarn_lockfiles", yarn_lockfile_fixture_name)
  end
  let(:yarn_lockfile_fixture_name) { "other_package.lock" }

  describe "#parse" do
    subject(:lockfile) { yarn_lockfile_parser.parse }

    it "parses the lockfile" do
      expect(lockfile).to eq(
        "etag@^1.0.0" => {
          "version" => "1.8.0",
          "resolved" => "https://registry.yarnpkg.com/etag/-/etag-"\
                        "1.8.0.tgz#41ae2eeb65efa62268aebfea83ac7d79299b0111"
        },
        "lodash@^1.2.1" => {
          "version" => "1.3.1",
          "resolved" => "https://registry.yarnpkg.com/lodash/-/lodash-"\
                        "1.3.1.tgz#a4663b53686b895ff074e2ba504dfb76a8e2b770"
        }
      )
    end

    context "with multiple requirements sharing a version resolution" do
      let(:yarn_lockfile_fixture_name) { "yarn_file_path_resolutions.lock" }

      it "expands lockfile requirements sharing the same version resolution" do
        first = lockfile.find { |o| o.first == "sprintf-js@~1.0.2" }
        second = lockfile.find do |o|
          o.first == "sprintf-js@file:./mocks/sprintf-js"
        end
        # Share same version reqirement
        expect(first.last).to equal(second.last)
        expect(lockfile.map(&:first)).to contain_exactly(
          "argparse@^1.0.7", "esprima@^4.0.0", "js-yaml@^3.13.1",
          "sprintf-js@file:./mocks/sprintf-js", "sprintf-js@~1.0.2"
        )
      end
    end

    context "with invalid lockfile" do
      let(:yarn_lockfile_fixture_name) { "bad_content.lock" }

      it "handles the error" do
        expect(lockfile).to eq({})
      end
    end
  end
end
