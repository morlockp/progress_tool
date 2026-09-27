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

  def test_chapterless_story_without_toc_or_print_page_numbers
    Dir.chdir(@tmp) do
      File.write('story.txt', "Opening paragraph.\n\n* * *\n\nClosing paragraph.\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files: [story.txt]
        :title: Short Story
        :chapterless: true
        :toc: false
        :date_start: '2019-11-01'
      YAML
      File.write('.docx_styles.yaml', <<~YAML)
        page:
          body_start_on_recto: false
        page_numbers:
          enabled: false
      YAML
      system('rake interleave_doc') or raise 'rake failed'
      html = File.read('Short_Story_draft_0.html')
      assert_includes html, '<p>Opening paragraph.</p>'
      assert_includes html, '<p>Closing paragraph.</p>'
      assert_includes html, '<p>* * *</p>'
      assert_equal 1, html.scan('<h2 id="story-title" style="text-align: center;">Short Story</h2>').size
      assert_operator html.index('id="story-title"'), :<, html.index('Opening paragraph.')
      refute_match(/<h2 id="chapter-/, html)
      refute_includes html, 'DOCX_TOC_INSERT'
      xml = extract_docx_content('Short_Story_draft_0.docx')
      opening = xml.scan(/<w:p\b.*?<\/w:p>/m).find { |p| p.include?('w:name="story-title"') }
      assert_includes opening, '<w:jc w:val="center"/>'
      assert_includes opening, '<w:ind w:left="0" w:firstLine="0"/>'
      refute_includes xml, 'oddPage'
      refute_includes xml, 'footerReference'
      refute_includes xml, 'DOCX_'
      refute_includes xml, 'Revision history:'

      config = File.read('.rakefile.yaml')
      File.write('.rakefile.yaml', config + ":opening_title: false\n")
      assert system('rake interleave_doc'), 'suppressed opening title failed'
      xml = extract_docx_content('Short_Story_draft_0.docx')
      refute_includes xml, 'w:name="story-title"'
      assert_includes xml, 'Opening paragraph.'

      # A multi-file chapterless story still gets only one opening title.
      File.write('ending.txt', "The final paragraph.\n\nAn interruption -\n")
      File.write('.rakefile.yaml', config.sub('[story.txt]', '[story.txt, ending.txt]') + ":opening_title: auto\n")
      assert system('rake interleave_html'), 'automatic opening title failed'
      html = File.read('Short_Story_draft_0.html')
      assert_equal 1, html.scan('id="story-title"').size
      assert_includes html, 'The final paragraph.'
      assert_includes html, "An interruption\u00a0-"

      chaptered = config.sub(':chapterless: true', ":chapter_head_tag: '** chapter'")
      File.write('story.txt', "** chapter 1: Arrival\n\nOpening paragraph.\n")
      File.write('.rakefile.yaml', chaptered)
      assert system('rake interleave_html'), 'chaptered opening failed'
      refute_includes File.read('Short_Story_draft_0.html'), 'id="story-title"'
      File.write('.rakefile.yaml', chaptered + ":opening_title: true\n")
      assert system('rake interleave_html'), 'forced opening title failed'
      html = File.read('Short_Story_draft_0.html')
      assert_operator html.index('id="story-title"'), :<, html.index('id="chapter-1"')
      File.write('.rakefile.yaml', config + ":opening_title: typo\n")
      output = IO.popen(['rake', 'interleave_html'], err: [:child, :out], &:read)
      refute $?.success?
      assert_includes output, ':opening_title must be auto, true, or false'
    end
  end

  def test_ebook_omits_half_title_and_places_author_last
    Dir.chdir(@tmp) do
      File.write('story.txt', "Opening paragraph.\n\nClosing paragraph.\n")
      File.write('other_books.md', "# Other Books\n\nBook One\n")
      File.write('about.md', "Author biography.\n")
      File.write('links.md', "# Stay Connected\n\n<https://example.com/books>\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files: [story.txt]
        :title: Ebook Layout
        :author: Test Author
        :chapterless: true
        :toc: false
        :date_start: '2019-11-01'
        :title_page:
          show_half_title: false
        :copyright_page:
          year: 2019
        :other_books: other_books.md
        :aftermatter_about_the_author: about.md
        :aftermatter_stay_connected: links.md
      YAML
      assert system('rake interleave_doc interleave_txt'), 'rake failed'
      xml = extract_docx_content('Ebook_Layout_draft_0.docx')
      assert_equal 2, xml.scan('Ebook Layout').size
      order = ['Ebook Layout', 'Copyright', 'Opening paragraph.', 'Closing paragraph.',
               'Stay Connected', 'Other Books', 'Book One', 'Author biography.']
      positions = order.map { |text| xml.index(text).tap { |pos| refute_nil pos, text } }
      assert_equal positions.sort, positions
      assert_equal 1, xml.scan('Other Books').size
      refute_includes xml, 'DOCX_'
      assert_includes extract_docx_file('Ebook_Layout_draft_0.docx', 'word/_rels/document.xml.rels'), 'https://example.com/books'
      text = File.read('Ebook_Layout_draft_0.txt')
      assert_match(/Closing paragraph.*Stay Connected.*Other Books.*Author biography/m, text)

      File.write('.rakefile.yaml', File.read('.rakefile.yaml').sub(':toc: false', ':toc: ebook'))
      assert system({'RAKEFILE_SKIP_DOCX_TOC_REFRESH' => nil}, 'rake interleave_doc'), 'ebook TOC build failed'
      xml = extract_docx_content('Ebook_Layout_draft_0.docx')
      toc = xml[/<w:sdt\b.*?<\/w:sdt>/m]
      refute_nil toc
      assert_includes toc, 'w:name="toc"'
      assert_includes extract_docx_file('Ebook_Layout_draft_0.docx', 'word/settings.xml'), '<w:updateFields w:val="false"/>'
      assert_includes toc, '\\n'
      refute_includes toc, 'PAGEREF'
      labels = toc.scan(/<w:hyperlink\b.*?<w:t>(.*?)<\/w:t>.*?<\/w:hyperlink>/m).flatten
      assert_equal ['Ebook Layout', 'Stay Connected', 'Other Books', 'About the Author'], labels
      anchors = toc.scan(/w:anchor="([^"]+)"/).flatten
      assert_equal 4, anchors.uniq.size
      anchors.each { |anchor| assert_equal 1, xml.scan(%(w:name="#{anchor}")).size }
      anchors.each do |anchor|
        target = xml.scan(/<w:p\b.*?<\/w:p>/m).find { |p| p.include?(%(w:name="#{anchor}")) }
        assert_includes target, '<w:outlineLvl w:val="0"/>'
      end
      assert_operator xml.index('<w:sdt>'), :<, xml.index('Opening paragraph.')
      refute_includes xml, 'DOCX_'
      File.write('preface.md', "# Preface\n\nBefore the chapters.\n")
      config_text = File.read('.rakefile.yaml').sub(':chapterless: true', ":chapter_head_tag: '** chapter'")
      config_text = config_text.sub(':target_files: [story.txt]', ':target_files: [fixtures/story_lopez.txt]')
      File.write('.rakefile.yaml', config_text + ":frontmatter: [TOC, preface.md]\n:frontmatter_layout: condensed\n")
      assert system('rake interleave_doc'), 'chaptered ebook TOC build failed'
      xml = extract_docx_content('Ebook_Layout_draft_0.docx')
      toc = xml[/<w:sdt\b.*?<\/w:sdt>/m]
      assert_includes toc, 'Preface'
      assert_includes toc, 'Beginning'
      chapter_row = toc.scan(/<w:p\b.*?<\/w:p>/m).find { |p| p.include?('Beginning') }
      assert_includes chapter_row, '<w:ind w:left="0"'

      assert_match(%r{</w:sdt><w:p>.*?<w:br w:type="page"/>}, xml)
      File.write('story.txt', "* Act 1: Beginnings\n\n** chapter 1: Arrival\n\nOpening.\n\n** chapter 2: Departure\n\nEnding.\n")
      config_text = config_text.sub(':target_files: [fixtures/story_lopez.txt]', ':target_files: [story.txt]')
      File.write('.rakefile.yaml', config_text)
      assert system('rake interleave_doc'), 'nested ebook TOC build failed'
      xml = extract_docx_content('Ebook_Layout_draft_0.docx')
      toc = xml[/<w:sdt\b.*?<\/w:sdt>/m]
      rows = toc.scan(/<w:p\b.*?<\/w:p>/m)
      assert_includes rows.find { |p| p.include?('Act 1: Beginnings') }, '<w:ind w:left="0"'
      assert_includes rows.find { |p| p.include?('Arrival') }, '<w:ind w:left="360"'
      assert_includes rows.find { |p| p.include?('Departure') }, '<w:ind w:left="360"'
      body = xml.sub(toc, '')
      arrival = body.scan(/<w:p\b.*?<\/w:p>/m).find { |p| p.include?('Arrival') }
      assert_includes arrival, '<w:outlineLvl w:val="1"/>'

    end
  end

  def test_shared_universe_catalog_omits_current_book_and_updates_on_rebuild
    Dir.chdir(@tmp) do
      File.write('story.txt', "Opening paragraph.\n\nStory ending.\n")
      File.write('about.md', "Author biography.\n")
      File.write('catalog.yaml', <<~YAML)
        heading: More in this universe
        intro: Pick your next story.
        books:
          - id: current
            title: Current Book
            amazon_url: https://www.amazon.com/dp/B081MW4W4Z
          - id: next
            title: 'Next & <Novel>'
            description: Another adventure.
            amazon_url: https://www.amazon.com/dp/B005JPPMS6
          - id: future
            title: Forthcoming Book
            description: Kindle edition forthcoming.
            amazon_url:
      YAML
      File.write('.rakefile.yaml', <<~YAML)
        :target_files: [story.txt]
        :title: Catalog Test
        :edition_format: ebook
        :chapterless: true
        :toc: ebook
        :date_start: '2019-11-01'
        :book_id: current
        :more_in_this_universe: catalog.yaml
        :aftermatter_about_the_author: about.md
      YAML
      assert system('rake interleave_doc interleave_txt'), 'catalog build failed'
      xml = extract_docx_content('Catalog_Test_draft_0.docx')
      body = xml.sub(/<w:sdt\b.*?<\/w:sdt>/m, '')
      refute_includes body, 'Current Book'
      assert_includes body, 'Next &amp; &lt;Novel&gt;'
      assert_includes body, 'Forthcoming Book'
      assert_operator body.index('Story ending.'), :<, body.index('More in this universe')
      assert_operator body.index('Forthcoming Book'), :<, body.index('Author biography.')
      assert_includes xml[/<w:sdt\b.*?<\/w:sdt>/m], 'More in this universe'
      rels = extract_docx_file('Catalog_Test_draft_0.docx', 'word/_rels/document.xml.rels')
      assert_includes rels, 'https://www.amazon.com/dp/B005JPPMS6'
      refute_includes rels, 'https://www.amazon.com/dp/B081MW4W4Z'
      assert_includes File.read('Catalog_Test_draft_0.txt'), 'Next & <Novel>'
      refute_includes xml, 'DOCX_'

      refute_includes xml, 'Rate'
      review_url = 'https://www.amazon.com/review/create-review?asin=B081MW4W4Z'
      base_config = File.read('.rakefile.yaml')
      File.write('.rakefile.yaml', base_config + ":reader_review_url: #{review_url}\n")
      assert system('rake interleave_doc interleave_txt'), 'review link build failed'
      xml = extract_docx_content('Catalog_Test_draft_0.docx')
      body = xml.sub(/<w:sdt\b.*?<\/w:sdt>/m, '')
      assert_includes body, 'Rate Catalog Test on Amazon'
      assert_includes body, 'Please leave an honest star rating'
      assert_operator body.index('Forthcoming Book'), :<, body.index('Please leave an honest star rating')
      assert_operator body.index('Rate Catalog Test'), :<, body.index('Author biography.')
      assert_includes extract_docx_file('Catalog_Test_draft_0.docx', 'word/_rels/document.xml.rels'), review_url
      assert_includes File.read('Catalog_Test_draft_0.txt'), review_url
      html = File.read('Catalog_Test_draft_0.html')
      assert_includes html, "<u><strong>Rate Catalog Test on Amazon</strong></u>"
      ['javascript:alert(1)', 'https://amazon.com.evil.example/review'].each do |invalid|
        File.write('.rakefile.yaml', base_config + ":reader_review_url: #{invalid}\n")
        output = IO.popen(['rake', 'interleave_doc'], err: [:child, :out], &:read)
        refute $?.success?
        assert_includes output, ':reader_review_url must be an absolute Amazon.com HTTP(S) URL'
      end
      File.write('.rakefile.yaml', base_config)

      File.write('catalog.yaml', File.read('catalog.yaml').sub('Another adventure.', 'Updated description.'))
      File.write('.rakefile.yaml', File.read('.rakefile.yaml').sub(':book_id: current', ':book_id: next'))
      assert system('rake interleave_doc'), 'second book build failed'
      xml = extract_docx_content('Catalog_Test_draft_0.docx')
      assert_includes xml, 'Current Book'
      refute_includes xml, 'Next &amp; &lt;Novel&gt;'
      File.write('.rakefile.yaml', File.read('.rakefile.yaml').sub(':book_id: next', ':book_id: current'))
      assert system('rake interleave_doc'), 'updated catalog build failed'
      assert_includes extract_docx_content('Catalog_Test_draft_0.docx'), 'Updated description.'

      File.write('.rakefile.yaml', File.read('.rakefile.yaml').sub(':book_id: current', ':book_id: typo'))
      output = IO.popen(['rake', 'interleave_doc'], err: [:child, :out], &:read)
      refute $?.success?
      assert_includes output, ':book_id must match a book'
    end
  end

  def test_reader_actions_work_for_series_and_standalones_in_both_formats
    Dir.chdir(@tmp) do
      File.write('story.txt', "Opening.\n\nStory ending.\n")
      File.write('actions.yaml', <<~YAML)
        patreon_url: https://www.patreon.com/cw/test-author
        catalog_url: https://www.amazon.com/stores/author/B06XF15CC8
      YAML
      File.write('catalog.yaml', <<~YAML)
        heading: More in this universe
        books:
          - id: current
            title: Current Book
            amazon_url: https://www.amazon.com/dp/B081MW4W4Z
          - id: next
            title: Next Book
            amazon_url: https://www.amazon.com/dp/B005JPPMS6
          - id: future
            title: Forthcoming Book
            description: Coming soon.
      YAML
      File.write('other_books.md', "# Books by Test Author\n\n## Fiction\n\n* [Another Book](https://www.amazon.com/dp/B005JPPMS6)\n")
      File.write('about.md', "# About the Author\n\nAuthor biography.\n")
      base = <<~YAML
        :target_files: [story.txt]
        :title: Action Test
        :chapterless: true
        :toc: false
        :date_start: '2019-11-01'
        :other_books: other_books.md
        :aftermatter_about_the_author: about.md
        :title_page:
          show_half_title: false
        :reader_actions: actions.yaml
        :reader_review_asin: 1709969407
      YAML
      series = ":book_id: current\n:more_in_this_universe: catalog.yaml\n"
      review_url = 'https://www.amazon.com/review/create-review/?asin=1709969407'
      %w[ebook print].each do |format|
        %w[books patreon].each do |lead|
          edition_base = format == 'ebook' ? base.sub(':toc: false', ':toc: ebook') : base
          File.write('.rakefile.yaml', edition_base + series + ":edition_format: #{format}\n:reader_actions_lead: #{lead}\n")
          assert system('rake interleave_doc interleave_txt'), "#{format}/#{lead} failed"
          docx = 'Action_Test_draft_0.docx'
          xml = extract_docx_content(docx)
          toc = xml[/<w:sdt\b.*?<\/w:sdt>/m]
          xml = xml.sub(toc, '') if toc
          text = File.read('Action_Test_draft_0.txt')
          html = File.read('Action_Test_draft_0.html')
          expected = ['Stay connected', 'Read new chapters free', 'What did you think?']
          lead == 'patreon' ? expected.push('More in this universe') : expected.unshift('More in this universe')
          expected.concat(['Books by Test Author', 'About the Author'])
          if format == 'ebook'
            labels = toc.scan(/<w:hyperlink\b.*?<w:t>(.*?)<\/w:t>.*?<\/w:hyperlink>/m).flatten
            assert_equal ['Action Test'] + expected.reject { |h| ['Read new chapters free', 'What did you think?'].include?(h) }, labels
          end
          refute_includes xml, 'Explore my other books'
          heading_paragraphs = ['Read new chapters free', 'What did you think?'].map do |heading|
            xml.scan(/<w:p\b.*?<\/w:p>/m).find { |p| p.include?(">#{heading}</w:t>") }
          end
          heading_paragraphs.each do |paragraph|
            refute_nil paragraph
            assert_includes paragraph, '<w:pStyle w:val="ReaderActionHeading"/>'
          end
          assert_equal 1, heading_paragraphs.map { |p| p[/<w:pPr>.*?<\/w:pPr>/m] }.uniq.size
          [xml, text].each do |output|
            positions = expected.map { |title| output.index(title).tap { |n| refute_nil n, title } }
            assert_equal positions.sort, positions
            assert_includes output, 'No paid membership is needed'
            assert_includes output, 'Please leave an honest star rating'
            refute_includes output, 'five-star'
            refute_includes output, 'Current Book'
          end
          assert_includes text, review_url
          assert_includes xml, 'Forthcoming Book'
          assert_equal 1, xml.scan(/<w:t[^>]*>Rate Action Test on Amazon<\/w:t>/).size
          refute_includes xml, 'DOCX_'
          rels = extract_docx_file(docx, 'word/_rels/document.xml.rels')
          if format == 'ebook'
            assert_includes rels, 'https://www.amazon.com/stores/author/B06XF15CC8'
            assert_match(%r{<h1[^>]*><a href="https://www.amazon.com/stores/author/B06XF15CC8"><u>Books by Test Author</u></a></h1>}, html)
            assert_includes rels, review_url
            assert_includes rels, 'https://www.patreon.com/cw/test-author'
            refute_includes html, 'data:image/png;base64,'
          else
            refute_includes rels, review_url
            assert_includes xml, review_url
            assert_operator xml.index('Another Book'), :<, xml.index('Browse all my books on Amazon')
            catalog_block = xml.scan(/<w:p\b.*?<\/w:p>/m).find { |p| p.include?('Browse all my books on Amazon') }
            assert_includes catalog_block, 'w:yAlign="bottom"'
            assert_includes catalog_block, 'w:vAnchor="margin"'
            assert_includes catalog_block, '<w:drawing'
            assert_includes catalog_block, 'https://www.amazon.com/stores/author/B06XF15CC8'
            refute_includes catalog_block, 'w:type="page"'

            assert_equal 4, html.scan('data:image/png;base64,').size
            qr_paragraphs = xml.scan(/<w:p\b.*?<\/w:p>/m).select { |p| p.include?('<w:drawing') && p.include?('MatterQRCode') }
            assert_equal 4, qr_paragraphs.size
            qr_paragraphs.each do |paragraph|
              assert_includes paragraph, '<w:keepLines/>'
              assert_includes paragraph, 'https://'
              assert_includes paragraph, '<w:b'
            end
          end
        end
      end
      File.write('.rakefile.yaml', base + ":edition_format: ebook\n")
      assert system('rake interleave_doc'), 'standalone failed'
      xml = extract_docx_content('Action_Test_draft_0.docx')
      refute_includes xml, 'More in this universe'
      assert_includes xml, 'Read new chapters free'
      assert_includes xml, 'Rate Action Test on Amazon'
      File.write('actions.yaml', "patreon_url: https://www.patreon.com/cw/updated-author\n")
      assert system('rake interleave_doc'), 'shared update failed'
      rels = extract_docx_file('Action_Test_draft_0.docx', 'word/_rels/document.xml.rels')
      assert_includes rels, 'https://www.patreon.com/cw/updated-author'
      refute_includes extract_docx_content('Action_Test_draft_0.docx'), 'Explore my other books'
      [base.sub('1709969407', 'bad&asin'),
       base + ":reader_review_url: https://www.amazon.com/review/create-review/?asin=B081MW4W4Z\n",
       base + ":reader_actions_lead: typo\n",
       base.sub('actions.yaml', '{patreon_url: "javascript:alert(1)"}'),
       base.sub('actions.yaml', '{catalog_url: "https://amazon.com.evil.example"}'),
       base.sub('actions.yaml', '{patreon_urll: "https://www.patreon.com/test"}')].each do |config|
        File.write('.rakefile.yaml', config)
        output = IO.popen(['rake', 'interleave_doc'], err: [:child, :out], &:read)
        refute $?.success?, config
        assert_includes output, '*** ERROR:'
      end
    end
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

  def test_docx_formats_opening_blockquote_as_epigraph
    Dir.chdir(@tmp) do
      File.write('fixtures/epigraph.txt', <<~TEXT)
        ** chapter 1: The Great Project

        > So great a task it was to found a people.
        > —Virgil, _Aeneid_ 1.33

        The chapter begins here.
      TEXT
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/epigraph.txt
        :title: Epigraph Test
        :target_words: 100
        :date_start: '2026-08-28'
        :chapter_head_tag: '** chapter'
      YAML

      assert system('rake interleave_doc'), 'rake interleave_doc failed'
      xml = extract_docx_content(Dir['*_draft_0.docx'].first).force_encoding('UTF-8')

      assert_includes xml, 'w:pStyle w:val="ChapterEpigraph"'
      assert_includes xml, 'w:pStyle w:val="ChapterEpigraphAttribution"'
      refute_match(/<w:pStyle w:val="Heading2"\/>.*?So great a task/m, xml)
    end
  end

  def test_docx_renders_labeled_starstarstar_marker_as_dinkus
    Dir.chdir(@tmp) do
      File.write('fixtures/story_with_subheading.txt', <<~TEXT)
        ** chapter 1: Test

        body text

        *** computing

        more body

        ***

        separator body
      TEXT

      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_with_subheading.txt
        :title: Test
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :never_hyphenate:
          - Aristillus
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)

      system('rake interleave_doc') or raise 'rake failed'

      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)
      assert_match(/<w:pStyle w:val="Dinkus"\s*\/>.*?\* \* \*/m, content_xml)
      assert_equal 2, content_xml.scan('w:pStyle w:val="Dinkus"').size
      refute_match(/<w:pStyle w:val="Heading3"\s*\/>.*?computing/m, content_xml)
      refute_match(/<w:pStyle w:val="Heading3"\s*\/>.*?<w:t>\*\*\*<\/w:t>/m, content_xml)
    end
  end

  def test_docx_renders_scene_marker_as_dinkus_by_default
    Dir.chdir(@tmp) do
      File.write('fixtures/story_with_scene_marker.txt', <<~TEXT)
        ** chapter 1: Test

        before

        *** transition: arrival

        after
      TEXT
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_with_scene_marker.txt
        :title: Scene Marker Test
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML

      assert system('rake interleave_doc'), 'rake interleave_doc failed'
      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)

      assert_match(/<w:pStyle w:val="Dinkus"\s*\/?>.*?\* \* \*/m, content_xml)
      refute_match(/<w:pStyle w:val="Heading3"\s*\/?>.*?scene 1: arrival/m, content_xml)
    end
  end

  def test_docx_renders_markdown_subheadings_as_toc_level_three
    Dir.chdir(@tmp) do
      File.write('fixtures/afterword.txt', <<~TEXT)
        ** chapter 1: Afterword

        ## On the Discipline and the Joy of Hard Science Fiction

        Afterword text.
      TEXT
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/afterword.txt
        :title: Afterword Test
        :target_words: 100
        :date_start: '2026-08-28'
        :chapter_head_tag: '** chapter'
      YAML

      assert system('rake interleave_doc'), 'rake interleave_doc failed'
      xml = extract_docx_content(Dir['*_draft_0.docx'].first).force_encoding('UTF-8')

      assert_match(/<w:pStyle w:val="Heading3"\s*\/>.*?On the Discipline/m, xml)
    end
  end

  def test_docx_renders_markdown_footnotes_as_end_of_afterword_notes
    Dir.chdir(@tmp) do
      File.write('fixtures/afterword.txt', <<~TEXT)
        ** chapter 1: One

        A fact worth citing.[^source]

        [^source]: https://example.com/source

        ** chapter 2: Afterword

        The final Afterword paragraph.

        ## Endnotes
      TEXT
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/afterword.txt
        :title: Afterword Footnote Test
        :target_words: 100
        :date_start: '2026-08-28'
        :chapter_head_tag: '** chapter'
      YAML

      assert system('rake interleave_doc'), 'rake interleave_doc failed'
      xml = extract_docx_content(Dir['*_draft_0.docx'].first).force_encoding('UTF-8')
      html = File.read(Dir['*_draft_0.html'].first)

      refute_match(/\[\^source\]/, xml)
      assert_match(/<w:vertAlign w:val="superscript"\s*\/>.*?<w:t[^>]*>1<\/w:t>/m, xml)
      assert_match(/<w:bookmarkStart w:id="\d+" w:name="endnote_reference_1"\s*\/>/, xml)
      assert_match(/PAGEREF endnote_reference_1/, xml)
      assert_match(/<w:t[^>]*>1\. \(page <\/w:t>/, xml)
      assert_operator xml.index('Endnotes'), :<, xml.index('https://example.com/source')
      assert_operator html.index('https://example.com/source'), :<, html.rindex('DOCX_CHAPTER_PAGE_BREAK')
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

  def test_docx_preserves_inline_italics_and_bold
    Dir.chdir(@tmp) do
      File.write('fixtures/story_with_italics.txt', <<~TEXT)
        * Act 1: The _Beginning_

        ** chapter 1: Test
        This has _italicized text_ and **bold text** in it. It also names **The Aristillus
        Engineering Club** and **Aristillus 3: Right
        and Duty**.

        *** scene: This remains a scene marker.
      TEXT
      
      # Update config to use the new file (use same format as original)
      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_with_italics.txt
        :title: Test
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :never_hyphenate:
          - Aristillus
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)
      
      system('rake interleave_doc') or raise 'rake failed'
      
      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)
      html = File.read(Dir['*_draft_0.html'].first)
      visible_html = html.delete("\u2060")
      
      assert content_xml.include?('<w:i/>') || content_xml.include?('<w:i'), "Document should contain italic formatting"
      assert_match(/<w:b\s*\/>.*?bold text/m, content_xml)
      assert_match(/<b>The Aristillus\s+Engineering Club<\/b>/, visible_html)
      assert_match(/<b>Aristillus 3: Right\s+and Duty<\/b>/, visible_html)
      assert_includes content_xml, 'A&#8288;r&#8288;i&#8288;s&#8288;t&#8288;i&#8288;l&#8288;l&#8288;u&#8288;s'
      refute_includes html, '<b> and </b>'
      refute_includes content_xml, 'This remains a scene marker.'
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
        - 2165: **Escape from Io** begins
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
      assert_match(/w:style w:type="paragraph" w:styleId="FrontmatterTimeline".*?w:left="1152".*?w:hanging="1152".*?w:tab w:val="left" w:pos="792"/m, styles_xml)
      assert_match(/<w:pStyle w:val="FrontmatterHeading1"\s*\/>.*?Timeline/m, content_xml)
      assert_match(/<w:pStyle w:val="FrontmatterTimeline"\s*\/>.*?2051/m, content_xml)
      assert_match(/<w:pStyle w:val="FrontmatterTimeline"\s*\/>.*?2165/m, content_xml)
      assert_match(/2051:<\/w:t><w:tab\/><w:t>Anti gravity developed/, content_xml)
      assert_match(/2165:<\/w:t><w:tab\/>.*?Escape from Io/m, content_xml)
      assert_equal 2, content_xml[content_xml.index('Escape from Io')...content_xml.index('Beginning')].scan('<w:br w:type="page"/>').size
      refute_match(/DOCX_FRONTMATTER_TIMELINE_START|DOCX_FRONTMATTER_TIMELINE_END/, content_xml)
    end
  end

  def test_docx_condensed_frontmatter_uses_consecutive_pages
    Dir.chdir(@tmp) do
      File.write('timeline.md', "# Timeline\n\n- 2051: Anti gravity developed\n")
      File.write('dramatis.md', "# Dramatis Personae\n\n**Roch** — Mission commander.\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_lopez.txt
        :frontmatter_layout: condensed
        :timeline: timeline.md
        :dramatis_personae: dramatis.md
        :toc: true
        :title: Test Novel
        :author: Test Author
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML

      assert system('rake interleave_doc'), 'rake interleave_doc failed'
      xml = extract_docx_content(Dir['*_draft_0.docx'].first)

      timeline_to_dramatis = xml[xml.index('Anti gravity developed')...xml.index('Dramatis Personae')]
      dramatis_to_toc = xml[xml.index('Mission commander.')...xml.index('DOCX_TOC_INSERT')]
      assert_equal 1, timeline_to_dramatis.scan('<w:br w:type="page"/>').size
      assert_equal 1, dramatis_to_toc.scan('<w:br w:type="page"/>').size
      refute_includes xml, 'DOCX_TOC_AFTER_PAGE_BREAK'
      assert_match(/<w:type w:val="oddPage"\/>/, xml)
    end
  end

  def test_shared_bibliography_links_follow_edition_format_only
    Dir.chdir(@tmp) do
      bibliography = "# Other Books\n\n* [Book *One* & Two](https://www.amazon.com/dp/B081PBXBMB)\n* Unlisted Book\n"
      File.write('other_books.md', bibliography)
      File.write('stay.md', "[Author website](https://example.com/author)\n")
      [[nil, true], ['print', false], ['ebook', true], ['ebook', false]].each do |format, half_title|
        config = <<~YAML
          :target_files: [fixtures/story_lopez.txt]
          :chapter_head_tag: '** chapter'
          :title: Bibliography Links
          :date_start: '2019-11-01'
          :toc: false
          :title_page:
            show_half_title: #{half_title}
          :other_books: other_books.md
          :aftermatter_stay_connected: stay.md
          :other_books_link:
            url: https://example.com/store
            format: #{format == 'ebook' ? 'link' : 'qr'}
        YAML
        config += ":edition_format: #{format}\n" if format
        File.write('.rakefile.yaml', config)
        assert system('rake interleave_doc'), "#{format.inspect}/#{half_title} build failed"
        docx = 'Bibliography_Links_draft_0.docx'
        xml = extract_docx_content(docx)
        rels = extract_docx_file(docx, 'word/_rels/document.xml.rels')
        html = File.read('Bibliography_Links_draft_0.html')
        section = html[/<section class="half-title-verso">.*?<\/section>/m]
        assert_includes section, 'Book <em>One</em> &amp; Two'
        assert_includes section, 'Unlisted Book'
        assert_includes rels, 'https://example.com/author'
        assert_equal bibliography, File.read('other_books.md')
        if format == 'ebook'
          assert_includes rels, 'https://www.amazon.com/dp/B081PBXBMB'
          assert_includes rels, 'https://example.com/store'
          assert_includes section, '<a href="https://www.amazon.com/dp/B081PBXBMB"><u>'
        else
          refute_includes rels, 'https://www.amazon.com/dp/B081PBXBMB'
          refute_includes section, '<a '
          refute_includes section, '<u>'
          assert_includes xml, '<w:pStyle w:val="MatterQRCode"/>'
          paragraph = xml.scan(/<w:p[ >].*?<\/w:p>/m).find { |p| p.include?('Unlisted Book') }
          refute_includes paragraph, '<w:u '
        end
      end
      File.write('.rakefile.yaml', File.read('.rakefile.yaml').sub(':edition_format: ebook', ':edition_format: typo'))
      output = IO.popen(['rake', 'interleave_doc'], err: [:child, :out], &:read)
      refute $?.success?
      assert_includes output, ':edition_format must be print or ebook'
    end
  end

  def test_other_books_destination_as_link_or_qr
    Dir.chdir(@tmp) do
      File.write('other_books.md', "# Other Books\n\nBook One\n")
      url = 'https://example.com/books?author=one&edition=two'
      %w[link qr].each do |format|
        File.write('.rakefile.yaml', <<~YAML)
          :target_files: [fixtures/story_lopez.txt]
          :chapter_head_tag: '** chapter'
          :title: Destination Test
          :date_start: '2019-11-01'
          :toc: false
          :title_page:
            show_half_title: #{format == 'qr'}
          :other_books: other_books.md
          :other_books_link:
            url: #{url}
            format: #{format}
            label: More books & stories
        YAML
        assert system('rake interleave_doc'), "#{format} build failed"
        xml = extract_docx_content('Destination_Test_draft_0.docx')
        html = File.read('Destination_Test_draft_0.html')
        assert_equal 1, xml.scan('More books &amp; stories').size
        assert_operator xml.index('Book One'), :<, xml.index('More books &amp; stories')
        assert_equal "# Other Books\n\nBook One\n", File.read('other_books.md')
        if format == 'link'
          rels = extract_docx_file('Destination_Test_draft_0.docx', 'word/_rels/document.xml.rels')
          assert_includes rels, url.gsub('&', '&amp;')
          assert_includes xml, '<w:hyperlink'
          assert_includes xml, '<w:u w:val="single"'
          refute_includes xml, 'MatterQRCode'
        else
          assert_equal 1, xml.scan('<w:pStyle w:val="MatterQRCode"/>').size
          assert_includes xml, 'cx="685800" cy="685800"'
          assert_includes html, 'data:image/png;base64,'
          assert_includes html, 'QR code for https://example.com/books?author=one&amp;edition=two'
        end
      end
      [['https://example.com/books', 'barcode', 'format must be link or qr'],
       ['javascript:alert(1)', 'link', 'url must be an absolute HTTP(S) URL']].each do |url, format, error|
        File.write('.rakefile.yaml', <<~YAML)
          :target_files: [fixtures/story_lopez.txt]
          :chapter_head_tag: '** chapter'
          :title: Invalid Destination
          :date_start: '2019-11-01'
          :other_books: other_books.md
          :other_books_link:
            url: #{url}
            format: #{format}
        YAML
        output = IO.popen(['rake', 'interleave_doc'], err: [:child, :out], &:read)
        refute $?.success?
        assert_includes output, error
      end
    end
  end

  def test_docx_adds_centered_qr_codes_only_for_allowlisted_matter_files
    Dir.chdir(@tmp) do
      skip 'qrencode is required for this test' unless system('qrencode', '--version', out: File::NULL, err: File::NULL)

      File.write('front.md', "# Front\n\nhttps://example.com/front\n")
      File.write('stay.md', "Visit us:\n\nhttps://example.com/stay\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_lopez.txt
        :frontmatter:
          - front.md
        :aftermatter_stay_connected: stay.md
        :matter_qr_codes:
          - stay.md
        :title: Test Novel
        :author: Test Author
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML

      assert system('rake interleave_doc'), 'rake interleave_doc failed'
      docx = Dir['*_draft_0.docx'].first
      xml = extract_docx_content(docx)
      styles = extract_docx_file(docx, 'word/styles.xml')
      front_to_stay = xml[xml.index('https://example.com/front')...xml.index('https://example.com/stay')]

      assert_match(/w:style w:type="paragraph" w:styleId="MatterQRCode".*?w:jc w:val="center"/m, styles)
      assert_equal 1, xml.scan('<w:pStyle w:val="MatterQRCode"/>').size
      refute_includes front_to_stay, 'MatterQRCode'
      assert_operator xml.index('https://example.com/stay'), :<, xml.index('MatterQRCode')
      assert_match(/<wp:extent cx="685800" cy="685800"/, xml)
      assert docx_entry_names(docx).any? { |name| name.start_with?('word/media/') }
    end
  end

  def test_docx_uses_named_standard_frontmatter_slots_in_publication_order
    Dir.chdir(@tmp) do
      File.write('epigraph.md', "# Epigraph\n\nOpening words.\n")
      File.write('timeline.md', "# Timeline\n\n- 2051: Anti gravity developed\n")
      File.write('dramatis.md', "# Dramatis Personae\n\n**Roch** — Mission commander.\n")
      File.write('backers.md', "# With Thanks to Our Kickstarter Backers\n\nThank you.\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_lopez.txt
        :epigraph: epigraph.md
        :timeline: timeline.md
        :dramatis_personae: dramatis.md
        :kickstarter_backers: backers.md
        :toc: true
        :title: Test Novel
        :author: Test Author
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML

      assert system('rake interleave_doc'), 'rake interleave_doc failed'
      xml = extract_docx_content(Dir['*_draft_0.docx'].first)

      assert xml.index('Epigraph') < xml.index('Timeline')
      assert xml.index('Timeline') < xml.index('Dramatis Personae')
      assert xml.index('Dramatis Personae') < xml.index('With Thanks to Our Kickstarter Backers')
      assert xml.index('With Thanks to Our Kickstarter Backers') < xml.index('DOCX_TOC_INSERT')
      assert_match(/<w:pStyle w:val="FrontmatterTimeline"\s*\/>.*?2051/m, xml)
      assert_match(/<w:pStyle w:val="FrontmatterDramatis"\s*\/>.*?Roch/m, xml)
    end
  end

  def test_docx_applies_dramatis_style_to_marked_frontmatter_file
    Dir.chdir(@tmp) do
      File.write('dramatis.md', <<~MD)
        ## Dramatis Personae

        **Roch** — Mission commander and astrogator. The oldest Dog on the mission. Childless.

        **Bollstadt** — Mission geologist. The youngest Dog. Brilliant. Obsessed. Trichromat (can see the color red).
      MD
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_lopez.txt
        :frontmatter:
          - file: dramatis.md
            style: dramatis
        :title: Test
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML

      assert system('rake interleave_doc'), 'rake interleave_doc failed'
      docx_file = Dir['*_draft_0.docx'].first
      content_xml = extract_docx_content(docx_file)
      styles_xml = extract_docx_file(docx_file, 'word/styles.xml')

      assert_match(/w:style w:type="paragraph" w:styleId="FrontmatterDramatisHeading".*?w:after="200"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="FrontmatterDramatis".*?w:left="1584".*?w:hanging="1584".*?w:tab w:val="left" w:pos="1584".*?w:suppressAutoHyphens/m, styles_xml)
      assert_match(/<w:pStyle w:val="FrontmatterDramatisHeading"\s*\/>.*?Dramatis Personae/m, content_xml)
      assert_match(/<w:pStyle w:val="FrontmatterDramatis"\s*\/>.*?Roch.*?<w:tab\/>.*?Mission commander/m, content_xml)
      dramatis_end = content_xml.index('Bollstadt')
      page_break = content_xml.index(/<w:br w:type="page"\s*\/>/, dramatis_end)
      assert_operator dramatis_end, :<, page_break
      refute_match(/DOCX_FRONTMATTER_DRAMATIS_START|DOCX_FRONTMATTER_DRAMATIS_END/, content_xml)
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

  def test_docx_long_title_page_uses_compact_spacing
    Dir.chdir(@tmp) do
      yaml_content = <<~YAML
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :title: The Aristillus Engineering Club and the Journey to the Center of Mars
        :title_page:
          layout: split_title
          series_title:
            - The Aristillus Engineering
            - Club
          conjunction: and
          book_title:
            - The Journey to the
            - Center of Mars
        :author: Test Author
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML
      File.write('.rakefile.yaml', yaml_content)

      system('rake interleave_doc') or raise 'rake failed'

      content_xml = extract_docx_content(Dir['*_draft_0.docx'].first)
      paragraphs = content_xml.scan(/<w:p\b.*?<\/w:p>/m)
      half_series_idx = paragraphs.index { |paragraph| paragraph.include?('Aristillus Engineering') && paragraph.include?('Club') && paragraph.include?('HalfTitleSeriesTitle') }
      half_conjunction_idx = paragraphs.index { |paragraph| paragraph.include?('and') && paragraph.include?('HalfTitleConjunction') }
      half_book_title_idx = paragraphs.index { |paragraph| paragraph.include?('Journey') && paragraph.include?('HalfTitleBookTitle') }
      series_idx = paragraphs.index { |paragraph| paragraph.include?('Aristillus Engineering') && paragraph.include?('Club') && paragraph.include?('TitlePageSeriesTitle') }
      conjunction_idx = paragraphs.index { |paragraph| paragraph.include?('and') && paragraph.include?('TitlePageConjunction') }
      book_title_idx = paragraphs.index { |paragraph| paragraph.include?('Journey') && paragraph.include?('TitlePageBookTitle') }
      author_idx = paragraphs.index { |paragraph| paragraph.include?('Test Author') && paragraph.include?('TitlePageSplitAuthor') }
      publisher_idx = paragraphs.index { |paragraph| paragraph.include?('Morlock Publishing') }
      logo_idx = paragraphs.index { |paragraph| paragraph.include?('<w:drawing') || paragraph.include?('<pic:pic') }
      toc_idx = paragraphs.index { |paragraph| paragraph.include?('DOCX_TOC_INSERT') }
      section_idx = (publisher_idx...toc_idx).find { |idx| paragraphs[idx].include?('<w:sectPr') }

      refute_nil half_series_idx
      assert half_series_idx < half_conjunction_idx
      assert half_conjunction_idx < half_book_title_idx
      assert half_book_title_idx < series_idx
      refute_nil series_idx
      assert series_idx < conjunction_idx
      assert conjunction_idx < book_title_idx
      assert book_title_idx < author_idx
      assert_match(/<w:br\b/, paragraphs[half_series_idx])
      assert_match(/<w:br\b/, paragraphs[half_book_title_idx])
      assert_match(/<w:br\b/, paragraphs[series_idx])
      assert_match(/<w:br\b/, paragraphs[book_title_idx])
      zero_indent = /<w:ind\b(?:(?=[^>]*w:left="0")(?=[^>]*w:firstLine="0")|(?=[^>]*w:start="0")(?=[^>]*w:hanging="0"))[^>]*\/>/
      [half_series_idx, half_conjunction_idx, half_book_title_idx, series_idx, conjunction_idx, book_title_idx, author_idx].each do |idx|
        assert_match(zero_indent, paragraphs[idx])
      end
      assert_match(/<w:spacing w:before="216" w:after="1296"\/>/, paragraphs[author_idx])
      assert_match(/<w:spacing w:before="1800" w:after="0"\/>/, paragraphs[publisher_idx])
      assert_match(/<w:pStyle w:val="TitlePagePublisher"\/>/, paragraphs[publisher_idx])
      refute_match(/DOCX_TITLE_PAGE_START/, content_xml)
      refute_nil logo_idx
      assert publisher_idx < section_idx, "publisher/logo block should stay before the title-page section break"
      assert logo_idx < section_idx, "logo should stay before the title-page section break"
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
          revision_history:
            - date: '2026-09-27'
              description: 'Reader links & <bibliography> updated.'
            - date: '2019-11'
              description: First published.
            - date: '2026-09'
              description: Typographical corrections.
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
      history = ['November 2019: First published.',
                 'September 2026: Typographical corrections.',
                 'September 27, 2026: Reader links &amp; &lt;bibliography&gt; updated.']
      history.each { |entry| assert_includes content_xml, entry }
      assert_equal 1, content_xml.scan('Revision history:').size
      history_paragraph = content_xml.scan(/<w:p\b.*?<\/w:p>/m).find { |p| p.include?(history.first) }
      assert_includes history_paragraph, '<w:ind w:left="360" w:firstLine="0"/>'
      assert_equal 2, history_paragraph.scan(/<w:br\s*\/>/).size
      assert_operator content_xml.index('Revision history:'), :<, content_xml.index(history.first)
      positions = history.map { |entry| content_xml.index(entry) }
      assert_equal positions.sort, positions
      assert_operator content_xml.index('Cover design by Jennifer Corcoran.'), :<, content_xml.index('Revision history:')
      assert_operator content_xml.index('Ebook ISBN: 978-1-235'), :<, content_xml.index('Revision history:')
      assert_operator content_xml.index('Printed in the United States of America'), :<, content_xml.index('Revision history:')
      publisher_paragraph = content_xml.scan(/<w:p\b.*?<\/w:p>/m).find { |p| p.include?('w:val="CopyrightPublisher"') }
      assert_operator positions.last, :<, content_xml.index(publisher_paragraph)
      assert_includes publisher_paragraph, 'w:y="10109"'
      assert_includes publisher_paragraph, 'w:vAnchor="page"'
      assert_includes publisher_paragraph, 'morlockpublishing.com'
      refute_includes publisher_paragraph, 'w:type="page"'
      File.write('.rakefile.yaml', yaml_content.sub('2026-09-27', '2026-02-30'))
      output = IO.popen(['rake', 'interleave_doc'], err: [:child, :out], &:read)
      refute $?.success?
      assert_includes output, 'revision_history date must be a valid YYYY-MM or YYYY-MM-DD'
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
      assert_equal 12, content_xml.scan('<w:br w:type="page"/>').size
      refute_match(/<w:br w:type="page"\/>\s*<\/w:p>\s*<w:p><w:bookmarkStart[^>]+w:name="RakefileManuscriptBody"/, content_xml)
      sections = content_xml.scan(/<w:sectPr\b.*?<\/w:sectPr>/m)
      assert_equal 3, sections.size
      title_section, frontmatter_section, body_section = sections
      assert_match(/<w:type w:val="nextPage"\/>/, title_section)
      refute_match(/w:headerReference|w:footerReference|w:pgNumType/, title_section)
      assert_match(/<w:type w:val="nextPage"\/>/, frontmatter_section)
      assert_match(/<w:footerReference w:type="default" r:id="#{Regexp.escape(odd_footer_id)}"\/>/, frontmatter_section)
      refute_match(/<w:footerReference w:type="even"/, frontmatter_section)
      assert_match(/<w:pgNumType w:fmt="lowerRoman" w:start="4"\/>/, frontmatter_section)
      assert_match(/<w:footerReference w:type="default" r:id="#{Regexp.escape(odd_footer_id)}"\/>/, body_section)
      assert_match(/<w:footerReference w:type="even" r:id="#{Regexp.escape(even_footer_id)}"\/>/, body_section)
      assert_match(/<w:type w:val="oddPage"\/>/, body_section)
      assert_match(/<w:pgNumType w:fmt="decimal" w:start="1"\/>/, body_section)
      refute_match(/r:id="rIdFooterOdd"|r:id="rIdFooterEven"/, content_xml)
      refute_match(/DOCX_FRONTMATTER_PAGE_BREAK_|DOCX_HALF_TITLE_PAGE_BREAK|DOCX_HALF_TITLE_VERSO_PAGE_BREAK|DOCX_HALF_TITLE_VERSO_START|DOCX_HALF_TITLE_VERSO_END|DOCX_ABOUT_AUTHOR_|DOCX_TITLE_PAGE_BREAK|DOCX_TOC_AFTER_PAGE_BREAK|DOCX_PUBLISHER_PAGE_BREAK|DOCX_ACT_PAGE_BREAK|DOCX_CHAPTER_PAGE_BREAK/, content_xml)
    end
  end

  def test_docx_adds_present_dedication_and_skips_missing_one
    Dir.chdir(@tmp) do
      File.write('dedication.md', "For the dogs.\n")
      File.write('front.md', "# Epigraph\n\nOpening words.\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_lopez.txt
        :dedication: dedication.md
        :frontmatter:
          - front.md
        :title: Test Novel
        :author: Test Author
        :target_words: 1000
        :chapter_head_tag: '** chapter'
        :date_start: '1 Jan 1970'
      YAML

      assert system('rake interleave_doc'), 'rake interleave_doc failed'
      xml = extract_docx_content(Dir['*_draft_0.docx'].first)

      assert_match(/<w:pStyle w:val="Dedication"\s*\/>.*?For the dogs\./m, xml)
      assert xml.index('Test Author') < xml.index('For the dogs.')
      assert xml.index('For the dogs.') < xml.index('Epigraph')
      assert_operator xml.index('For the dogs.'), :<, xml.index(/<w:br w:type="page"\s*\/>/, xml.index('For the dogs.'))

      File.delete('dedication.md')
      assert system('rake interleave_doc'), 'rake interleave_doc failed with an absent dedication'
      xml = extract_docx_content(Dir['*_draft_0.docx'].first)
      refute_includes xml, 'Dedication'
      refute_includes xml, 'For the dogs.'
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
        :aftermatter_other:
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
      File.write('stay.md', "Stay in touch.\n")
      File.write('.rakefile.yaml', <<~YAML)
        :target_files:
          - fixtures/story_lopez.txt
          - fixtures/story_spacex.txt
        :aftermatter_about_the_author: about.md
        :aftermatter_stay_connected: stay.md
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
      assert content_xml.index('Stay in touch.') < content_xml.index('About the Author')
      assert_match(/<w:pStyle w:val="AboutAuthorHeading"\s*\/>.*?Stay Connected/m, content_xml)
      assert_match(/<w:pStyle w:val="AboutAuthorBody"\s*\/>.*?Stay in touch\./m, content_xml)
      assert_equal 1, content_xml.scan('About the Author').size
      refute_match(/DOCX_(ABOUT_AUTHOR|STAY_CONNECTED)_/, content_xml)
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
      assert_match(/w:style w:type="paragraph" w:styleId="FirstParagraph".*?w:firstLine="0".*?w:sz w:val="22"/m, styles_xml)
      assert_match(/w:style w:type="paragraph" w:styleId="Compact".*?w:firstLine="0".*?w:after="0"/m, styles_xml)
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
