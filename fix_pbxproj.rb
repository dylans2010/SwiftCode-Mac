#!/usr/bin/env ruby
# Validates and repairs common pbxproj syntax corruption without external gems.
# Xcode's OpenStep plist parser requires path values containing special
# characters (for example '+', spaces, or parentheses) to be quoted.

project_path = ARGV[0] || File.join(__dir__, 'SwiftCode.xcodeproj', 'project.pbxproj')
abort "Missing project file: #{project_path}" unless File.file?(project_path)

contents = File.read(project_path)
fixed = contents.gsub(/(\bpath\s*=\s*)([^";\n]+)(;)/) do
  prefix = Regexp.last_match(1)
  value = Regexp.last_match(2).strip
  suffix = Regexp.last_match(3)

  if value.match?(/\A[A-Za-z0-9_.\/$<>-]+\z/)
    "#{prefix}#{value}#{suffix}"
  else
    escaped = value.gsub('\\', '\\\\').gsub('"', '\\"')
    "#{prefix}\"#{escaped}\"#{suffix}"
  end
end

if fixed == contents
  puts "No pbxproj path quoting repairs needed."
else
  File.write(project_path, fixed)
  puts "Repaired pbxproj path quoting in #{project_path}."
end
