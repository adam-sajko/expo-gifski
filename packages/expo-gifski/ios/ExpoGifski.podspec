Pod::Spec.new do |s|
  s.name           = 'ExpoGifski'
  s.version        = '0.1.0'
  s.summary        = 'Expo module for gifski'
  s.description    = 'Expo module for gifski - high-quality GIF encoder written in Rust'
  s.author         = ''
  s.homepage       = 'https://github.com/adam-sajko/expo-gifski'
  s.platforms      = { :ios => '13.0' }
  s.source         = { :git => '' }
  s.static_framework = true
  s.swift_version  = '5.0'

  s.dependency 'ExpoModulesCore'

  # Swift source: the Expo module + UniFFI generated bindings
  s.source_files = "*.{h,m,mm,swift}", "generated/*.swift"

  # Compute absolute paths at pod install time
  libs_dir = File.join(__dir__, 'libs')
  generated_dir = File.join(__dir__, 'generated')

  device_lib = File.join(libs_dir, 'libexpo_gifski.a')
  sim_lib = File.join(libs_dir, 'libexpo_gifski_sim.a')

  if File.exist?(device_lib) && File.exist?(sim_lib)
    s.preserve_paths = 'libs/*.a', 'generated/*'

    # UniFFI generates a C header and modulemap for the FFI layer.
    modulemap_path = File.join(generated_dir, 'expo_gifskiFFI.modulemap')
    if File.exist?(modulemap_path)
      s.pod_target_xcconfig = {
        'SWIFT_INCLUDE_PATHS' => "\"#{generated_dir}\"",
        'HEADER_SEARCH_PATHS' => "\"#{generated_dir}\"",
        'LIBRARY_SEARCH_PATHS' => "\"#{libs_dir}\"",
        'OTHER_SWIFT_FLAGS' => "$(inherited) -Xcc -fmodule-map-file=\"#{modulemap_path}\""
      }
    else
      s.pod_target_xcconfig = {
        'LIBRARY_SEARCH_PATHS' => "\"#{libs_dir}\""
      }
    end

    # Link the correct Rust static library based on SDK (device vs simulator).
    ffi_flags = File.exist?(modulemap_path) ? {
      'OTHER_SWIFT_FLAGS' => "$(inherited) -Xcc -fmodule-map-file=\"#{modulemap_path}\"",
      'HEADER_SEARCH_PATHS' => "\"#{generated_dir}\""
    } : {}
    s.xcconfig = ffi_flags.merge({
      'OTHER_LDFLAGS[sdk=iphoneos*]' => "$(inherited) -force_load \"#{device_lib}\"",
      'OTHER_LDFLAGS[sdk=iphonesimulator*]' => "$(inherited) -force_load \"#{sim_lib}\""
    })
  else
    puts "⚠️  Warning: Rust libraries not found. Run './ios/build.sh' in the module directory first."
  end
end
