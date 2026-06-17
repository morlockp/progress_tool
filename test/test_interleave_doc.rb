require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'zip'

class InterleaveDocTest < Minitest::Test
  REPO_RAKEFILE = File.join(File.dirname(__FILE__), '..', 'rakefile')

  def setup
    @old_skip_docx_toc_refresh = ENV['RAKEFILE_SKIP_DOCX_TOC_REFRESH']
    ENV['RAKEFILE_SKIP_DOCX_TOC_REFRESH'] = '1'
    test_dir = File.dirname(__FILE__)
    fixtures_dir = File.join(test_dir, 'fixtures')
    yaml_path = File.join(fixtures_dir, '.rakefile.yaml')
    @tmp = Dir.mktmpdir('interleave_doc_test')
    # copy fixtures into tmp dir
    FileUtils.mkdir_p(File.join(@tmp, 'fixtures'))
    Dir.glob(File.join(fixtures_dir, '*'), File::FNM_DOTMATCH).each do |file|
      next if File.basename(file) =~ /^\.\.?$/  # skip . and ..
      FileUtils.cp file, File.join(@tmp, 'fixtures')
    end
    # copy test rakefile from repo
    FileUtils.cp REPO_RAKEFILE, File.join(@tmp, 'rakefile')
    # copy config into tmp dir root
    FileUtils.cp yaml_path, File.join(@tmp, '.rakefile.yaml')
  end

  def teardown
    if @old_skip_docx_toc_refresh.nil?
      ENV.delete('RAKEFILE_SKIP_DOCX_TOC_REFRESH')
    else
      ENV['RAKEFILE_SKIP_DOCX_TOC_REFRESH'] = @old_skip_docx_toc_refresh
    end
    FileUtils.remove_entry(@tmp) if @tmp && Dir.exist?(@tmp)
  end

  def test_interleave_doc_creates_file
    Dir.chdir(@tmp) do
      system('rake interleave_doc') or raise 'rake failed'
      assert File.exist?('Interleave_Test_draft_0.docx'), "draft docx should exist"
    end
  end

  def test_interleave_doc_uses_configured_draft_number_in_filename
    Dir.chdir(@tmp) do
      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :title: Filename Test
        :draft: 7
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)

      system('rake interleave_doc') or raise 'rake failed'

      assert File.exist?('Filename_Test_draft_7.docx')
      assert File.exist?('Filename_Test_draft_7.html')
      refute File.exist?('output.docx')
    end
  end

  def test_docx_has_heading_hierarchy
    Dir.chdir(@tmp) do
      system('rake interleave_doc') or raise 'rake failed'
      
      # Extract content.xml from the DOCX (it's a ZIP file)
      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)
      
      # Check for heading styles in the document
      # Pandoc uses w:pStyle elements with heading styles
      assert content_xml.include?('Heading'), "Document should contain heading styles"
    end
  end

  def test_docx_has_acts_and_chapters
    Dir.chdir(@tmp) do
      system('rake interleave_doc') or raise 'rake failed'
      
      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)
      
      # Check for Act content
      assert content_xml.include?('Beginning'), "Document should contain Act text"
      
      # Check for Chapter content
      assert content_xml.include?('chapter'), "Document should contain chapter text"
    end
  end

  def test_docx_preserves_paragraph_breaks
    Dir.chdir(@tmp) do
      system('rake interleave_doc') or raise 'rake failed'
      
      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)
      
      # DOCX stores paragraphs as <w:p> elements
      # Count the number of paragraphs
      paragraph_count = content_xml.scan(/<w:p/).length
      
      # Should have multiple paragraphs (Acts, Chapters, and content paragraphs)
      assert paragraph_count > 3, "Document should have multiple paragraphs, got #{paragraph_count}"
    end
  end

  def test_docx_preserves_italics
    Dir.chdir(@tmp) do
      # Create fixture with italicized text
      File.write('fixtures/story_with_italics.txt', <<~TEXT)
        * Act 1: The _Beginning_

        ** chapter 1: Test
        This has _italicized text_ in it.
      TEXT
      
      # Update config to use the new file (use same format as original)
      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_with_italics.txt
        :title: Test
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)
      
      system('rake interleave_doc') or raise 'rake failed'
      
      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)
      
      # Pandoc converts markdown-style italics to Word's italic format
      # Look for text runs with italic emphasis (w:i element)
      assert content_xml.include?('<w:i/>') || content_xml.include?('<w:i'), "Document should contain italic formatting"
    end
  end

  def test_docx_preserves_markdown_frontmatter_structure
    Dir.chdir(@tmp) do
      File.write('dramatis.md', <<~MD)
        # Dramatis

        - Alice

        - Bob
      MD

      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :frontmatter:
          - dramatis.md
        :title: Test
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)

      system('rake interleave_doc') or raise 'rake failed'

      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)

      assert content_xml.include?('Dramatis'), "Document should contain frontmatter heading text"
      assert content_xml.include?('Alice'), "Document should contain frontmatter bullet text"
      assert content_xml.include?('<w:numPr>'), "Document should preserve markdown bullets as Word list structure"
      refute_match(/DOCX_FRONTMATTER_PAGE_BREAK_/, content_xml)
    end
  end

  def test_docx_title_page_comes_before_frontmatter
    Dir.chdir(@tmp) do
      File.write('dramatis.md', <<~MD)
        # Dramatis

        - Alice
      MD

      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :frontmatter:
          - dramatis.md
        :title: Test Novel
        :author: Test Author
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)

      system('rake interleave_doc') or raise 'rake failed'

      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)

      assert content_xml.include?('Test Novel'), "Document should contain title page title"
      assert content_xml.include?('Test Author'), "Document should contain title page author"
      assert content_xml.index('Test Novel') < content_xml.index('Test Author')
      assert content_xml.index('Test Author') < content_xml.index('DOCX_TOC_INSERT')
      assert_match(/Test Author.*?<w:p><w:r><w:br w:type="page"\/><\/w:r><\/w:p>.*?DOCX_TOC_INSERT/m, content_xml)
      assert content_xml.index('DOCX_TOC_INSERT') < content_xml.index('Dramatis')
      assert content_xml.index('Dramatis') < content_xml.index('Beginning')
      assert content_xml.include?('<w:jc w:val="center"/>'), "Title page headings should be centered"
      assert content_xml.include?('<w:br w:type="page"/>'), "Title page should end with a page break"
    end
  end

  def test_docx_title_page_has_page_break_before_toc
    Dir.chdir(@tmp) do
      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :title: Test Novel
        :author: Test Author
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)

      system('rake interleave_doc') or raise 'rake failed'

      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)
      paragraphs = content_xml.scan(/<w:p\b.*?<\/w:p>/m)
      author_idx = paragraphs.index { |paragraph| paragraph.include?('Test Author') }
      toc_idx = paragraphs.index { |paragraph| paragraph.include?('DOCX_TOC_INSERT') }

      refute_nil author_idx, "title page author paragraph should exist"
      refute_nil toc_idx, "TOC marker paragraph should exist"
      assert_equal author_idx + 2, toc_idx
      assert_match(/<w:br w:type="page"\/>/, paragraphs[author_idx + 1])
      refute_match(/Test Author|DOCX_TOC_INSERT/, paragraphs[author_idx + 1])
    end
  end

  def test_docx_has_table_of_contents_after_title_page
    Dir.chdir(@tmp) do
      File.write('dramatis.md', <<~MD)
        # Dramatis

        ## Frontmatter Group

        - Alice
      MD

      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :frontmatter:
          - dramatis.md
        :title: Test Novel
        :author: Test Author
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)

      system('rake interleave_doc') or raise 'rake failed'

      docx_file = Dir['*_draft_0.docx'].first
      content_xml = extract_docx_content(docx_file)
      settings_xml = extract_docx_file(docx_file, 'word/settings.xml')

      assert content_xml.index('Test Author') < content_xml.index('DOCX_TOC_INSERT')
      assert content_xml.index('DOCX_TOC_INSERT') < content_xml.index('Dramatis')
      assert content_xml.index('Dramatis') < content_xml.index('Act 1')
      assert content_xml.index('Frontmatter Group') < content_xml.index('w:name="RakefileManuscriptBody"')
      assert content_xml.index('w:name="RakefileManuscriptBody"') < content_xml.index('Act 1')
      refute_match(/DOCX_MANUSCRIPT_START|DOCX_MANUSCRIPT_END/, content_xml)
      assert_match(/<w:pStyle w:val="FrontmatterHeading1"\s*\/>.*?Dramatis/m, content_xml)
      assert_match(/<w:pStyle w:val="FrontmatterHeading2"\s*\/>.*?Frontmatter Group/m, content_xml)
      assert_match(/<w:pStyle w:val="Heading1"\s*\/>.*?Act 1/m, content_xml)
      assert_match(/<w:bookmarkStart w:id="\d+" w:name="chapter-1"/, content_xml)
      assert_match(/<w:bookmarkStart w:id="\d+" w:name="chapter-2"/, content_xml)
      assert_match(/<w:updateFields w:val="true"\/>/, settings_xml)
    end
  end

  def test_docx_page_breaks_between_title_frontmatter_and_chapters
    Dir.chdir(@tmp) do
      File.write('front_one.md', "# Front One\n\nalpha\n")
      File.write('front_two.txt', "Front Two\n\nbeta\n")

      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :frontmatter:
          - front_one.md
          - front_two.txt
        :title: Test Novel
        :author: Test Author
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)

      system('rake interleave_doc') or raise 'rake failed'

      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)

      assert content_xml.index('Test Author') < content_xml.index('Front One')
      assert content_xml.index('Front One') < content_xml.index('Front Two')
      assert content_xml.index('Front Two') < content_xml.index('Beginning')
      assert_equal 9, content_xml.scan('<w:br w:type="page"/>').size
      refute_match(/DOCX_FRONTMATTER_PAGE_BREAK_|DOCX_TITLE_PAGE_BREAK|DOCX_ACT_PAGE_BREAK|DOCX_CHAPTER_PAGE_BREAK/, content_xml)
    end
  end

  def test_docx_places_collected_xxx_after_frontmatter_before_manuscript
    Dir.chdir(@tmp) do
      File.write('fixtures/story_a.txt', <<~TEXT)
        XXX pre-act
        note

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
      File.write('front.md', "# Front\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_a.txt
          - fixtures/story_b.txt
        :frontmatter:
          - front.md
        :title: XXX Novel
        :author: Test Author
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML

      system('rake interleave_doc') or raise 'rake failed'

      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)

      assert content_xml.index('Front') < content_xml.index('XXX A pre-act note')
      assert content_xml.index('XXX A pre-act note') < content_xml.index('XXX B pre-act note')
      assert content_xml.index('XXX B pre-act note') < content_xml.index('Act 1')
      assert_equal 1, content_xml.scan(/XXX A pre-act note/).size
      assert_equal 1, content_xml.scan(/XXX B pre-act note/).size
    end
  end

  def test_interleave_doc_falls_back_when_reference_docx_is_missing
    Dir.chdir(@tmp) do
      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :docx_reference: missing-reference.docx
        :title: Test
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)

      out = `rake interleave_doc 2>&1`

      assert $?.success?, 'rake interleave_doc should fall back when reference file is missing'
      assert_match(/DOCX reference file missing-reference\.docx not found/, out)
      assert File.exist?(Dir['*_draft_0.docx'].first.to_s), "output.docx should still exist"
    end
  end

  def test_interleave_doc_uses_generated_reference_docx_styles
    Dir.chdir(@tmp) do
      system('rake init') or raise 'rake init failed'
      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :docx_reference: .default.docx
        :author: Test Author
        :title: Test
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)

      system('rake interleave_doc') or raise 'rake interleave_doc failed'

      docx_file = Dir['*_draft_0.docx'].first
      styles_xml = extract_docx_file(docx_file, 'word/styles.xml')
      document_xml = extract_docx_file(docx_file, 'word/document.xml')
      header_xml = extract_docx_file(docx_file, 'word/header1.xml')
      assert_match(/w:ascii="Times New Roman"/, styles_xml)
      assert_match(/w:color w:val="000000"/, styles_xml)
      assert_match(/w:style w:type="paragraph" w:default="1" w:styleId="Normal".*?<w:ind w:firstLine="720"\s*\/>.*?w:line="480".*?w:sz w:val="24"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="Heading1".*?w:sz w:val="60"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageTitle".*?w:sz w:val="72"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageAuthor".*?w:sz w:val="40"/m, styles_xml)
      assert_match(/w:pgSz w:w="12240" w:h="15840"/, document_xml)
      assert_match(/w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/, document_xml)
      assert_match(/PAGE/, header_xml)

      content_xml = extract_docx_content(docx_file)
      assert_match(/<w:pStyle w:val="TitlePageTitle"\/>.*?Test/m, content_xml)
      assert_match(/<w:pStyle w:val="TitlePageAuthor"\/>.*?Test Author/m, content_xml)
      assert_match(/Test Author.*?<w:p><w:r><w:br w:type="page"\/><\/w:r><\/w:p>.*?DOCX_TOC_INSERT/m, content_xml)
    end
  end

  def test_interleave_doc_uses_reference_docx_by_default
    Dir.chdir(@tmp) do
      system('rake init') or raise 'rake init failed'
      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :title: Test
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)

      system('rake interleave_doc') or raise 'rake interleave_doc failed'

      styles_xml = extract_docx_file(Dir['*_draft_0.docx'].first, 'word/styles.xml')
      assert_match(/w:ascii="Times New Roman"/, styles_xml)
      assert_match(/w:color w:val="000000"/, styles_xml)
    end
  end

  def test_interleave_doc_regenerates_default_docx_when_styles_change
    Dir.chdir(@tmp) do
      system('rake init') or raise 'rake init failed'
      File.write('.docx_styles.yaml', <<~YAML)
        ---
        font: Courier New
        page:
          margin_left_inches: 1.25
        styles:
          normal:
            size: 12
            line_spacing: single
          heading_1:
            size: 18
          title_page_title:
            size: 30
      YAML
      old_time = Time.now - 60
      File.utime(old_time, old_time, '.default.docx')

      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :title: Test
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)

      system('rake interleave_doc') or raise 'rake interleave_doc failed'

      reference_styles_xml = extract_docx_file('.default.docx', 'word/styles.xml')
      reference_document_xml = extract_docx_file('.default.docx', 'word/document.xml')
      output_styles_xml = extract_docx_file(Dir['*_draft_0.docx'].first, 'word/styles.xml')
      assert_match(/w:ascii="Courier New"/, reference_styles_xml)
      assert_match(/w:style w:type="paragraph" w:default="1" w:styleId="Normal".*?w:sz w:val="24"/m, reference_styles_xml)
      assert_match(/w:style w:type="paragraph" w:default="1" w:styleId="Normal".*?w:line="240"/m, reference_styles_xml)
      assert_match(/w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1800"/, reference_document_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="Heading1".*?w:sz w:val="36"/m, output_styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageTitle".*?w:sz w:val="60"/m, output_styles_xml)
    end
  end

  private

  def extract_docx_content(docx_file)
    # DOCX is a ZIP archive
    content = nil
    Zip::File.open(docx_file) do |zip|
      entry = zip.find_entry('word/document.xml')
      if entry
        content = entry.get_input_stream.read
      end
    end
    content || ""
  end

  def extract_docx_file(docx_file, path)
    content = nil
    Zip::File.open(docx_file) do |zip|
      entry = zip.find_entry(path)
      content = entry.get_input_stream.read if entry
    end
    content || ""
  end
end
