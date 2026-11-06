require 'xcodeproj'

# Adds a host-based unit test bundle (DynamicIslandTests) so the Spotify
# integration — and any future code — can be exercised with @testable import.
# Idempotent: re-running is a no-op once the target exists.

project_path = './DynamicIsland.xcodeproj'
project = Xcodeproj::Project.open(project_path)

if project.targets.any? { |t| t.name == 'DynamicIslandTests' }
  puts 'Target DynamicIslandTests already exists.'
  exit 0
end

app_target = project.targets.find { |t| t.name == 'DynamicIsland' }
raise 'App target DynamicIsland not found' unless app_target

test_target = project.new_target(:unit_test_bundle, 'DynamicIslandTests', :osx)

test_group = project.main_group.find_subpath('DynamicIslandTests', true)
test_group.set_source_tree('<group>')
test_group.set_path('DynamicIslandTests')

source_ref = test_group.new_reference('SpotifyLibraryTests.swift')
info_plist_ref = test_group.new_reference('Info.plist')
test_target.add_file_references([source_ref])

test_target.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_NAME'] = 'DynamicIslandTests'
  settings['PRODUCT_MODULE_NAME'] = 'DynamicIslandTests'
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.Ebullioscopic.Atoll.DynamicIslandTests'
  settings['INFOPLIST_FILE'] = 'DynamicIslandTests/Info.plist'
  settings['SWIFT_VERSION'] = '5.0'
  settings['MACOSX_DEPLOYMENT_TARGET'] = '15.0'
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  # Load into the app so @testable import Atoll resolves against the app module.
  settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Atoll.app/Contents/MacOS/Atoll'
  settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  settings['LD_RUNPATH_SEARCH_PATHS'] =
    ['$(inherited)', '@executable_path/../Frameworks', '@loader_path/../Frameworks']
end

# Depend on the app so it's built and testability is available.
test_target.add_dependency(app_target)

# Register the test bundle with the shared scheme's TestAction.
scheme_path = File.join(
  project_path, 'xcshareddata', 'xcschemes', 'DynamicIsland.xcscheme'
)
if File.exist?(scheme_path)
  scheme = Xcodeproj::XCScheme.new(scheme_path)
  testable = Xcodeproj::XCScheme::TestAction::TestableReference.new(test_target)
  scheme.test_action.add_testable(testable)
  scheme.save_as(project_path, 'DynamicIsland', true)
  puts 'Registered DynamicIslandTests in the DynamicIsland scheme.'
end

project.save
puts 'Successfully added DynamicIslandTests unit test target.'
