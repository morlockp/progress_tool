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

  def test_interleave_doc_removes_colons_from_output_filename
    Dir.chdir(@tmp) do
      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :title: "Aristillus:123"
        :draft: 7
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)

      system('rake interleave_doc') or raise 'rake failed'

      assert File.exist?('Aristillus123_draft_7.docx')
      assert File.exist?('Aristillus123_draft_7.html')
      refute File.exist?('Aristillus:123_draft_7.docx')
      refute File.exist?('Aristillus:123_draft_7.html')
    end
  end

  def test_docx_has_heading_hierarchy
    Dir.chdir(@tmp) do
      system('rake interleave_doc') or raise 'rake failed'
      
      # Extract content.xml from the DOCX (it's a ZIP file)
      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first).dup.force_encoding("UTF-8")
      
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
      File.write('other_books.md', <<~MD)
        # Other Books by Test Author

        ## Series One

        - Book One
      MD
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

  def test_docx_preserves_markdown_frontmatter_line_breaks
    Dir.chdir(@tmp) do
      File.write('quote.md', <<~MD)
        *first line
        second line
        third line*
      MD

      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_lopez.txt
        :frontmatter:
          - quote.md
        :title: Test
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)

      system('rake interleave_doc') or raise 'rake failed'

      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)

      assert_operator content_xml.scan(/<w:br\b[^>]*>/).size, :>=, 2
    end
  end

  def test_docx_applies_timeline_style_to_marked_frontmatter_file
    Dir.chdir(@tmp) do
      File.write('timeline.md', <<~MD)
        # Timeline

        - 2051: Anti gravity developed
        - 2165: Escape from Io begins
      MD

      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :frontmatter:
          - file: timeline.md
            style: timeline
        :title: Test
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)

      system('rake interleave_doc') or raise 'rake failed'

      docx_file = Dir['*_draft_0.docx'].first
      content_xml = extract_docx_content(docx_file)
      styles_xml = extract_docx_file(docx_file, 'word/styles.xml')

      assert_match(/w:style w:type="paragraph" w:styleId="FrontmatterTimeline".*?w:sz w:val="20"/m, styles_xml)
      assert_match(/<w:pStyle w:val="FrontmatterHeading1"\s*\/>.*?Timeline/m, content_xml)
      assert_match(/<w:pStyle w:val="FrontmatterTimeline"\s*\/>.*?2051/m, content_xml)
      assert_match(/<w:pStyle w:val="FrontmatterTimeline"\s*\/>.*?2165/m, content_xml)
      refute_match(/DOCX_FRONTMATTER_TIMELINE_START|DOCX_FRONTMATTER_TIMELINE_END/, content_xml)
    end
  end

  def test_docx_title_page_comes_before_frontmatter
    Dir.chdir(@tmp) do
      File.write('other_books.md', <<~MD)
        # Other Books by Test Author

        Book One
      MD
      File.write('dramatis.md', <<~MD)
        # Dramatis

        - Alice
      MD

      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :other_books: other_books.md
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
      generated_html = File.read(Dir['*_draft_0.html'].first)

      assert content_xml.include?('Test Novel'), "Document should contain title page title"
      assert content_xml.include?('Test Author'), "Document should contain title page author"
      assert content_xml.include?('Morlock Publishing'), "Document should contain generated publisher page"
      assert content_xml.include?(Time.now.year.to_s), "Document should contain generated publisher year"
      title_positions = content_xml.enum_for(:scan, /Test Novel/).map { Regexp.last_match.begin(0) }
      assert_equal 2, title_positions.size
      assert title_positions[0] < content_xml.index('Other Books by Test Author')
      assert content_xml.index('Other Books by Test Author') < title_positions[1]
      title_page_author_position = content_xml.index('Test Author', title_positions[1])
      assert title_positions[1] < title_page_author_position
      assert title_page_author_position < content_xml.index('Morlock Publishing')
      assert content_xml.index('Morlock Publishing') < content_xml.index('DOCX_TOC_INSERT')
      assert_match(/Test Author.*?Morlock Publishing.*?<w:sectPr><w:type w:val="nextPage"\/>.*?<\/w:sectPr>.*?DOCX_TOC_INSERT/m, content_xml)
      assert content_xml.index('DOCX_TOC_INSERT') < content_xml.index('Dramatis')
      assert_equal 1, content_xml.scan('Other Books by Test Author').size
      half_title_verso_xml = content_xml[content_xml.index('Other Books by Test Author')...title_positions[1]]
      assert_match(/Book.*?One/m, half_title_verso_xml)
      assert_match(/<w:pStyle w:val="OtherBooksHeading1"\s*\/>/, content_xml)
      assert_match(/<w:pStyle w:val="OtherBooksTitle"\s*\/>/, half_title_verso_xml)
      assert_match(/<w:i\s*\/>/, half_title_verso_xml)
      refute_match(/<w:numPr>/, half_title_verso_xml)
      assert_match(/<p style="text-align: center;"><em>Book One<\/em><\/p>/, generated_html)
      refute_match(/<li>Book One<\/li>/, generated_html)
      assert content_xml.index('Dramatis') < content_xml.index('Beginning')
      assert content_xml.include?('<w:jc w:val="center"/>'), "Title page headings should be centered"
      assert_match(/<w:sectPr><w:type w:val="nextPage"\/>.*?<\/w:sectPr>/m, content_xml, "Title page should end with a new section")
      assert docx_entry_names(Dir['*_draft_0.docx'].first).any? { |name| name.start_with?('word/media/') }, "publisher logo should be embedded"
    end
  end

  def test_docx_title_page_contains_publisher_page_before_section_break
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
      publisher_idx = paragraphs.index { |paragraph| paragraph.include?('Morlock Publishing') }

      refute_nil author_idx, "title page author paragraph should exist"
      refute_nil toc_idx, "TOC marker paragraph should exist"
      refute_nil publisher_idx, "generated publisher paragraph should exist"
      assert_equal author_idx + 1, publisher_idx
      assert publisher_idx < toc_idx
      section_idx = (publisher_idx...toc_idx).find { |idx| paragraphs[idx].include?('<w:sectPr') }
      refute_nil section_idx, "title page section break should exist before TOC"
      assert_match(/<w:sectPr><w:type w:val="nextPage"\/>.*?<\/w:sectPr>/m, paragraphs[section_idx])
      refute_match(/w:headerReference|w:footerReference|w:pgNumType/, paragraphs[section_idx])
      refute_match(/Test Author|Morlock Publishing|DOCX_TOC_INSERT/, paragraphs[section_idx])
    end
  end

  def test_docx_generates_configured_copyright_page_with_credits
    Dir.chdir(@tmp) do
      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_lopez.txt
        :title: Test Novel
        :author: Test Author
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
        :copyright_page:
          year: 2026
          holder: Morlock Publishing
          publisher: Morlock Publishing
          publisher_urls:
            - morlockpublishing.com
            - https://www.patreon.com/cw/morlockp
            - https://twitter.com/MorlockP
          printed_in: the United States of America
          isbn:
            paperback: 978-1-234
            ebook: 978-1-235
          credits:
            cover design: Jennifer Corcoran
            beta readers:
              - Larry Prince
              - Andrew Doonan
              - Salim Blume
      YAML
      File.write('.rakefile.yaml', yaml_content)

      system('rake interleave_doc') or raise 'rake failed'

      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first).dup.force_encoding("UTF-8")

      assert content_xml.index('Morlock Publishing') < content_xml.index('Copyright © 2026 Morlock Publishing')
      assert content_xml.index('Copyright © 2026 Morlock Publishing') < content_xml.index('DOCX_TOC_INSERT')
      assert_match(/TEST NOVEL.*?Copyright © 2026 Morlock Publishing/m, content_xml)
      assert_match(/<w:pStyle w:val="CopyrightTitle"\s*\/>.*?TEST NOVEL/m, content_xml)
      assert_match(/<w:pStyle w:val="CopyrightBody"\s*\/>.*?All rights reserved\./m, content_xml)
      assert_match(/without written permission from the publisher and copyright holder\./m, content_xml)
      assert_match(/Morlock Publishing.*?morlockpublishing\.com.*?patreon\.com\/cw\/morlockp.*?twitter\.com\/MorlockP/m, content_xml)
      assert_match(/<w:pStyle w:val="CopyrightPublisher"\s*\/>.*?Morlock Publishing/m, content_xml)
      assert_match(/Paperback ISBN: 978-1-234/, content_xml)
      assert_match(/Ebook ISBN: 978-1-235/, content_xml)
      assert_match(/Cover design by Jennifer Corcoran\./, content_xml)
      assert_match(/Beta readers: Larry Prince, Andrew Doonan, Salim Blume/, content_xml)
      assert_match(/Printed in the United States of America/, content_xml)
      refute_match(/First edition/, content_xml)
      refute_match(/DOCX_COPYRIGHT_/, content_xml)
    end
  end

  def test_interleave_doc_reports_default_toc_location_when_not_configured
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

      out = `rake interleave_doc 2>&1`

      assert $?.success?, 'rake interleave_doc should succeed'
      assert_match(/:TOC not specified in :frontmatter; adding in default location/, out)
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

  def test_docx_places_toc_where_frontmatter_marker_appears
    Dir.chdir(@tmp) do
      File.write('quote.txt', "Opening Quote\n")
      File.write('dramatis.md', "# Dramatis\n\n- Alice\n")

      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :frontmatter:
          - quote.txt
          - :TOC
          - dramatis.md
        :title: Test Novel
        :author: Test Author
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)

      out = `rake interleave_doc 2>&1`

      assert $?.success?, 'rake interleave_doc should succeed'
      refute_match(/:TOC not specified in :frontmatter/, out)

      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)

      assert content_xml.index('Test Author') < content_xml.index('Opening Quote')
      assert content_xml.index('Opening Quote') < content_xml.index('DOCX_TOC_INSERT')
      assert content_xml.index('DOCX_TOC_INSERT') < content_xml.index('Dramatis')
      assert content_xml.index('Dramatis') < content_xml.index('Act 1')
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

      docx_file = Dir['*_draft_0.docx'].first
      content_xml = extract_docx_content(docx_file)
      rels_xml = extract_docx_file(docx_file, 'word/_rels/document.xml.rels')
      odd_footer_id = rels_xml[/Id="([^"]+)"[^>]*Target="footer1\.xml"/, 1]
      even_footer_id = rels_xml[/Id="([^"]+)"[^>]*Target="footer2\.xml"/, 1]

      assert content_xml.index('Test Author') < content_xml.index('Front One')
      assert content_xml.index('Morlock Publishing') < content_xml.index('Front One')
      assert content_xml.index('Front One') < content_xml.index('Front Two')
      assert content_xml.index('Front Two') < content_xml.index('Beginning')
      assert_equal 10, content_xml.scan('<w:br w:type="page"/>').size
      sections = content_xml.scan(/<w:sectPr\b.*?<\/w:sectPr>/m)
      assert_equal 3, sections.size
      title_section, frontmatter_section, body_section = sections
      assert_match(/<w:type w:val="nextPage"\/>/, title_section)
      refute_match(/w:headerReference|w:footerReference|w:pgNumType/, title_section)
      assert_match(/<w:type w:val="oddPage"\/>/, frontmatter_section)
      assert_match(/<w:footerReference w:type="default" r:id="#{Regexp.escape(odd_footer_id)}"\/>/, frontmatter_section)
      refute_match(/<w:footerReference w:type="even"/, frontmatter_section)
      assert_match(/<w:pgNumType w:fmt="lowerRoman" w:start="2"\/>/, frontmatter_section)
      assert_match(/<w:footerReference w:type="default" r:id="#{Regexp.escape(odd_footer_id)}"\/>/, body_section)
      assert_match(/<w:footerReference w:type="even" r:id="#{Regexp.escape(even_footer_id)}"\/>/, body_section)
      assert_match(/<w:pgNumType w:fmt="decimal" w:start="1"\/>/, body_section)
      refute_match(/r:id="rIdFooterOdd"|r:id="rIdFooterEven"/, content_xml)
      refute_match(/DOCX_FRONTMATTER_PAGE_BREAK_|DOCX_HALF_TITLE_PAGE_BREAK|DOCX_HALF_TITLE_VERSO_PAGE_BREAK|DOCX_HALF_TITLE_VERSO_START|DOCX_HALF_TITLE_VERSO_END|DOCX_ABOUT_AUTHOR_|DOCX_TITLE_PAGE_BREAK|DOCX_PUBLISHER_PAGE_BREAK|DOCX_ACT_PAGE_BREAK|DOCX_CHAPTER_PAGE_BREAK/, content_xml)
    end
  end

  def test_docx_omits_collected_xxx_by_default
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

      assert content_xml.index('Front') < content_xml.index('Act 1')
      refute_match(/XXX A pre-act note|XXX B pre-act note/, content_xml)
    end
  end

  def test_docx_can_include_collected_xxx_when_configured
    Dir.chdir(@tmp) do
      File.write('fixtures/story_a.txt', <<~TEXT)
        XXX pre-act
        note

        * Act 1: shared beginning

        ** chapter 1: first
        one
      TEXT
      File.write('front.md', "# Front\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_a.txt
        :frontmatter:
          - front.md
        :docx_include_review_notes: true
        :title: XXX Novel
        :author: Test Author
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML

      system('rake interleave_doc') or raise 'rake failed'

      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)

      assert content_xml.index('Front') < content_xml.index('XXX A pre-act note')
      assert content_xml.index('XXX A pre-act note') < content_xml.index('Act 1')
    end
  end

  def test_docx_places_aftermatter_after_manuscript
    Dir.chdir(@tmp) do
      File.write('about.md', "# About the Author\n\nBio text.\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :aftermatter:
          - about.md
        :title: Aftermatter Novel
        :author: Test Author
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML

      system('rake interleave_doc') or raise 'rake failed'

      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)

      assert content_xml.index('Beta') < content_xml.index('About the Author')
      assert content_xml.include?('Bio text.')
      refute_match(/DOCX_AFTERMATTER_PAGE_BREAK_/, content_xml)
    end
  end

  def test_docx_styles_configured_about_author_page
    Dir.chdir(@tmp) do
      File.write('about.md', "Bio text.\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :about_author: about.md
        :title: About Author Novel
        :author: Test Author
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML

      system('rake interleave_doc') or raise 'rake failed'

      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)

      assert content_xml.index('Beta') < content_xml.index('About the Author')
      assert_match(/<w:pStyle w:val="AboutAuthorHeading"\s*\/>.*?About the Author/m, content_xml)
      assert_match(/<w:pStyle w:val="AboutAuthorBody"\s*\/>.*?Bio text\./m, content_xml)
      assert_equal 1, content_xml.scan('About the Author').size
      refute_match(/DOCX_ABOUT_AUTHOR_/, content_xml)
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
      settings_xml = extract_docx_file(docx_file, 'word/settings.xml')
      footer_xml = extract_docx_file(docx_file, 'word/footer1.xml')
      rels_xml = extract_docx_file(docx_file, 'word/_rels/document.xml.rels')
      odd_footer_id = rels_xml[/Id="([^"]+)"[^>]*Target="footer1\.xml"/, 1]
      even_footer_id = rels_xml[/Id="([^"]+)"[^>]*Target="footer2\.xml"/, 1]
      assert_match(/w:ascii="Garamond"/, styles_xml)
      assert_match(/w:color w:val="000000"/, styles_xml)
      assert_match(/w:style w:type="paragraph" w:default="1" w:styleId="Normal".*?<w:ind w:firstLine="288"\s*\/>.*?w:line="240".*?w:sz w:val="22"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="BodyText".*?<w:ind w:firstLine="288"\s*\/>.*?w:sz w:val="22"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="FirstParagraph".*?<w:ind w:firstLine="0"\s*\/>.*?w:sz w:val="22"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="Compact".*?<w:ind w:firstLine="0"\s*\/>.*?w:after="0"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="Heading1".*?w:sz w:val="80"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageTitle".*?w:sz w:val="72"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageAuthor".*?w:sz w:val="40"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageTitle".*?<w:suppressAutoHyphens\s*\/>/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageAuthor".*?<w:suppressAutoHyphens\s*\/>/m, styles_xml)
      assert_match(/w:pgSz w:w="8640" w:h="12960"/, document_xml)
      assert_match(/w:pgMar w:top="1138" w:right="1138" w:bottom="1426" w:left="1138"/, document_xml)
      assert_match(/w:mirrorMargins/, settings_xml)
      assert_match(/w:evenAndOddHeaders/, settings_xml)
      assert_match(/w:autoHyphenation/, settings_xml)
      assert_match(/PAGE/, footer_xml)
      assert_match(/<w:footerReference w:type="default" r:id="#{Regexp.escape(odd_footer_id)}"\/>/, document_xml)
      assert_match(/<w:footerReference w:type="even" r:id="#{Regexp.escape(even_footer_id)}"\/>/, document_xml)
      refute_match(/r:id="rIdFooterOdd"|r:id="rIdFooterEven"/, document_xml)

      content_xml = extract_docx_content(docx_file)
      assert_match(/<w:pStyle w:val="TitlePageTitle"\/>.*?Test/m, content_xml)
      assert_match(/<w:pStyle w:val="TitlePageAuthor"\/>.*?Test Author/m, content_xml)
      assert_match(/<w:p\b(?=.*?<w:pStyle w:val="TitlePageTitle"\/>).*?<w:suppressAutoHyphens\/>.*?Test.*?<\/w:p>/m, content_xml)
      assert_match(/Test Author.*?Morlock Publishing.*?<w:sectPr><w:type w:val="nextPage"\/>.*?<\/w:sectPr>.*?DOCX_TOC_INSERT/m, content_xml)
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
      assert_match(/w:ascii="Garamond"/, styles_xml)
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
      assert_match(/w:pgMar w:top="1138" w:right="1138" w:bottom="1426" w:left="1800"/, reference_document_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="Heading1".*?w:sz w:val="36"/m, output_styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageTitle".*?w:sz w:val="60"/m, output_styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="TitlePageTitle".*?<w:suppressAutoHyphens\s*\/>/m, output_styles_xml)
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

  def docx_entry_names(docx_file)
    Zip::File.open(docx_file) do |zip|
      zip.entries.map(&:name)
    end
  end
end
