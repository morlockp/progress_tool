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
    out = File.read(Dir['*_draft_0.txt'].first)
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

      assert File.exist?('Interleave_Test_draft_0.txt')
      out = File.read(Dir['*_draft_0.txt'].first)
      expected = File.read(File.expand_path('expected_output.txt', __dir__))

      # normalize line endings
      assert_equal expected.gsub("\r\n", "\n"), out.gsub("\r\n", "\n")
    end
  end

  def test_interleave_prepends_single_frontmatter_file
    Dir.chdir(@tmp) do
      File.write('front.txt', "Dramatis Personae\nAlice\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :frontmatter:
          - front.txt
        :title: Frontmatter Test
        :target_words: 100
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
      YAML

      system('rake interleave_txt') or raise 'rake failed'
      out = File.read(Dir['*_draft_0.txt'].first)

      assert out.start_with?("Dramatis Personae\nAlice\n")
      assert out.index("Dramatis Personae") < out.index("** chapter")
    end
  end

  def test_interleave_prepends_multiple_frontmatter_files_in_order
    Dir.chdir(@tmp) do
      File.write('front_a.txt', "First front section\n")
      File.write('front_b.txt', "Second front section\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :frontmatter:
          - front_a.txt
          - front_b.txt
        :title: Frontmatter Test
        :target_words: 100
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
      YAML

      system('rake interleave_txt') or raise 'rake failed'
      out = File.read(Dir['*_draft_0.txt'].first)

      assert out.index("First front section") < out.index("Second front section")
      assert out.index("Second front section") < out.index("** chapter")
    end
  end

  def test_interleave_collects_xxx_lines_before_first_act
    Dir.chdir(@tmp) do
      File.write('fixtures/story_a.txt', <<~TEXT)
        XXX this is one complete
        comment that should be preserved as a single item

        XXX this is a second comment

        * Act 1: shared beginning

        ** chapter 1: first
        one

        XXX A post-act note
      TEXT
      File.write('fixtures/story_b.txt', <<~TEXT)
        XXX this is
        comment number three

        * Act 1: shared beginning

        ** chapter 1: alpha
        alpha
      TEXT
      File.write('front.txt', "Front matter\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_a.txt
          - fixtures/story_b.txt
        :frontmatter:
          - front.txt
        :title: XXX Test
        :target_words: 100
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
      YAML

      system('rake interleave_txt') or raise 'rake failed'
      out = File.read(Dir['*_draft_0.txt'].first)

      first_comment = "XXX A this is one complete comment that should be preserved as a single item"
      second_comment = "XXX A this is a second comment"
      third_comment = "XXX B this is comment number three"

      assert out.index("Front matter") < out.index(first_comment)
      assert out.index(first_comment) < out.index(second_comment)
      assert out.index(second_comment) < out.index(third_comment)
      assert out.index(third_comment) < out.index("* Act 1: shared beginning")
      assert out.index("XXX A post-act note") > out.index("one")
      assert_equal 1, out.scan(/#{Regexp.escape(first_comment)}/).size
      assert_equal 1, out.scan(/#{Regexp.escape(second_comment)}/).size
      assert_equal 1, out.scan(/#{Regexp.escape(third_comment)}/).size
    end
  end

  def test_book_split_keeps_collected_xxx_lines_before_first_act
    Dir.chdir(@tmp) do
      File.write('fixtures/story_a.txt', <<~TEXT)
        XXX pre-act note

        * Act 1: shared beginning

        ** chapter 1: first
        one
      TEXT
      File.write('fixtures/story_b.txt', <<~TEXT)
        XXX pre-act note

        * Act 1: shared beginning

        ** chapter 1: alpha
        alpha
      TEXT
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_a.txt
          - fixtures/story_b.txt
        :title: XXX Book Split Test
        :target_words: 100
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
        :book_split:
          Book One:
            - "1"
      YAML

      system('rake interleave_txt') or raise 'rake failed'
      out = File.read('Book_One.txt')

      assert out.index("XXX A pre-act note") < out.index("XXX B pre-act note")
      assert out.index("XXX B pre-act note") < out.index("* Act 1: shared beginning")
      assert_equal 1, out.scan(/XXX A pre-act note/).size
      assert_equal 1, out.scan(/XXX B pre-act note/).size
    end
  end

  def test_interleave_html_preserves_markdown_frontmatter_semantics
    Dir.chdir(@tmp) do
      File.write('dramatis.md', <<~MD)
        # Dramatis

        - Alice

        - Bob
      MD
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :frontmatter:
          - dramatis.md
        :title: Frontmatter Test
        :target_words: 100
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
      YAML

      system('rake interleave_html') or raise 'rake failed'
      out = File.read(Dir['*_draft_0.html'].first)

      assert_match(/<h1[^>]*>Dramatis<\/h1>/, out)
      assert_match(/<li>Alice<\/li>/, out)
      assert_match(/<li>Bob<\/li>/, out)
      refute_match(/<li><p>Alice<\/p><\/li>/, out)
      assert out.index("Dramatis") < out.index("chapter")
    end
  end

  def test_ich_reports_interleaved_chapters_without_writing_output
    Dir.chdir(@tmp) do
      out = `rake ich`
      assert $?.success?, 'rake ich failed'
      plain_out = out.gsub(/\e\[[0-9;]*m/, "")

      refute Dir['*_draft_0.txt'].any?, 'ich should not write a draft txt file'
      assert_match(/Built interleaved chapters in memory/, plain_out)
      assert_match(/\| interleaved/, plain_out)
      assert_match(/\|\s+1\s+.*\(LOPEZ 1\): One/, plain_out)
      assert_match(/\|\s+2\s+.*\(SPACEX 1\): Alpha/, plain_out)
      assert_match(/\* 3 chapters not done/, plain_out)
    end
  end

  def test_ichv_matches_ich_with_done_lines_removed
    Dir.chdir(@tmp) do
      ich_out = `rake ich`
      assert $?.success?, 'rake ich failed'

      ichv_out = `rake ichv`
      assert $?.success?, 'rake ichv failed'

      expected = ich_out.lines.reject { |line| line.include?("✓") }.join
      assert_equal expected, ichv_out
    end
  end

  def test_interleave_renumbers_chapter_with_parenthetical_before_colon
    Dir.chdir(@tmp) do
      File.write('fixtures/story_a.txt', <<~TEXT)
        ** chapter 1: first
        one

        ** chapter 2 (later): second
        two
      TEXT
      File.write('fixtures/story_b.txt', <<~TEXT)
        ** chapter 1: alpha
        alpha

        ** chapter 2: beta
        beta
      TEXT
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_a.txt
          - fixtures/story_b.txt
        :title: Parenthetical Test
        :target_words: 100
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
      YAML

      system('rake interleave_txt') or raise 'rake failed'
      out = File.read(Dir['*_draft_0.txt'].first)

      assert_match(/\*\* chapter 3 \(A 2\) \(later\): second/, out)
      refute_match(/\*\* chapter 2 \(later\):/, out)
    end
  end

  def test_interleave_includes_act_markers_from_any_source_file
    Dir.chdir(@tmp) do
      File.write('fixtures/story_a.txt', <<~TEXT)
        * Act 1: shared beginning

        ** chapter 1: first
        one
      TEXT
      File.write('fixtures/story_b.txt', <<~TEXT)
        * Act 1: shared beginning

        ** chapter 1: alpha
        alpha

        * Act 2: second-file-only act

        ** chapter 2: beta
        beta
      TEXT
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_a.txt
          - fixtures/story_b.txt
        :title: Any Act Test
        :target_words: 100
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
      YAML

      system('rake interleave_txt') or raise 'rake failed'
      out = File.read(Dir['*_draft_0.txt'].first)

      assert_equal 1, out.scan(/^\* Act 1: shared beginning$/).size
      assert_match(/^\* Act 2: second-file-only act$/m, out)
      assert out.index("* Act 2: second-file-only act") < out.index("beta")
    end
  end

  def test_interleave_keeps_chapters_inside_their_source_act
    Dir.chdir(@tmp) do
      File.write('fixtures/story_a.txt', <<~TEXT)
        * Act 1: shared beginning

        ** chapter 1: a act one
        a one

        * Act 2: later

        ** chapter 2: a act two
        a two
      TEXT
      File.write('fixtures/story_b.txt', <<~TEXT)
        * Act 1: shared beginning

        ** chapter 1: b act one
        b one

        ** chapter 2: b still act one
        b two
      TEXT
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_a.txt
          - fixtures/story_b.txt
        :title: Act Boundary Test
        :target_words: 100
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
      YAML

      system('rake interleave_txt') or raise 'rake failed'
      out = File.read(Dir['*_draft_0.txt'].first)

      assert out.index("b two") < out.index("* Act 2: later")
      assert out.index("* Act 2: later") < out.index("a two")
    end
  end

  def test_renumber_numbers_each_source_file_by_act
    Dir.chdir(@tmp) do
      File.write('fixtures/story_a.txt', <<~TEXT)
        * Act 1: start

        ** chapter 7: first
        one

        ** chapter 9 (note): second
        two

        * Act 2: middle

        ** chapter 42: third
        three

        ** chapter 43: fourth
        four

        * Act 3: end

        ** chapter 99: fifth
        five
      TEXT
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_a.txt
        :title: Renumber Test
        :target_words: 100
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
      YAML

      system('git', 'init', out: File::NULL, err: File::NULL) or raise 'git init failed'
      system('git', 'config', 'user.email', 'test@example.com') or raise 'git config failed'
      system('git', 'config', 'user.name', 'Test User') or raise 'git config failed'
      system('git', 'add', '.') or raise 'git add failed'
      system('git', 'commit', '-m', 'initial', out: File::NULL, err: File::NULL) or raise 'git commit failed'

      system('rake renumber') or raise 'rake renumber failed'
      out = File.read('fixtures/story_a.txt')

      assert_match(/^\*\* chapter 1: first$/m, out)
      assert_match(/^\*\* chapter 2 \(note\): second$/m, out)
      assert_match(/^\*\* chapter 10: third$/m, out)
      assert_match(/^\*\* chapter 11: fourth$/m, out)
      assert_match(/^\*\* chapter 20: fifth$/m, out)
    end
  end

  def test_renumber_skips_to_next_free_decade_when_act_has_more_than_ten_chapters
    Dir.chdir(@tmp) do
      chapters = (1..12).map do |idx|
        "** chapter #{idx + 30}: act one #{idx}\nbody #{idx}\n"
      end.join("\n")
      File.write('fixtures/story_a.txt', <<~TEXT)
        * Act 1: start

        #{chapters}
        * Act 2: middle

        ** chapter 90: act two first
        later
      TEXT
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_a.txt
        :title: Renumber Decade Test
        :target_words: 100
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
      YAML

      system('git', 'init', out: File::NULL, err: File::NULL) or raise 'git init failed'
      system('git', 'config', 'user.email', 'test@example.com') or raise 'git config failed'
      system('git', 'config', 'user.name', 'Test User') or raise 'git config failed'
      system('git', 'add', '.') or raise 'git add failed'
      system('git', 'commit', '-m', 'initial', out: File::NULL, err: File::NULL) or raise 'git commit failed'

      system('rake renumber') or raise 'rake renumber failed'
      out = File.read('fixtures/story_a.txt')

      assert_match(/^\*\* chapter 12: act one 12$/m, out)
      assert_match(/^\*\* chapter 20: act two first$/m, out)
    end
  end

  def test_renumber_aborts_when_source_file_has_git_diff
    Dir.chdir(@tmp) do
      File.write('fixtures/story_a.txt', <<~TEXT)
        ** chapter 7: first
        one
      TEXT
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_a.txt
        :title: Renumber Dirty Test
        :target_words: 100
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
      YAML

      system('git', 'init', out: File::NULL, err: File::NULL) or raise 'git init failed'
      system('git', 'config', 'user.email', 'test@example.com') or raise 'git config failed'
      system('git', 'config', 'user.name', 'Test User') or raise 'git config failed'
      system('git', 'add', '.') or raise 'git add failed'
      system('git', 'commit', '-m', 'initial', out: File::NULL, err: File::NULL) or raise 'git commit failed'

      File.open('fixtures/story_a.txt', 'a') { |f| f.puts "dirty edit" }

      refute system('rake renumber'), 'rake renumber should fail when target file has git diff'
      assert_match(/dirty edit/, File.read('fixtures/story_a.txt'))
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
