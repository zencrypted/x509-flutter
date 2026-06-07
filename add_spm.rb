require 'xcodeproj'
project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Add SwiftASN1 package
package = project.root_object.add_swift_package_repository('https://github.com/apple/swift-asn1.git', '1.0.0')

# Add package to the Runner target
target = project.targets.first
framework_ref = project.frameworks_group.new_product_ref_for_target('SwiftASN1', :swift_package)
build_phase = target.frameworks_build_phase
build_phase.add_file_reference(framework_ref)

project.save
