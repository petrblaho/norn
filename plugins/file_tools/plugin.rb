require_relative "path_helper"

class FileToolsPlugin < Norn::Plugin
  def self.plugin_name
    "file_tools"
  end

  def on_tool_register(registry)
    # 1. file_read
    registry.register(Norn::Tool.new(
      "file_read",
      "Read the contents of a file within the workspace, optionally specifying start line and maximum lines.",
      {
        type: "object",
        properties: {
          path: { type: "string", description: "Path of the file relative to workspace root" },
          offset: { type: "integer", description: "Line number to start reading from (1-indexed, optional)" },
          limit: { type: "integer", description: "Maximum number of lines to read (optional)" }
        },
        required: ["path"]
      },
      required_capabilities: [:sys_read]
    ) { |args|
      path = args[:path]
      offset = args[:offset] || 1
      limit = args[:limit]

      abs_path = Norn::Plugins::FileTools::PathHelper.resolve_and_verify(path)
      raise Errno::ENOENT, "File not found: #{path}" unless File.exist?(abs_path)
      raise "Cannot read a directory as a file." if File.directory?(abs_path)

      lines = File.readlines(abs_path)
      offset_idx = [offset.to_i - 1, 0].max
      limit_val = limit ? limit.to_i : lines.size

      selected_lines = lines[offset_idx, limit_val] || []
      selected_lines.map.with_index(offset_idx + 1) { |line, idx| "#{idx}: #{line.chomp}" }.join("\n")
    })

    # 2. file_write
    registry.register(Norn::Tool.new(
      "file_write",
      "Write content to a file. Overwrites any existing file at the path.",
      {
        type: "object",
        properties: {
          path: { type: "string", description: "Path of the file relative to workspace root" },
          content: { type: "string", description: "The content to write into the file" }
        },
        required: ["path", "content"]
      },
      required_capabilities: [:sys_write],
      dangerous: true
    ) { |args|
      path = args[:path]
      content = args[:content]

      abs_path = Norn::Plugins::FileTools::PathHelper.resolve_and_verify(path)
      
      # Ensure parent directory exists
      parent_dir = File.dirname(abs_path)
      FileUtils.mkdir_p(parent_dir) unless Dir.exist?(parent_dir)

      File.write(abs_path, content)
      "Successfully wrote to #{path}."
    })

    # 3. file_edit
    registry.register(Norn::Tool.new(
      "file_edit",
      "Perform precise, exact string replacement in a file.",
      {
        type: "object",
        properties: {
          path: { type: "string", description: "Path of the file relative to workspace root" },
          old_string: { type: "string", description: "The exact substring inside the file to be replaced" },
          new_string: { type: "string", description: "The replacement substring" }
        },
        required: ["path", "old_string", "new_string"]
      },
      required_capabilities: [:sys_write],
      dangerous: true
    ) { |args|
      path = args[:path]
      old_str = args[:old_string]
      new_str = args[:new_string]

      abs_path = Norn::Plugins::FileTools::PathHelper.resolve_and_verify(path)
      raise Errno::ENOENT, "File not found: #{path}" unless File.exist?(abs_path)

      content = File.read(abs_path)

      occurrences = content.scan(old_str).size
      if occurrences == 0
        raise "Error: old_string not found in file."
      elsif occurrences > 1
        raise "Error: old_string matches multiple locations. Provide more surrounding context lines."
      end

      updated_content = content.sub(old_str, new_str)
      File.write(abs_path, updated_content)
      "Successfully updated #{path}."
    })

    # 4. glob
    registry.register(Norn::Tool.new(
      "glob",
      "Find files matching a glob pattern relative to the workspace root.",
      {
        type: "object",
        properties: {
          pattern: { type: "string", description: "The glob pattern (e.g. '**/*.rb' or 'lib/**/*.json')" }
        },
        required: ["pattern"]
      },
      required_capabilities: [:sys_read]
    ) { |args|
      root = File.expand_path(Norn::Container.config.root)
      # Ensure the glob search runs safely inside root
      matches = Dir.glob(File.join(root, args[:pattern])).map do |abs_path|
        Pathname.new(abs_path).relative_path_from(Pathname.new(root)).to_s
      end
      matches.any? ? matches.join("\n") : "No files matched."
    })

    # 5. grep
    registry.register(Norn::Tool.new(
      "grep",
      "Search for occurrences of a regular expression across files in the workspace.",
      {
        type: "object",
        properties: {
          pattern: { type: "string", description: "The regular expression to search for" },
          include: { type: "string", description: "Optional glob pattern to restrict searched files (e.g. '*.rb')" }
        },
        required: ["pattern"]
      },
      required_capabilities: [:sys_read]
    ) { |args|
      root = File.expand_path(Norn::Container.config.root)
      pattern = Regexp.new(args[:pattern])
      glob_pattern = args[:include] || "**/*"

      results = []
      Dir.glob(File.join(root, glob_pattern)).each do |abs_path|
        next unless File.file?(abs_path)
        # Skip binary or very large files for performance
        next if File.size(abs_path) > 1_000_000

        begin
          relative_path = Pathname.new(abs_path).relative_path_from(Pathname.new(root)).to_s
          File.readlines(abs_path, encoding: "utf-8").each_with_index do |line, idx|
            if line =~ pattern
              results << "#{relative_path}:#{idx + 1}: #{line.strip}"
            end
          end
        rescue => e
          # Ignore encoding/read errors silently
        end
      end

      results.any? ? results.join("\n") : "No matches found."
    })
  end
end
