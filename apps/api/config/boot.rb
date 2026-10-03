ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
require_relative "../lib/secret_files"
SecretFiles.load!

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
