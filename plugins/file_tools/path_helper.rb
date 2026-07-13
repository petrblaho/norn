module Norn
  module Plugins
    module FileTools
      module PathHelper
        def self.resolve_and_verify(relative_path)
          root = File.expand_path(Norn.workspace_root)
          # Expand the absolute path
          absolute_path = File.expand_path(relative_path, root)
          
          # Verify the path is inside the root directory
          unless absolute_path.start_with?(root)
            raise SecurityError, "Path traversal attempt detected: #{relative_path} is outside the workspace root."
          end

          absolute_path
        end
      end
    end
  end
end
