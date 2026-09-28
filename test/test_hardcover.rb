require 'minitest/autorun'
require 'rake'
require 'tmpdir'
load File.expand_path('../rakefile', __dir__)

class HardcoverTest < Minitest::Test
  def test_limits_presets_and_format_names
    config = {title: 'Book', draft: 2, print_binding: 'hardcover'}
    assert_equal 'Book_hc_draft_2.pdf', draft_output_file(config, 'pdf')
    assert_equal 'Book_tpb_draft_2.pdf', draft_output_file(config.merge(print_binding: 'paperback'), 'pdf')
    assert_equal 'Book_ebook_draft_2.docx', draft_output_file(config.merge(edition_format: 'ebook'), 'docx')
    assert_nil hardcover_layout_config(config.merge(edition_format: 'ebook'))
    assert_nil hardcover_layout_config(config.merge(print_binding: 'paperback'))
    layout = hardcover_layout_config(config)
    assert_equal [75, 550], layout.values_at('min_pages', 'max_pages')
    assert_equal [12, 12, 11.5, 11], layout['presets'].map { |p| p['body_size'] }
    [{min_pages: 0}, {max_pages: 74}, {max_pages: 550.5}, {unknown: true}, {presets: nil}].each do |invalid|
      assert_raises(RuntimeError) { hardcover_layout_config(config.merge(hardcover_layout: invalid)) }
    end
    [{body_size: 10}, {body_size: 11.75}, {leading: 12}, {leading: Float::INFINITY}, {top_margin: 9}, {bottom_margin: 0.1}].each do |invalid|
      preset = layout['presets'].first.merge(invalid.transform_keys(&:to_s))
      assert_raises(RuntimeError) { hardcover_layout_config(config.merge(hardcover_layout: {presets: [preset]})) }
    end
  end

  def test_rendered_page_limits_choose_first_fitting_layout_and_preserve_failed_outputs
    # Simulated renderer counts exercise threshold crossings without building six novels.
    [
      [[140], 'paperback', false, 1],
      [[550, 550], 'paperback', false, 2],
      [[75], 'paperback', false, 1],
      [[592, 592, 551, 538], 'compact_spacing', false, 4],
      [[74], nil, true, 1],
      [[600, 600, 580, 570, 560, 552], nil, true, 6]
    ].each do |page_counts, selected, failure, expected_builds|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          File.write('styles.yaml', "styles:\n  normal:\n    size: 12\n    line_spacing_points: 15\n")
          original = File.read('styles.yaml')
          config = {title: 'HC Test', print_binding: 'hardcover', docx_styles: 'styles.yaml'}
          pdf = draft_output_file(config, 'pdf')
          File.write(pdf, 'previous good PDF')
          builds = []
          builder = lambda do |effective|
            styles = load_docx_styles(docx_styles_file(effective))
            builds << styles
            File.write(draft_output_file(effective, 'docx'), 'docx')
          end
          exporter = lambda { |_docx, path| File.write(path, 'new PDF'); true }
          stdout, = capture_io do
            stub(:generate_interleaved_docx, builder) do
              stub(:convert_docx_to_pdf_with_libreoffice, exporter) do
                stub(:generated_pdf_page_count, ->(_path) { page_counts.shift }) do
                  if failure
                    assert_raises(RuntimeError) { generate_edition_document(config, pdf: true) }
                  else
                    generate_edition_document(config, pdf: true)
                  end
                end
              end
            end
          end
          assert_equal expected_builds, builds.length
          assert_equal original, File.read('styles.yaml')
          assert_equal(failure ? 'previous good PDF' : 'new PDF', File.read(pdf))
          assert_includes stdout, "Selected hardcover layout: #{selected}" unless failure
          if selected == 'paperback'
            assert_equal 12, builds.last['styles']['normal']['size']
            assert_equal 15, builds.last['styles']['normal']['line_spacing_points']
            assert_equal 0.79, builds.last['page']['margin_top_inches']
          elsif selected == 'compact_spacing'
            %w[normal first_paragraph compact].each do |name|
              assert_equal 12, builds.last['styles'][name]['size']
              assert_equal 14, builds.last['styles'][name]['line_spacing_points']
            end
            assert_equal 0.95, builds.last['page']['margin_left_inches']
            assert_in_delta 0.6, builds.last['page']['footer_margin_inches'], 0.0001
          end
        end
      end
    end
  end
end
