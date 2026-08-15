require 'xcodeproj'

# Consolidates the two Cocoa.framework file references into one SDKROOT-relative
# reference shared by every target, removing an SDK-version-pinned
# (DEVELOPER_DIR/MacOSX*.sdk) reference that breaks portability across Xcode/SDK
# versions. Idempotent: re-running once consolidated is a no-op.

project_path = './DynamicIsland.xcodeproj'
project = Xcodeproj::Project.open(project_path)

cocoa_refs = project.files.select { |f| f.display_name == 'Cocoa.framework' }
sdkroot_ref = cocoa_refs.find { |f| f.source_tree == 'SDKROOT' }
pinned_refs = cocoa_refs.reject { |f| f.source_tree == 'SDKROOT' }

if sdkroot_ref.nil?
  raise 'No SDKROOT-relative Cocoa.framework reference found; aborting.'
end

if pinned_refs.empty?
  puts 'Cocoa.framework already consolidated to a single SDKROOT reference.'
  exit 0
end

pinned_uuids = pinned_refs.map(&:uuid)

# Repoint every build file that used a pinned reference at the SDKROOT one.
project.targets.each do |target|
  target.frameworks_build_phase.files.each do |build_file|
    ref = build_file.file_ref
    next unless ref && pinned_uuids.include?(ref.uuid)
    build_file.file_ref = sdkroot_ref
    puts "Repointed Cocoa.framework in #{target.name} to the SDKROOT reference."
  end
end

# Remove the now-orphaned pinned references (also unlinks them from their group).
pinned_refs.each(&:remove_from_project)

project.save
puts 'Successfully consolidated Cocoa.framework to a single SDKROOT reference.'
