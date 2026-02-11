autoload :YAML, 'yaml'
require 'erubi'
require 'erubi/capture_end'
require 'tilt'

module Mrss
  module EgConfigUtils
    def transform_config(template_path, context)
      Tilt.new(template_path, engine_class: Erubi::CaptureEndEngine).render(context)
    end

    def generated_file_warning
      <<-EOT
# GENERATED FILE - DO NOT EDIT.
# Run ./.evergreen/update-evergreen-configs to regenerate this file.

EOT
    end
  end
end
