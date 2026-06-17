require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'zip'

class InterleaveDocTest < Minitest::Test
  REPO_RAKEFILE = File.join(File.dirname(__FILE__), '..', 'rakefile')

  def setup
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
    FileUtils.remove_entry(@tmp) if @tmp && Dir.exist?(@tmp)
  end

  def test_interleave_doc_creates_file
    Dir.chdir(@tmp) do
      system('rake interleave_doc') or raise 'rake failed'
      assert File.exist?('output.docx'), "output.docx should exist"
    end
  end

  def test_docx_has_heading_hierarchy
    Dir.chdir(@tmp) do
      system('rake interleave_doc') or raise 'rake failed'
      
      # Extract content.xml from the DOCX (it's a ZIP file)
      content_xml = extract_docx_content('output.docx')
      
      # Check for heading styles in the document
      # Pandoc uses w:pStyle elements with heading styles
      assert content_xml.include?('Heading'), "Document should contain heading styles"
    end
  end

  def test_docx_has_acts_and_chapters
    Dir.chdir(@tmp) do
      system('rake interleave_doc') or raise 'rake failed'
      
      content_xml = extract_docx_content('output.docx')
      
      # Check for Act content
      assert content_xml.include?('Beginning'), "Document should contain Act text"
      
      # Check for Chapter content
      assert content_xml.include?('chapter'), "Document should contain chapter text"
    end
  end

  def test_docx_preserves_paragraph_breaks
    Dir.chdir(@tmp) do
      system('rake interleave_doc') or raise 'rake failed'
      
      content_xml = extract_docx_content('output.docx')
      
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
      
      content_xml = extract_docx_content('output.docx')
      
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

      content_xml = extract_docx_content('output.docx')

      assert content_xml.include?('Dramatis'), "Document should contain frontmatter heading text"
      assert content_xml.include?('Alice'), "Document should contain frontmatter bullet text"
      assert content_xml.include?('<w:numPr>'), "Document should preserve markdown bullets as Word list structure"
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

      content_xml = extract_docx_content('output.docx')

      assert content_xml.include?('Test Novel'), "Document should contain title page title"
      assert content_xml.include?('Test Author'), "Document should contain title page author"
      assert content_xml.index('Test Novel') < content_xml.index('Test Author')
      assert content_xml.index('Test Author') < content_xml.index('Dramatis')
      assert content_xml.index('Dramatis') < content_xml.index('Beginning')
      assert content_xml.include?('<w:jc w:val="center"/>'), "Title page headings should be centered"
      assert content_xml.include?('<w:br w:type="page"/>'), "Title page should end with a page break"
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

      content_xml = extract_docx_content('output.docx')

      assert content_xml.index('Test Author') < content_xml.index('Front One')
      assert content_xml.index('Front One') < content_xml.index('Front Two')
      assert content_xml.index('Front Two') < content_xml.index('Beginning')
      assert_equal 3, content_xml.scan('<w:br w:type="page"/>').size
      refute_match(/DOCX_FRONTMATTER_PAGE_BREAK_/, content_xml)
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
      assert File.exist?('output.docx'), "output.docx should still exist"
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

      styles_xml = extract_docx_file('output.docx', 'word/styles.xml')
      assert_match(/w:ascii="Garamond"/, styles_xml)
      assert_match(/w:color w:val="000000"/, styles_xml)
      assert_match(/w:style w:type="paragraph" w:default="1" w:styleId="Normal".*?w:sz w:val="20"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageTitle".*?w:sz w:val="46"/m, styles_xml)

      content_xml = extract_docx_content('output.docx')
      assert_match(/<w:pStyle w:val="TitlePageTitle"\/>.*?Test/m, content_xml)
      assert_match(/<w:pStyle w:val="TitlePageAuthor"\/>.*?Test Author/m, content_xml)
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

      styles_xml = extract_docx_file('output.docx', 'word/styles.xml')
      assert_match(/w:ascii="Garamond"/, styles_xml)
      assert_match(/w:color w:val="000000"/, styles_xml)
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
