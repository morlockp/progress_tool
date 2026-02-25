require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

class InterleaveTest < Minitest::Test
  REPO_RAKEFILE = File.expand_path('../rakefile', __dir__)

  def setup
    @tmp = Dir.mktmpdir('interleave_test')
    Dir.chdir(@tmp) do
      # copy fixtures into tmp dir
      FileUtils.mkdir_p('fixtures')
      FileUtils.cp Dir[File.expand_path('fixtures/*', __dir__)], 'fixtures'
      # copy test rakefile from repo
      FileUtils.cp REPO_RAKEFILE, 'rakefile'
      # copy config into tmp dir root
      FileUtils.cp File.expand_path('fixtures/.rakefile.yaml', __dir__), '.rakefile.yaml'
    end
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp && Dir.exist?(@tmp)
  end

  def test_interleave_generates_expected_output
    Dir.chdir(@tmp) do
      # run rake task
      system('rake interleave_txt') or raise 'rake failed'

      out = File.read('output.txt')
      expected = File.read(File.expand_path('expected_output.txt', __dir__))

      # normalize line endings
      assert_equal expected.gsub("\r\n", "\n"), out.gsub("\r\n", "\n")
    end
  end

  def test_act_mismatch_fails
    Dir.chdir(@tmp) do
      # overwrite config to point at mismatch fixtures
      File.write('.rakefile.yaml', <<~YAML)
:target_files:
  - fixtures/bad_act_mismatch_1.txt
  - fixtures/bad_act_mismatch_2.txt
:title: "Bad Act Mismatch"
:target_words: 1000
:chapter_head_tag: '** chapter'
YAML

      # expect rake task to fail due to mismatched Act lines
      refute system('rake interleave_txt'), 'rake should fail for mismatched Act lines'
    end
  end

  def test_invalid_star_line_fails
    Dir.chdir(@tmp) do
      # overwrite config to point at invalid star fixture
      File.write('.rakefile.yaml', <<~YAML)
:target_files:
  - fixtures/bad_invalid_star_1.txt
:title: "Bad Invalid Star"
:target_words: 1000
:chapter_head_tag: '** chapter'
YAML

      # expect rake task to fail due to invalid '*' line
      refute system('rake interleave_txt'), 'rake should fail for invalid "*" lines'
    end
  end
end
