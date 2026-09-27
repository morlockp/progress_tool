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

  def test_duplicate_rakefile_keys_abort_before_task_runs
    Dir.chdir(@tmp) do
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - story.txt
        :title: First Title
        :title: Second Title
        :target_words: 1000
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
      YAML

      out = `rake default 2>&1`

      refute $?.success?, 'rake should fail for duplicate config keys'
      assert_match(/\*\*\* ERROR: duplicate keys in \.\/\.rakefile\.yaml/, out)
      assert_match(/title duplicated at line 4 \(first seen on line 3\)/, out)
    end
  end

  def test_duplicate_rakefile_keys_abort_for_symbol_and_plain_key_variants
    Dir.chdir(@tmp) do
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - story.txt
        :frontmatter:
          - dramatis.txt
        frontmatter: []
        :title: Test Novel
        :target_words: 1000
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
      YAML

      out = `rake default 2>&1`

      refute $?.success?, 'rake should fail for equivalent duplicate config keys'
      assert_match(/frontmatter duplicated at line 5 \(first seen on line 3\)/, out)
    end
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
      assert_equal [], config[:never_hyphenate]
      assert_equal 'full', config[:frontmatter_layout]
      assert_nil config[:aftermatter_about_the_author]
      assert_nil config[:aftermatter_stay_connected]
      assert_equal [], config[:aftermatter_other]
      assert_nil config[:epigraph]
      assert_nil config[:timeline]
      assert_nil config[:dramatis_personae]
      assert_nil config[:kickstarter_backers]
      assert_equal true, config[:toc]
      assert_equal '.default.docx', config[:docx_reference]
      assert_equal '.docx_styles.yaml', config[:docx_styles]
      assert_equal 'author goes here', config[:author]
      assert_equal 0, config[:draft]
      assert File.exist?('.docx_styles.yaml')
      assert File.exist?('.default.docx')

      docx_styles = YAML.load_file('.docx_styles.yaml')
      assert_equal 'Garamond', docx_styles['font']
      assert_equal 6, docx_styles['page']['width_inches']
      assert_equal 9, docx_styles['page']['height_inches']
      assert_equal 11, docx_styles['styles']['normal']['size']
      assert_equal 40, docx_styles['styles']['heading_1']['size']
      assert_equal 36, docx_styles['styles']['title_page_title']['size']
      assert_equal 20, docx_styles['styles']['title_page_author']['size']
      assert_equal 12, docx_styles['styles']['heading_3']['size']
      assert_equal 16, docx_styles['styles']['title_page_series_title']['size']
      assert_equal 14, docx_styles['styles']['title_page_conjunction']['size']
      assert_equal 22, docx_styles['styles']['title_page_book_title']['size']
      assert_equal 12, docx_styles['styles']['title_page_split_author']['size']
      assert_equal 11, docx_styles['styles']['title_page_publisher']['size']
      assert_equal 20, docx_styles['styles']['half_title_series_title']['size']
      assert_equal 14, docx_styles['styles']['half_title_conjunction']['size']
      assert_equal 28, docx_styles['styles']['half_title_book_title']['size']
      %w[
        title_page_title
        title_page_author
        title_page_series_title
        title_page_conjunction
        title_page_book_title
        title_page_split_author
        title_page_publisher
        half_title_series_title
        half_title_conjunction
        half_title_book_title
      ].each do |style_name|
        assert_equal 0, docx_styles['styles'][style_name]['first_line_indent_inches'], "#{style_name} should not inherit paragraph indents"
      end
      assert_equal 'single', docx_styles['styles']['normal']['line_spacing']
      assert_equal 0.2, docx_styles['styles']['normal']['first_line_indent_inches']
      assert_equal true, docx_styles['page_numbers']['enabled']
      assert_equal 'footer', docx_styles['page_numbers']['position']
      assert File.exist?(File.join('assets', 'morlock_publishing_logo.png'))

      styles_xml = extract_docx_file('.default.docx', 'word/styles.xml')
      document_xml = extract_docx_file('.default.docx', 'word/document.xml')
      settings_xml = extract_docx_file('.default.docx', 'word/settings.xml')
      footer_odd_xml = extract_docx_file('.default.docx', 'word/footer1.xml')
      footer_even_xml = extract_docx_file('.default.docx', 'word/footer2.xml')
      rels_xml = extract_docx_file('.default.docx', 'word/_rels/document.xml.rels')
      assert_match(/w:ascii="Garamond"/, styles_xml)
      assert_match(/w:color w:val="000000"/, styles_xml)
      assert_match(/w:style w:type="paragraph" w:default="1" w:styleId="Normal".*?<w:jc w:val="left"\/>.*?<w:ind w:firstLine="288"\/>.*?w:line="240".*?w:sz w:val="22"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="BodyText".*?<w:ind w:firstLine="288"\/>.*?w:sz w:val="22"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="FirstParagraph".*?w:firstLine="0".*?w:sz w:val="22"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="Compact".*?w:firstLine="0".*?w:after="0"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="Heading1".*?<w:b\/>.*?w:sz w:val="80"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="Heading2".*?<w:b\/>.*?w:sz w:val="30"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="Heading3".*?<w:outlineLvl w:val="2"\/>.*?<w:b\/>.*?w:sz w:val="24"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="FrontmatterHeading1".*?<w:b\/>.*?w:sz w:val="24"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="FrontmatterHeading2".*?<w:b\/>.*?w:sz w:val="24"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="FrontmatterHeading1".*?w:after="200"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="FrontmatterHeading2".*?w:after="200"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageTitle".*?w:spacing w:before="2880".*?<w:b\/>.*?w:sz w:val="72"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageAuthor".*?w:spacing w:before="1440".*?<w:b\/>.*?w:sz w:val="40"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageTitle".*?<w:suppressAutoHyphens\s*\/>/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageAuthor".*?<w:suppressAutoHyphens\s*\/>/m, styles_xml)
      assert_match(/w:pgSz w:w="8640" w:h="12960"/, document_xml)
      assert_match(/w:pgMar w:top="1138" w:right="1138" w:bottom="1426" w:left="1138"/, document_xml)
      assert_match(/w:footerReference w:type="default" r:id="rIdFooterOdd"/, document_xml)
      assert_match(/w:footerReference w:type="even" r:id="rIdFooterEven"/, document_xml)
      assert_match(/w:mirrorMargins/, settings_xml)
      assert_match(/w:evenAndOddHeaders/, settings_xml)
      assert_match(/PAGE/, footer_odd_xml)
      assert_match(/PAGE/, footer_even_xml)
      assert_match(/Target="footer1.xml"/, rels_xml)
      assert_match(/Target="footer2.xml"/, rels_xml)
    end
  end

  def test_init_docx_overwrites_default_docx_only
    Dir.chdir(@tmp) do
      File.write('.default.docx', 'old')
      File.write('.docx_styles.yaml', <<~YAML)
        ---
        font: Courier New
        styles:
          title_page_title:
            size: 28
      YAML
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
      assert_match(/created file .\/\.docx_styles\.yaml/, out)
      assert_match(/created file .\/\.default\.docx/, out)
      assert_equal original_config, File.read('.rakefile.yaml')

      styles_xml = extract_docx_file('.default.docx', 'word/styles.xml')
      assert_match(/TitlePageTitle/, styles_xml)
      assert_match(/w:ascii="Courier New"/, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageTitle".*?w:sz w:val="56"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageTitle".*?<w:suppressAutoHyphens\s*\/>/m, styles_xml)
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

  def test_git_uses_revision_progress_as_commit_message_across_target_files
    Dir.chdir(@tmp) do
      system('git', 'init', out: File::NULL, err: File::NULL) or raise 'git init failed'
      system('git', 'config', 'user.email', 'test@example.com') or raise 'git config failed'
      system('git', 'config', 'user.name', 'Test User') or raise 'git config failed'

      File.write('part_one.txt', "one two\n")
      File.write('part_two.txt', "three four <----\n")
      File.write('audit.txt', "This must not override revision mode.\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - part_one.txt
          - part_two.txt
        :title: Test Novel
        :target_words: 100
        :date_start: '2026-03-02'
        :chapter_head_tag: '** chapter'
      YAML

      out = `rake git 2>&1`

      assert $?.success?, out
      assert_match(/Committing with message: 80\.00% revised/, out)
      assert_equal '80.00% revised', `git log -1 --pretty=%s`.strip
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
