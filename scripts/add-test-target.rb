#!/usr/bin/env ruby
# Adds the MarqueTests unit-test target (hosted in Marque.app) and a shared
# "Marque" scheme that builds the app and runs those tests, using the
# xcodeproj gem (CocoaPods' project writer) rather than hand-editing
# project.pbxproj. One-off; kept for the record and for re-running against a
# scratch copy.
#
#   gem install --user-install xcodeproj
#   ruby scripts/add-test-target.rb --root /path/to/copy-of-repo
#
# Idempotent: does nothing if the target already exists.
require "optparse"
require "xcodeproj"

root = Dir.pwd
OptionParser.new { |o| o.on("--root PATH") { |v| root = File.expand_path(v) } }.parse!
project_path = File.join(root, "Marque.xcodeproj")
project = Xcodeproj::Project.open(project_path)

app = project.targets.find { |t| t.name == "Marque" } or abort "no Marque target"
if project.targets.any? { |t| t.name == "MarqueTests" }
  puts "MarqueTests already exists"
  exit 0
end

app_settings = app.build_configurations.first.build_settings
tests = project.new_target(:unit_test_bundle, "MarqueTests", :ios, app_settings["IPHONEOS_DEPLOYMENT_TARGET"])
tests.add_dependency(app)
tests.build_configurations.each do |config|
  s = config.build_settings
  s["PRODUCT_BUNDLE_IDENTIFIER"] = "com.tommychiu.marque.tests"
  s["PRODUCT_NAME"] = "$(TARGET_NAME)"
  s["GENERATE_INFOPLIST_FILE"] = "YES"
  s["SWIFT_VERSION"] = app_settings["SWIFT_VERSION"] || "5.0"
  s["TARGETED_DEVICE_FAMILY"] = app_settings["TARGETED_DEVICE_FAMILY"] || "1"
  s["DEVELOPMENT_TEAM"] = app_settings["DEVELOPMENT_TEAM"]
  s["CODE_SIGN_STYLE"] = "Automatic"
  s["TEST_HOST"] = "$(BUILT_PRODUCTS_DIR)/Marque.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Marque"
  s["BUNDLE_LOADER"] = "$(TEST_HOST)"
end

group = project.main_group.find_subpath("MarqueTests", true)
group.set_source_tree("<group>")
group.set_path("MarqueTests")
Dir.glob(File.join(root, "MarqueTests", "*.swift")).sort.each do |file|
  tests.add_file_references([group.new_reference(File.basename(file))])
end

project.root_object.attributes["TargetAttributes"] ||= {}
project.root_object.attributes["TargetAttributes"][tests.uuid] = { "TestTargetID" => app.uuid }
project.save

# Shared scheme: build Marque (and the widget it embeds), test MarqueTests,
# run Debug. Written by xcodeproj's scheme API, not by hand.
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app, tests, launch_target: true)
scheme.test_action.build_configuration = "Debug"
scheme.launch_action.build_configuration = "Debug"
scheme.save_as(project_path, "Marque", true)
puts "added MarqueTests (#{tests.source_build_phase.files.count} files) and shared scheme Marque"
