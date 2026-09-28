require 'minitest/autorun'
require 'rake'
require 'tmpdir'
require 'zip'
require 'nokogiri'
load File.expand_path('../rakefile', __dir__)

class TypographyTest < Minitest::Test
  NS = { 'w' => 'http://schemas.openxmlformats.org/wordprocessingml/2006/main' }.freeze

  def test_paperback_margin_bands_and_overrides
    {1 => 0.70, 199 => 0.70, 200 => 0.80, 399 => 0.80,
     400 => 0.90, 499 => 0.90, 500 => 0.95, 700 => 0.95}.each do |count, margin|
      assert_equal margin, paperback_inside_margin(count)
    end
    [0, -1, 200.5].each { |count| assert_raises(RuntimeError) { paperback_inside_margin(count) } }
    Dir.mktmpdir do |dir|
      config = {docx_styles: File.join(dir, 'styles.yaml')}
      assert_equal 'auto', print_margin_policy(config)
      assert_nil print_margin_policy(config.merge(edition_format: 'ebook'))
      assert_equal 'auto', print_margin_policy(config.merge(print_binding: 'hardcover'))
      assert_nil print_margin_policy(config.merge(print_margins: false))
      assert_equal({'inside' => 1.0, 'outside' => 0.6}, print_margin_policy(config.merge(print_margins: {inside: 1.0, outside: 0.6})))
      [nil, true, 'guess', {inside: -1, outside: 0.6}, {inside: 1}, {inside: 4, outside: 3}, {inside: Float::INFINITY, outside: 1}].each do |bad|
        assert_raises(RuntimeError) { print_margin_policy(config.merge(print_margins: bad)) }
      end
      File.write(config[:docx_styles], "page:\n  width_inches: 8.5\n  height_inches: 11\n")
      assert_nil print_margin_policy(config)
    end
  end

  def test_automatic_margins_rebuild_when_pagination_crosses_a_band
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        config = {title: 'Margin test', docx_styles: 'styles.yaml'}
        File.write('styles.yaml', "page:\n  margin_top_inches: 0.8\n")
        builds = []
        counts = [220, 405, 503, 510]
        build = lambda do |effective|
          page = load_docx_styles(docx_styles_file(effective))['page']
          builds << page['margin_left_inches']
          assert_equal 0.65, page['margin_right_inches']
          assert_equal 0.8, page['margin_top_inches']
          assert_equal true, page['mirror_margins']
          File.write(draft_output_file(effective, 'docx'), 'docx')
        end
        convert = lambda { |_docx, pdf| File.write(pdf, 'verified pdf'); true }
        stub(:generate_interleaved_docx, build) do
          stub(:convert_docx_to_pdf_with_libreoffice, convert) do
            stub(:generated_pdf_page_count, ->(_pdf) { counts.shift }) do
              generate_edition_document(config, pdf: true)
            end
          end
        end
        assert_equal [0.70, 0.80, 0.90, 0.95], builds
        assert_equal 'verified pdf', File.read(draft_output_file(config, 'pdf'))
        assert_equal "page:\n  margin_top_inches: 0.8\n", File.read('styles.yaml')
        File.write(draft_output_file(config, 'pdf'), 'previous good PDF')
        stub(:generate_interleaved_docx, build) do
          stub(:convert_docx_to_pdf_with_libreoffice, false) do
            assert_raises(SystemExit) { generate_edition_document(config, pdf: true) }
          end
        end
        assert_equal 'previous good PDF', File.read(draft_output_file(config, 'pdf'))
      end
    end
  end

  def test_body_defaults_exact_print_leading_and_reader_adjustable_ebook_spacing
    defaults = default_docx_styles
    assert_equal 'EB Garamond', defaults['font']
    %w[normal first_paragraph compact].each do |name|
      assert_equal 12, defaults['styles'][name]['size']
      assert_equal 0, defaults['styles'][name]['spacing_after_points']
    end
    [false, true].each do |print|
      styles = Marshal.load(Marshal.dump(defaults))
      %w[normal first_paragraph compact].each do |name|
        styles['styles'][name]['line_spacing_points'] = 15 if print
      end
      xml = Nokogiri::XML(default_reference_styles_xml(styles))
      %w[Normal BodyText FirstParagraph Compact].each do |id|
        node = xml.at_xpath("//w:style[@w:styleId='#{id}']", NS)
        assert_equal '24', node.at_xpath('w:rPr/w:sz', NS)['w:val'], id
        assert_equal 'EB Garamond', node.at_xpath('w:rPr/w:rFonts', NS)['w:ascii'], id
        spacing = node.at_xpath('w:pPr/w:spacing', NS)
        assert_equal(print ? '300' : '240', spacing['w:line'], id)
        assert_equal(print ? 'exact' : 'auto', spacing['w:lineRule'], id)
      end
    end
    assert_equal 300, docx_line_spacing_twips('line_spacing' => 1.25)
    assert_equal 360, docx_line_spacing_twips('line_spacing' => '1.5')
    assert_equal 480, docx_line_spacing_twips('line_spacing' => 'double')
    assert_raises(RuntimeError) { docx_line_spacing_twips('line_spacing_points' => -15) }
    assert_raises(RuntimeError) { docx_line_spacing_twips('line_spacing' => 0) }
  end

  def test_exact_body_leading_does_not_clip_headings_or_inline_art
    styles = default_docx_styles
    styles['styles']['normal']['line_spacing_points'] = 15
    xml = Nokogiri::XML(default_reference_styles_xml(styles))
    %w[Heading1 Heading2 Heading3 FrontmatterHeading1 FrontmatterHeading2 TitlePageTitle TitlePageAuthor CaptionedFigure].each do |id|
      spacing = xml.at_xpath("//w:style[@w:styleId='#{id}']/w:pPr/w:spacing", NS)
      assert_equal 'auto', spacing['w:lineRule'], id
      assert_equal '240', spacing['w:line'], id
    end
    ['<w:pPr/>', '<w:pPr><w:spacing w:before="120" w:line="300" w:lineRule="exact"/></w:pPr>', ''].each do |properties|
      paragraph = "<w:p>#{properties}<w:r><w:drawing><wp:inline/></w:drawing></w:r></w:p>"
      result = allow_docx_inline_image_height(paragraph)
      assert_includes result, 'w:line="240" w:lineRule="auto"'
      assert_includes result, 'w:before="120"' if properties.include?('w:before')
      assert_equal result, allow_docx_inline_image_height(result)
    end
    plain = '<w:p><w:r><w:t>Body text</w:t></w:r></w:p>'
    assert_equal plain, allow_docx_inline_image_height(plain)
  end

  def test_cast_entries_use_compact_readable_layout_independent_of_body_settings
    styles = default_docx_styles
    styles['styles']['normal'].merge!('size' => 16, 'line_spacing_points' => 22)
    xml = Nokogiri::XML(default_reference_styles_xml(styles))
    entry = xml.at_xpath("//w:style[@w:styleId='FrontmatterDramatis']", NS)
    assert_equal 'EB Garamond', entry.at_xpath('w:rPr/w:rFonts', NS)['w:ascii']
    assert_equal '22', entry.at_xpath('w:rPr/w:sz', NS)['w:val']
    spacing = entry.at_xpath('w:pPr/w:spacing', NS)
    assert_equal '260', spacing['w:line']
    assert_equal 'exact', spacing['w:lineRule']
    assert_equal '60', spacing['w:after']
    indent = entry.at_xpath('w:pPr/w:ind', NS)
    assert_equal '216', indent['w:left']
    assert_equal '216', indent['w:hanging']
    assert_nil entry.at_xpath('w:pPr/w:tabs', NS), 'Descriptions should not jump to tab columns'
    assert entry.at_xpath('w:pPr/w:suppressAutoHyphens', NS)
    {'FrontmatterDramatisHeading' => '30', 'FrontmatterDramatisSubheading' => '22'}.each do |id, size|
      heading = xml.at_xpath("//w:style[@w:styleId='#{id}']", NS)
      assert_equal size, heading.at_xpath('w:rPr/w:sz', NS)['w:val']
      assert heading.at_xpath('w:pPr/w:keepNext', NS)
    end
  end

  def test_pdf_export_embeds_user_installed_font_without_xdg_override
    skip 'LibreOffice and pdffonts required' unless executable_in_path('libreoffice', 'soffice') && executable_in_path('pdffonts')
    skip 'EB Garamond required' unless IO.popen(['fc-match', '-f', '%{family}', 'EB Garamond'], &:read).include?('EB Garamond')
    previous_data_home = ENV.delete('XDG_DATA_HOME')
    begin
      Dir.mktmpdir do |dir|
        docx = File.join(dir, 'font-check.docx')
        pdf = File.join(dir, 'font-check.pdf')
        create_default_reference_docx(docx)
        Zip::File.open(docx) do |zip|
          xml = zip.read('word/document.xml').sub('<w:body>', '<w:body><w:p><w:r><w:rPr><w:rFonts w:ascii="EB Garamond" w:hAnsi="EB Garamond"/></w:rPr><w:t>Garamond PDF export check</w:t></w:r></w:p>')
          zip.get_output_stream('word/document.xml') { |stream| stream.write(xml) }
        end
        assert convert_docx_to_pdf_with_libreoffice(docx, pdf)
        fonts = IO.popen(['pdffonts', pdf], &:read)
        assert_match(/EBGaramond.*\byes\s+yes\b/, fonts, 'PDF must embed Garamond, not silently substitute a system font')
        refute_includes fonts, 'DejaVuSans'
      end
    ensure
      ENV['XDG_DATA_HOME'] = previous_data_home
    end
  end

  def test_cached_reference_refreshes_when_inherited_body_typography_changes
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write('.docx_styles.yaml', "font: EB Garamond\n")
        create_default_reference_docx('.default.docx')
        Zip::File.open('.default.docx') do |zip|
          xml = zip.read('word/styles.xml').gsub('w:sz w:val="24"', 'w:sz w:val="22"')
          zip.get_output_stream('word/styles.xml') { |f| f.write(xml) }
        end
        refute docx_reference_styles_match?('.default.docx', load_docx_styles)
        refresh_default_docx_reference_if_needed({})
        assert docx_reference_styles_match?('.default.docx', load_docx_styles)
        before = File.binread('.default.docx')
        refresh_default_docx_reference_if_needed({})
        assert_equal before, File.binread('.default.docx'), 'Unchanged defaults should not rebuild'
      end
    end
  end
end
