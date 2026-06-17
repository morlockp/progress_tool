require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'yaml'
require 'zip'

class DefaultTaskTest < Minitest::Test
  REPO_RAKEFILE = File.expand_path('../rakefile', __dir__)

  def setup
    @tmp = Dir.mktmpdir('default_task_test')
    FileUtils.cp REPO_RAKEFILE, File.join(@tmp, 'rakefile')
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp && Dir.exist?(@tmp)
  end

  def test_default_book_split_uses_act_aware_diff_counts
    Dir.chdir(@tmp) do
      File.write('story.txt', <<~TEXT)
        * Act 1: before the storm

        ** chapter 1: old title
        alpha beta

        * Act 2-A: after the storm

        ** chapter 2: second title
        one two three
      TEXT

      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - story.txt
        :title: Test Novel
        :target_words: 1000
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
        :book_split:
          Book One:
            - 1
          Book Two:
            - 2-a
      YAML

      system('git', 'init', out: File::NULL, err: File::NULL) or raise 'git init failed'
      system('git', 'config', 'user.email', 'test@example.com') or raise 'git config failed'
      system('git', 'config', 'user.name', 'Test User') or raise 'git config failed'
      system('git', 'add', '.') or raise 'git add failed'
      system('git', 'commit', '-m', 'initial', out: File::NULL, err: File::NULL) or raise 'git commit failed'

      File.write('story.txt', <<~TEXT)
        * Act 1: before the storm

        ** chapter 1: new title should not count
        alpha beta gamma delta

        * Act 2-A: after the storm

        ** chapter 2: second title
        one two
      TEXT

      out = `rake default`

      assert_match(/Book One/m, out)
      assert_match(/Book Two/m, out)
      assert_match(/Book One.*today's word delta: \+2\s+\(\+4 -2\)/m, out)
      assert_match(/Book Two.*today's word delta: -1\s+\(\+2 -3\)/m, out)
    end
  end

  def test_init_writes_frontmatter_and_default_docx_reference
    Dir.chdir(@tmp) do
      out = `rake init`
      assert $?.success?, 'rake init failed'
      assert_match(/created file/, out)

      config = YAML.load_file('.rakefile.yaml')
      assert_equal [], config[:frontmatter]
      assert_equal '.default.docx', config[:docx_reference]
      assert_equal 'author goes here', config[:author]
      assert File.exist?('.default.docx')

      styles_xml = extract_docx_file('.default.docx', 'word/styles.xml')
      assert_match(/w:ascii="Garamond"/, styles_xml)
      assert_match(/w:color w:val="000000"/, styles_xml)
      assert_match(/w:style w:type="paragraph" w:default="1" w:styleId="Normal".*?w:sz w:val="20"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="Heading1".*?<w:b\/>.*?w:sz w:val="30"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="Heading2".*?<w:b\/>.*?w:sz w:val="24"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageTitle".*?w:spacing w:before="4320".*?<w:b\/>.*?w:sz w:val="46"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageAuthor".*?w:spacing w:before="1440".*?<w:b\/>.*?w:sz w:val="22"/m, styles_xml)
    end
  end

  def test_init_docx_overwrites_default_docx_only
    Dir.chdir(@tmp) do
      File.write('.default.docx', 'old')
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - story.txt
        :title: Sentinel
        :target_words: 1000
        :date_start: '2026-03-02'
      YAML
      original_config = File.read('.rakefile.yaml')

      out = `rake init_docx`
      assert $?.success?, 'rake init_docx failed'
      assert_match(/created file .\/\.default\.docx/, out)
      assert_equal original_config, File.read('.rakefile.yaml')

      styles_xml = extract_docx_file('.default.docx', 'word/styles.xml')
      assert_match(/TitlePageTitle/, styles_xml)
      assert_match(/w:sz w:val="46"/, styles_xml)
    end
  end

  def test_word_graph_uses_git_history
    Dir.chdir(@tmp) do
      system('git', 'init', out: File::NULL, err: File::NULL) or raise 'git init failed'
      system('git', 'config', 'user.email', 'test@example.com') or raise 'git config failed'
      system('git', 'config', 'user.name', 'Test User') or raise 'git config failed'

      File.write('story_ancient.txt', "prehistory words should not count\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - story_ancient.txt
        :title: Test Novel
        :target_words: 1000
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
      YAML
      system({ 'GIT_AUTHOR_DATE' => '2026-02-01T12:00:00-0500', 'GIT_COMMITTER_DATE' => '2026-02-01T12:00:00-0500' }, 'git', 'add', '.') or raise 'git add failed'
      system({ 'GIT_AUTHOR_DATE' => '2026-02-01T12:00:00-0500', 'GIT_COMMITTER_DATE' => '2026-02-01T12:00:00-0500' }, 'git', 'commit', '-m', 'prehistory', out: File::NULL, err: File::NULL) or raise 'git commit failed'

      File.write('story_old.txt', "one two\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - ./story_old.txt
        :title: Test Novel
        :target_words: 1000
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
      YAML

      system({ 'GIT_AUTHOR_DATE' => '2026-03-02T12:00:00-0500', 'GIT_COMMITTER_DATE' => '2026-03-02T12:00:00-0500' }, 'git', 'add', '.') or raise 'git add failed'
      system({ 'GIT_AUTHOR_DATE' => '2026-03-02T12:00:00-0500', 'GIT_COMMITTER_DATE' => '2026-03-02T12:00:00-0500' }, 'git', 'commit', '-m', 'initial', out: File::NULL, err: File::NULL) or raise 'git commit failed'

      File.write('story_new.txt', "one two three four five\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - story_new.txt
        :title: Test Novel
        :target_words: 1000
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
      YAML
      system({ 'GIT_AUTHOR_DATE' => '2026-03-05T12:00:00-0500', 'GIT_COMMITTER_DATE' => '2026-03-05T12:00:00-0500' }, 'git', 'add', '.') or raise 'git add failed'
      system({ 'GIT_AUTHOR_DATE' => '2026-03-05T12:00:00-0500', 'GIT_COMMITTER_DATE' => '2026-03-05T12:00:00-0500' }, 'git', 'commit', '-m', 'more', out: File::NULL, err: File::NULL) or raise 'git commit failed'

      out = `rake word_graph`

      assert_match(/Test Novel word history/, out)
      assert_match(/2026-03-02: 2 words/, out)
      assert_match(/2026-03-05: 5 words/, out)
      assert_match(/net: \+3 words/, out)
      assert_match(/\*/, out)
      refute_match(/2026-02-01/, out)

      cache_path = File.join('.git', 'word_graph_cache.yml')
      assert File.exist?(cache_path)
      cache = YAML.load_file(cache_path)
      assert_equal 1, cache["version"]
      assert_equal 2, cache["commits"].size
      assert_equal [2, 5], cache["commits"].values.map { |entry| entry["words"] }

      first_commit = cache["commits"].keys.first
      cache["commits"][first_commit]["words"] = 9
      File.write(cache_path, cache.to_yaml)

      out = `rake word_graph`
      assert_match(/2026-03-02: 9 words/, out)
    end
  end

  private

  def extract_docx_file(docx_file, path)
    Zip::File.open(docx_file) do |zip|
      entry = zip.find_entry(path)
      return entry.get_input_stream.read if entry
    end
    ""
  end
end
