# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

RSpec.configure do |config|
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.disable_monkey_patching!
  config.order = :random

  Kernel.srand config.seed
end
