require 'xcodeproj'
project = Xcodeproj::Project.open('/Users/dylan/Downloads/SwiftCode-Mac-1/SwiftCode.xcodeproj')
target = project.targets.find { |t| t.name == 'SwiftCode' }
file_ref = project.files.find { |f| f.path == 'NativeTextView.swift' }
if file_ref
  unless target.source_build_phase.files_references.include?(file_ref)
    target.source_build_phase.add_file_reference(file_ref)
    project.save
    puts "Added NativeTextView.swift to build phase."
  else
    puts "NativeTextView.swift is already in the build phase."
  end
else
  puts "NativeTextView.swift file reference not found."
end
