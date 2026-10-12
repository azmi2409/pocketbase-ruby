# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.pattern = "test/test_*.rb"
  t.warning = false
end

Rake::TestTask.new(:test_offline) do |t|
  t.libs << "lib" << "test"
  t.test_files = %w[test/test_utils.rb test/test_auth_store.rb test/test_transport.rb test/test_realtime_offline.rb]
  t.warning = false
end

desc "Build release gem after offline regression checks"
task build: :test_offline do
  sh "gem", "build", "pocketbase.gemspec"
end

task default: :test
