require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'set'
require 'rake'

REPO_RAKEFILE = File.expand_path('../rakefile', __dir__)
load REPO_RAKEFILE

class PragmasTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir('pragma_test')
    Dir.chdir(@tmp) do
      FileUtils.mkdir_p('fixtures')
      FileUtils.cp REPO_RAKEFILE, 'rakefile'
    end
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp && Dir.exist?(@tmp)
  end

  def test_parse_pragmas_define_tag
    Dir.chdir(@tmp) do
      # Test pragma parsing for DEFINE-TAG
      chapter_text = <<~TEXT
        ** chapter 1: setup
        # DEFINE-TAG: story-setup
        Some content here.
      TEXT
      
      pragmas = parse_pragmas_from_chapter_text(chapter_text)
      
      assert_equal "story-setup", pragmas[:defines]
      assert_equal [], pragmas[:depends_on]
      assert_equal [], pragmas[:must_come_before]
    end
  end

  def test_parse_pragmas_must_be_after
    Dir.chdir(@tmp) do
      # Test pragma parsing for MUST-BE-AFTER
      chapter_text = <<~TEXT
        ** chapter 2: climax
        # MUST-BE-AFTER: story-setup, character-intro
        Story climax here.
      TEXT
      
      pragmas = parse_pragmas_from_chapter_text(chapter_text)
      
      assert_equal nil, pragmas[:defines]
      assert_equal ["story-setup", "character-intro"], pragmas[:depends_on]
      assert_equal [], pragmas[:must_come_before]
    end
  end

  def test_parse_pragmas_multiple_must_be_after
    Dir.chdir(@tmp) do
      # Test multiple MUST-BE-AFTER lines accumulate dependencies
      chapter_text = <<~TEXT
        ** chapter 3: finale
        # MUST-BE-AFTER: setup
        # MUST-BE-AFTER: climax
        Final chapter content.
      TEXT
      
      pragmas = parse_pragmas_from_chapter_text(chapter_text)
      
      assert_equal nil, pragmas[:defines]
      assert_equal ["setup", "climax"], pragmas[:depends_on]
      assert_equal [], pragmas[:must_come_before]
    end
  end

  def test_parse_pragmas_must_be_before
    Dir.chdir(@tmp) do
      # Test pragma parsing for MUST-BE-BEFORE
      chapter_text = <<~TEXT
        ** chapter 1: early-setup
        # MUST-BE-BEFORE: story-climax, character-arc
        Early setup content.
      TEXT
      
      pragmas = parse_pragmas_from_chapter_text(chapter_text)
      
      assert_equal nil, pragmas[:defines]
      assert_equal [], pragmas[:depends_on]
      assert_equal ["story-climax", "character-arc"], pragmas[:must_come_before]
    end
  end

  def test_parse_pragmas_multiple_must_be_before
    Dir.chdir(@tmp) do
      # Test multiple MUST-BE-BEFORE lines accumulate dependencies
      chapter_text = <<~TEXT
        ** chapter 2: development
        # MUST-BE-BEFORE: climax
        # MUST-BE-BEFORE: resolution
        Development content.
      TEXT
      
      pragmas = parse_pragmas_from_chapter_text(chapter_text)
      
      assert_equal nil, pragmas[:defines]
      assert_equal [], pragmas[:depends_on]
      assert_equal ["climax", "resolution"], pragmas[:must_come_before]
    end
  end

  def test_parse_pragmas_both_define_and_depend
    Dir.chdir(@tmp) do
      # Test chapter that both defines and depends on tags
      chapter_text = <<~TEXT
        ** chapter 5: plot-twist
        # DEFINE-TAG: major-twist
        # MUST-BE-AFTER: setup, character-arc
        Plot twist content here.
      TEXT
      
      pragmas = parse_pragmas_from_chapter_text(chapter_text)
      
      assert_equal "major-twist", pragmas[:defines]
      assert_equal ["setup", "character-arc"], pragmas[:depends_on]
      assert_equal [], pragmas[:must_come_before]
    end
  end

  def test_parse_pragmas_with_whitespace
    Dir.chdir(@tmp) do
      # Test pragma parsing tolerates extra whitespace
      chapter_text = <<~TEXT
        ** chapter 1: test
        #   DEFINE-TAG:   tag-name  
        #   MUST-BE-AFTER:  tag1  ,  tag2  ,  tag3
        Content.
      TEXT
      
      pragmas = parse_pragmas_from_chapter_text(chapter_text)
      
      assert_equal "tag-name", pragmas[:defines]
      assert_equal ["tag1", "tag2", "tag3"], pragmas[:depends_on]
      assert_equal [], pragmas[:must_come_before]
    end
  end

  def test_parse_pragmas_no_pragmas
    Dir.chdir(@tmp) do
      # Test chapter with no pragmas
      chapter_text = <<~TEXT
        ** chapter 1: normal
        Just regular content here.
        No pragmas at all.
      TEXT
      
      pragmas = parse_pragmas_from_chapter_text(chapter_text)
      
      assert_equal nil, pragmas[:defines]
      assert_equal [], pragmas[:depends_on]
      assert_equal [], pragmas[:must_come_before]
    end
  end

  def test_build_pragma_registry
    Dir.chdir(@tmp) do
      # Create two files with pragmas
      File.write('fixtures/story_lopez.txt', <<~TEXT)
        ** chapter 1: setup
        # DEFINE-TAG: lopez-setup
        Lopez setup content.
        
        ** chapter 2: climax
        # MUST-BE-AFTER: mackenzie-intro
        Lopez climax content.
      TEXT
      
      File.write('fixtures/story_mackenzie.txt', <<~TEXT)
        ** chapter 1: intro
        # DEFINE-TAG: mackenzie-intro
        Mackenzie intro content.
        
        ** chapter 2: resolution
        # MUST-BE-AFTER: lopez-setup
        Mackenzie resolution content.
      TEXT
      
      all_data = {}
      all_files = ['fixtures/story_lopez.txt', 'fixtures/story_mackenzie.txt']
      all_files.each do |file|
        all_data[file] = parse_chapters_and_acts_from_file(file, {:chapter_head_tag => '** chapter'})
      end
      
      registry = build_pragma_registry(all_data, all_files)
      
      # Check tag definitions
      assert_equal "fixtures/story_lopez.txt:1", registry[:tag_definitions]["lopez-setup"]
      assert_equal "fixtures/story_mackenzie.txt:1", registry[:tag_definitions]["mackenzie-intro"]
      
      # Check dependencies
      assert_equal ["mackenzie-intro"], registry[:chapter_dependencies]["fixtures/story_lopez.txt:2"]
      assert_equal ["lopez-setup"], registry[:chapter_dependencies]["fixtures/story_mackenzie.txt:2"]
      
      # Check no undefined or circular tags
      assert_equal [], registry[:undefined_tags]
      assert_equal [], registry[:circular_deps]
    end
  end

  def test_pragma_registry_undefined_tag
    Dir.chdir(@tmp) do
      # Create a file with undefined tag reference
      File.write('fixtures/bad.txt', <<~TEXT)
        ** chapter 1: test
        # MUST-BE-AFTER: nonexistent-tag
        Content.
      TEXT
      
      all_data = {}
      all_data['fixtures/bad.txt'] = parse_chapters_and_acts_from_file('fixtures/bad.txt', {:chapter_head_tag => '** chapter'})
      
      registry = build_pragma_registry(all_data, ['fixtures/bad.txt'])
      
      # Should report undefined tag
      assert_includes registry[:undefined_tags], "nonexistent-tag"
    end
  end

  def test_pragma_registry_unused_tag
    Dir.chdir(@tmp) do
      # Create a file where a tag is defined but never used
      File.write('fixtures/unused.txt', <<~TEXT)
        ** chapter 1: setup
        # DEFINE-TAG: never-used-tag
        Content here.
        
        ** chapter 2: main
        Just content.
      TEXT
      
      all_data = {}
      all_data['fixtures/unused.txt'] = parse_chapters_and_acts_from_file('fixtures/unused.txt', {:chapter_head_tag => '** chapter'})
      
      registry = build_pragma_registry(all_data, ['fixtures/unused.txt'])
      
      # Should report unused tag
      assert_includes registry[:unused_tags], "never-used-tag"
    end
  end

  def test_topological_sort_simple
    Dir.chdir(@tmp) do
      # Build a simple dependency graph: 1 -> 2 -> 3
      tag_definitions = {
        "tag-a" => "file1:1",
        "tag-b" => "file1:2",
        "tag-c" => "file1:3"
      }
      
      chapter_dependencies = {
        "file1:2" => ["tag-a"],
        "file1:3" => ["tag-b"]
      }
      
      all_chapters = ["file1:1", "file1:2", "file1:3"]
      
      sorted = topological_sort_chapters(chapter_dependencies, {}, tag_definitions, all_chapters)
      
      # Check order respects dependencies
      idx_1 = sorted.index("file1:1")
      idx_2 = sorted.index("file1:2")
      idx_3 = sorted.index("file1:3")
      
      assert idx_1 < idx_2, "Chapter 1 should come before chapter 2"
      assert idx_2 < idx_3, "Chapter 2 should come before chapter 3"
    end
  end

  def test_topological_sort_diamond_dependency
    Dir.chdir(@tmp) do
      # Diamond pattern: 1 <- {2, 3}, both 2 and 3 depend on 1
      tag_definitions = {
        "start" => "file1:1",
        "path-a" => "file1:2",
        "path-b" => "file1:3",
        "end" => "file1:4"
      }
      
      chapter_dependencies = {
        "file1:2" => ["start"],
        "file1:3" => ["start"],
        "file1:4" => ["path-a", "path-b"]
      }
      
      all_chapters = ["file1:1", "file1:2", "file1:3", "file1:4"]
      
      sorted = topological_sort_chapters(chapter_dependencies, {}, tag_definitions, all_chapters)
      
      # Check order respects dependencies
      idx_1 = sorted.index("file1:1")
      idx_4 = sorted.index("file1:4")
      
      assert idx_1 < idx_4, "Start should come before end"
    end
  end

  def test_topological_sort_no_dependencies
    Dir.chdir(@tmp) do
      # All chapters independent
      tag_definitions = {}
      chapter_dependencies = {}
      all_chapters = ["file1:1", "file1:2", "file1:3"]
      
      sorted = topological_sort_chapters(chapter_dependencies, {}, tag_definitions, all_chapters)
      
      # Should still return all chapters
      assert_equal 3, sorted.size
      assert_equal Set.new(all_chapters), Set.new(sorted)
    end
  end

  def test_pragma_reordering_actually_applied
    Dir.chdir(@tmp) do
      # Create two files where the second file needs to come before first due to pragmas
      File.write('fixtures/story_a.txt', <<~TEXT)
        ** chapter 1: intro
        # MUST-BE-AFTER: b-setup
        A intro content.
        
        ** chapter 2: climax
        A climax content.
      TEXT
      
      File.write('fixtures/story_b.txt', <<~TEXT)
        ** chapter 1: setup
        # DEFINE-TAG: b-setup
        B setup content.
      TEXT
      
      # Create .rakefile.yaml
      File.write('.rakefile.yaml', <<~YAML)
:target_files:
  - fixtures/story_a.txt
  - fixtures/story_b.txt
:title: "Test Pragma Ordering"
:target_words: 1000
:date_start: '2026-03-06'
:chapter_head_tag: '** chapter'
YAML
      
      # Run the task
      system('rake interleave_txt') or raise 'rake failed'
      
      # Read output and verify ordering
      output = File.read('output.txt')
      
      # B's chapter 1 should appear before A's chapter 1 despite file order
      # Because A's chapter 1 depends on B's setup
      b_pos = output.index("B setup content")
      a_pos = output.index("A intro content")
      
      assert b_pos < a_pos, "B setup (dependency) should appear before A intro (dependent)"
    end
  end

  def test_pragma_sort_preserves_source_file_chapter_order
    Dir.chdir(@tmp) do
      File.write('fixtures/story_a.txt', <<~TEXT)
        ** chapter 1: delayed intro
        # MUST-BE-AFTER: b-setup
        A chapter one content.

        ** chapter 2: should stay after one
        A chapter two content.
      TEXT

      File.write('fixtures/story_b.txt', <<~TEXT)
        ** chapter 1: setup
        # DEFINE-TAG: b-setup
        B setup content.
      TEXT

      File.write('.rakefile.yaml', <<~YAML)
:target_files:
  - fixtures/story_a.txt
  - fixtures/story_b.txt
:title: "Test Source Order"
:target_words: 1000
:date_start: '2026-03-06'
:chapter_head_tag: '** chapter'
YAML

      system('rake interleave_txt') or raise 'rake failed'

      output = File.read('output.txt')
      a1_pos = output.index("A chapter one content")
      a2_pos = output.index("A chapter two content")

      assert a1_pos < a2_pos, "A chapter 1 should stay before A chapter 2"
    end
  end

  def test_pragma_constraint_violation_caught
    Dir.chdir(@tmp) do
      # Create a scenario where pragmas create an impossible constraint
      # File A has chapters that depend on each other in a circular way
      File.write('fixtures/circular.txt', <<~TEXT)
        ** chapter 1: first
        # MUST-BE-AFTER: tag2
        First content.
        
        ** chapter 2: second
        # DEFINE-TAG: tag1
        # MUST-BE-AFTER: tag1
        Second content (depends on itself).
      TEXT
      
      # Create .rakefile.yaml
      File.write('.rakefile.yaml', <<~YAML)
:target_files:
  - fixtures/circular.txt
:title: "Test Circular Dependency"
:target_words: 1000
:date_start: '2026-03-06'
:chapter_head_tag: '** chapter'
YAML
      
      # Circular dependency should be caught during pragma validation
      result = system('rake interleave_txt 2>&1')
      assert !result, "Task should fail due to circular dependency"
    end
  end
end
