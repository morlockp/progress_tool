  def test_arrows_are_removed_from_output
    Dir.chdir(@tmp) do
      # Add a chapter with arrows in the text
      File.write('fixtures/arrows.txt', <<~TEXT)
        ** chapter 1: arrowy
        This is a line <== with an arrow.
        <=== This line starts with arrows.
        Normal line.
      TEXT
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/arrows.txt
        :title: Arrow Test
        :target_words: 100
        :chapter_head_tag: '** chapter'
      YAML
      system('rake interleave_txt') or raise 'rake failed'
      out = File.read('output.txt')
      # Assert no arrows remain
      refute_match(/<==+/, out, 'Output should not contain any arrows like <==, <===, etc.')
      # Assert the rest of the text is present
      assert_match(/This is a line  with an arrow\./, out)
      assert_match(/^ This line starts with arrows\./m, out)
      assert_match(/Normal line\./, out)
    end
  end
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

  def test_size_cutoff_force_done_tag
    Dir.chdir(@tmp) do
      # create a tiny chapter with the force_done tag to mark it complete
      File.write('fixtures/short.txt', <<~TEXT)
        ** chapter 1: tiny
        AAA-chapter-complete
      TEXT
      File.write('.rakefile.yaml', <<~YAML)
:target_files:
  - fixtures/short.txt
:title: Test
:target_words: 1000
:date_start: '2026-03-02'
:chapter_head_tag: '** chapter'
:size_cuttoff_chapter: 100
:size_cutoff_force_done: 'AAA-chapter-complete'
YAML
      out = `rake chapters`
      # '✓' indicates done status for chapter 1
      assert_match /\b1\s+✓/, out
    end
  end

  def test_size_cutoff_force_incomplete_tag
    Dir.chdir(@tmp) do
      # create a long chapter with force_incomplete tag so it shows not done
      long_text = "word " * 200
      File.write('fixtures/long.txt', "** chapter 1: long\n#{long_text} force_incomplete_tag\n")
      File.write('.rakefile.yaml', <<~YAML)
:target_files:
  - fixtures/long.txt
:title: Test
:target_words: 1000
:date_start: '2026-03-02'
:chapter_head_tag: '** chapter'
:size_cuttoff_chapter: 50
:size_cutoff_force_incomplete: 'force_incomplete_tag'
YAML
      out = `rake chapters`
      assert_match /\b1\s+/, out
      refute_match /\b1\s+✓/, out
    end
  end
end
