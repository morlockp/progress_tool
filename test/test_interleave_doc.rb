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
end
