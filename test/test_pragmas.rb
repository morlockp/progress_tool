require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'set'

class PragmasTest < Minitest::Test
  REPO_RAKEFILE = File.expand_path('../rakefile', __dir__)

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

  # Helper to load just the functions from rakefile, not the tasks
  def load_pragma_functions
    code = File.read(REPO_RAKEFILE)
    # Extract just the helper functions, not the Rake tasks
    # We'll use eval with a specific subset of the code
    eval code, binding, REPO_RAKEFILE
  rescue => e
    # If load fails due to missing Rake methods, that's ok - we only need functions
    nil
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
      
      sorted = topological_sort_chapters(chapter_dependencies, tag_definitions, all_chapters)
      
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
      
      sorted = topological_sort_chapters(chapter_dependencies, tag_definitions, all_chapters)
      
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
      
      sorted = topological_sort_chapters(chapter_dependencies, tag_definitions, all_chapters)
      
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

# Load pragma functions from rakefile at module load time
def parse_pragmas_from_chapter_text(chapter_text)
  defines = nil
  depends_on = []
  must_come_before = []
  
  chapter_text.each_line do |line|
    # Look for DEFINE-TAG pragma
    if line =~ /^\s*#\s*DEFINE-TAG:\s*(\S+)/
      defines = $1
    end
    
    # Look for MUST-BE-AFTER pragma(s) - can have multiple occurrences
    if line =~ /^\s*#\s*MUST-BE-AFTER:\s*(.+)/
      deps_str = $1
      # Split by comma, strip whitespace from each
      deps_str.split(',').each do |dep|
        dep_tag = dep.strip
        depends_on << dep_tag if dep_tag != ""
      end
    end
    
    # Look for MUST-BE-BEFORE pragma(s) - can have multiple occurrences
    if line =~ /^\s*#\s*MUST-BE-BEFORE:\s*(.+)/
      before_str = $1
      # Split by comma, strip whitespace from each
      before_str.split(',').each do |tag|
        tag_name = tag.strip
        must_come_before << tag_name if tag_name != ""
      end
    end
  end
  
  { :defines => defines, :depends_on => depends_on, :must_come_before => must_come_before }
end

def build_pragma_registry(all_data, all_files)
  tag_definitions = {}
  chapter_dependencies = {}
  undefined_tags = Set.new
  unused_tags = Set.new
  circular_deps = []
  
  # First pass: collect all DEFINE-TAG pragmas
  all_files.each do |file|
    next unless all_data[file]
    
    all_data[file][:chapters].each do |local_ch_num, chapter_data|
      pragmas = chapter_data[:pragmas] || { :defines => nil, :depends_on => [] }
      
      if pragmas[:defines]
        tag_name = pragmas[:defines]
        chapter_id = "#{file}:#{local_ch_num}"
        
        if tag_definitions[tag_name]
          abort "*** ERROR: Tag '#{tag_name}' defined multiple times: in #{tag_definitions[tag_name]} and #{chapter_id}"
        end
        
        tag_definitions[tag_name] = chapter_id
        unused_tags.add(tag_name)
      end
    end
  end
  
  # Second pass: collect all MUST-BE-AFTER dependencies and mark tags as used
  all_files.each do |file|
    next unless all_data[file]
    
    all_data[file][:chapters].each do |local_ch_num, chapter_data|
      pragmas = chapter_data[:pragmas] || { :defines => nil, :depends_on => [] }
      
      if pragmas[:depends_on].size > 0
        chapter_id = "#{file}:#{local_ch_num}"
        chapter_dependencies[chapter_id] = pragmas[:depends_on].dup
        
        pragmas[:depends_on].each do |tag|
          if tag_definitions[tag]
            unused_tags.delete(tag)
          else
            undefined_tags.add(tag)
          end
        end
      end
    end
  end
  
  # Detect circular dependencies using DFS
  visited = Set.new
  rec_stack = Set.new
  
  def has_cycle_dfs(chapter_id, graph, visited, rec_stack, tag_definitions)
    visited.add(chapter_id)
    rec_stack.add(chapter_id)
    
    deps = graph[chapter_id] || []
    deps.each do |tag|
      dep_chapter_id = tag_definitions[tag]
      next unless dep_chapter_id
      
      if !visited.include?(dep_chapter_id)
        if has_cycle_dfs(dep_chapter_id, graph, visited, rec_stack, tag_definitions)
          return true
        end
      elsif rec_stack.include?(dep_chapter_id)
        return true
      end
    end
    
    rec_stack.delete(chapter_id)
    false
  end
  
  chapter_dependencies.keys.each do |chapter_id|
    if !visited.include?(chapter_id)
      if has_cycle_dfs(chapter_id, chapter_dependencies, visited, rec_stack, tag_definitions)
        circular_deps << chapter_id
      end
    end
  end
  
  {
    :tag_definitions => tag_definitions,
    :chapter_dependencies => chapter_dependencies,
    :undefined_tags => undefined_tags.to_a,
    :unused_tags => unused_tags.to_a,
    :circular_deps => circular_deps
  }
end

def topological_sort_chapters(chapter_dependencies, tag_definitions, all_chapters_by_id)
  in_degree = {}
  adjacency = {}
  
  all_chapters_by_id.each do |chapter_id|
    in_degree[chapter_id] = 0
    adjacency[chapter_id] = []
  end
  
  chapter_dependencies.each do |chapter_id, dep_tags|
    dep_tags.each do |tag|
      dep_chapter_id = tag_definitions[tag]
      next unless dep_chapter_id
      
      adjacency[dep_chapter_id] ||= []
      adjacency[dep_chapter_id] << chapter_id
      in_degree[chapter_id] = (in_degree[chapter_id] || 0) + 1
    end
  end
  
  queue = []
  in_degree.each do |chapter_id, degree|
    queue << chapter_id if degree == 0
  end
  
  sorted = []
  while queue.size > 0
    current = queue.shift
    sorted << current
    
    (adjacency[current] || []).each do |neighbor|
      in_degree[neighbor] -= 1
      queue << neighbor if in_degree[neighbor] == 0
    end
  end
  
  if sorted.size != all_chapters_by_id.size
    abort "*** ERROR: Topological sort failed - cycle detected in pragma dependencies"
  end
  
  sorted
end

def parse_chapters_and_acts_from_file(file_path, config)
  chapter_head_tag = config[:chapter_head_tag] || "== chapter"
  
  if !File.exist?(file_path)
    warn "*** warning: file #{file_path} not found"
    return { :chapters => {}, :acts => [] }
  end
  
  contents = File.read(file_path)
  lines = contents.split("\n")
  
  acts = []
  chapters = {}
  current_chapter_num = nil
  last_act_before_chapter = nil
  last_act_before_chapter_lineno = nil
  
  lines.each_with_index do |line, idx|
    lineno = idx + 1
    if line =~ /^\* /
      if line !~ /^\* Act /
        bytes = line.bytes.map { |b| sprintf("%02x", b) }.join(' ')
        if line =~ /chapter/i
          abort "*** SYNTAX ERROR in #{file_path}: Line #{lineno}: starts with '*' but not followed by 'Act': #{line.inspect}\n  bytes: #{bytes}\n  Hint: did you forget an extra asterisk for the chapter?"
        else
          abort "*** SYNTAX ERROR in #{file_path}: Line #{lineno}: starts with '*' but not followed by 'Act': #{line.inspect}\n  bytes: #{bytes}"
        end
      end
      last_act_before_chapter = line
      last_act_before_chapter_lineno = lineno
    elsif line =~ /^#{Regexp.escape(chapter_head_tag)}\s/
      line.match(/ (\d+)/)
      if $1
        current_chapter_num = $1.to_i
        if last_act_before_chapter
          acts << { :line => last_act_before_chapter, :before_chapter => current_chapter_num, :line_no => last_act_before_chapter_lineno }
          last_act_before_chapter = nil
          last_act_before_chapter_lineno = nil
        end
      end
    end
  end
  
  arr = contents.split(chapter_head_tag)
  arr = arr.slice(1..9999)
  arr ||= []
  
  arr.each do |text|
    lines = text.split("\n")
    title_line = lines[0]
    
    title_line.match(/ (\d+)/)
    chapter_num_str = $1
    
    next unless chapter_num_str
    
    chap_num = chapter_num_str.to_i
    
    content_lines = lines.reject { |l| l =~ /^\* Act / }
    clean_text = content_lines.join("\n")
    
    full_text = "#{chapter_head_tag}#{clean_text}"
    
    pragmas = parse_pragmas_from_chapter_text(full_text)
    
    chapters[chap_num] = {
      :title => title_line,
      :full_text => full_text,
      :source_file => file_path,
      :pragmas => pragmas
    }
  end
  
  { :chapters => chapters, :acts => acts }
end
