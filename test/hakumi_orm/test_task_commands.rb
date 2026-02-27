# typed: false
# frozen_string_literal: true

require "test_helper"
require "hakumi_orm/task_commands"
require "tmpdir"
require "stringio"

class TestTaskCommands < HakumiORM::TestCase
  def setup
    @original_seeds_path = HakumiORM.config.seeds_path
  end

  def teardown
    HakumiORM.config.seeds_path = @original_seeds_path
  end

  test "run_seed warns when seed file is missing" do
    Dir.mktmpdir do |dir|
      HakumiORM.config.seeds_path = File.join(dir, "missing_seeds.rb")
      out, err = capture_io { HakumiORM::TaskCommands.run_seed }

      assert_empty out
      assert_includes err, "Seed file not found"
    end
  end

  test "run_seed loads seed file and prints completion message" do
    Dir.mktmpdir do |dir|
      seed_path = File.join(dir, "seeds.rb")
      marker_path = File.join(dir, "seed_marker.txt")
      File.write(seed_path, "File.write(#{marker_path.inspect}, \"ok\")\n")
      HakumiORM.config.seeds_path = seed_path

      out, = capture_io { HakumiORM::TaskCommands.run_seed }

      assert_equal "ok", File.read(marker_path)
      assert_includes out, "Seed completed from"
      assert_includes out, seed_path
    end
  end
end
