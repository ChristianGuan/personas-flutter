#!/usr/bin/env ruby
# Idempotent native source/model/framework and share-extension wiring.
require 'xcodeproj'
require 'pathname'
root = File.expand_path('..', __dir__)
ios = File.join(root, 'flutter_app/ios')
project = Xcodeproj::Project.open(File.join(ios, 'Runner.xcodeproj'))
runner = project.targets.find { |t| t.name == 'Runner' }
group = project.main_group['Runner']
%w[PhotoPreparation.swift PhotoStore.swift PhotosBridge.swift NativeFaceEngine.mm NativeFaceEngine.h BackgroundAnalysis.swift AnalysisSession.swift].each do |name|
  ref = group.files.find { |f| f.path == name } || group.new_file(name)
  runner.source_build_phase.add_file_reference(ref, true) unless name.end_with?('.h')
end
models = project.main_group.files.find { |f| f.path == '../../app/src/main/assets/models' } || project.main_group.new_file('../../app/src/main/assets/models')
models.last_known_file_type = 'folder'
runner.resources_build_phase.add_file_reference(models, true)
framework_path = '../../.tooling/opencv-ios/opencv2.xcframework'
project.frameworks_group.files.select { |f| f.path == '../../.tooling/opencv-ios/opencv2.framework' }.each { |f| f.remove_from_project }
framework = project.frameworks_group.files.find { |f| f.path == framework_path } || project.frameworks_group.new_file(framework_path)
framework.last_known_file_type = 'wrapper.xcframework'
runner.frameworks_build_phase.add_file_reference(framework, true)
licenses = project.main_group.files.find { |f| f.path == 'Licenses' } || project.main_group.new_file('Licenses')
licenses.last_known_file_type = 'folder'
runner.resources_build_phase.add_file_reference(licenses, true)
privacy = group.files.find { |f| f.path == 'PrivacyInfo.xcprivacy' } || group.new_file('PrivacyInfo.xcprivacy')
runner.resources_build_phase.add_file_reference(privacy, true)
%w[Accelerate AVFoundation CoreMedia CoreVideo CoreGraphics ImageIO Photos PhotosUI UniformTypeIdentifiers].each do |name|
  path = "System/Library/Frameworks/#{name}.framework"
  ref = project.frameworks_group.files.find { |f| f.path == path } || project.frameworks_group.new_file(path)
  ref.source_tree = 'SDKROOT'; runner.frameworks_build_phase.add_file_reference(ref, true)
end
runner.build_configurations.each do |config|
  config.build_settings.merge!({
    'IPHONEOS_DEPLOYMENT_TARGET' => '16.0', 'PRODUCT_BUNDLE_IDENTIFIER' => 'co.local.personas',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',
    'SWIFT_VERSION' => '5.0', 'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17', 'CLANG_CXX_LIBRARY' => 'libc++',
    'FRAMEWORK_SEARCH_PATHS' => ['$(inherited)', '$(BUILT_PRODUCTS_DIR)'],
    'OTHER_LDFLAGS' => ['$(inherited)', '-lc++'], 'ENABLE_BITCODE' => 'NO',
    'PERSONAS_APP_GROUP' => 'group.co.local.personas', 'CODE_SIGN_ENTITLEMENTS' => 'Runner/Runner.entitlements'
  })
end
project.build_configurations.each { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0' }
extension = project.targets.find { |t| t.name == 'PersonasShare' } || project.new_target(:app_extension, 'PersonasShare', :ios, '16.0')
extension_group = project.main_group['ShareExtension'] || project.main_group.new_group('ShareExtension', 'ShareExtension')
ref = extension_group.files.find { |f| f.path == 'ShareViewController.swift' } || extension_group.new_file('ShareViewController.swift')
extension.source_build_phase.add_file_reference(ref, true)
flutter_config = project.files.find { |f| f.path == 'Flutter/Generated.xcconfig' }
raise 'Falta Flutter/Generated.xcconfig en el proyecto' unless flutter_config
extension.build_configurations.each do |config|
  config.base_configuration_reference = flutter_config
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'co.local.personas.share', 'SWIFT_VERSION' => '5.0',
    'IPHONEOS_DEPLOYMENT_TARGET' => '16.0', 'INFOPLIST_FILE' => 'ShareExtension/Info.plist',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',
    'GENERATE_INFOPLIST_FILE' => 'NO', 'SKIP_INSTALL' => 'YES', 'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'PERSONAS_APP_GROUP' => 'group.co.local.personas', 'CODE_SIGN_ENTITLEMENTS' => 'ShareExtension/ShareExtension.entitlements',
    'CURRENT_PROJECT_VERSION' => '$(FLUTTER_BUILD_NUMBER)', 'MARKETING_VERSION' => '$(FLUTTER_BUILD_NAME)',
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'TARGETED_DEVICE_FAMILY' => '1,2', 'CODE_SIGN_STYLE' => 'Automatic'
  })
end
runner.add_dependency(extension) unless runner.dependencies.any? { |d| d.target == extension }
embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' } || runner.new_copy_files_build_phase('Embed App Extensions')
embed.dst_subfolder_spec = '13'
# Embed before Flutter's Thin Binary script to avoid an Info.plist dependency cycle.
runner.build_phases.delete(embed)
thin_index = runner.build_phases.index { |phase| phase.respond_to?(:name) && phase.name == 'Thin Binary' }
runner.build_phases.insert(thin_index || runner.build_phases.length, embed)
file = embed.add_file_reference(extension.product_reference, true)
file.settings = {'ATTRIBUTES' => ['RemoveHeadersOnCopy']}
project.save
plist = File.join(ios, 'Runner/Info.plist')
data = Xcodeproj::Plist.read_from_path(plist)
data['CFBundleDisplayName'] = 'Personas'
data['NSPhotoLibraryUsageDescription'] = 'Permite elegir álbumes para buscar localmente a una persona en tus fotografías.'
data['PersonasAppGroup'] = '$(PERSONAS_APP_GROUP)'
data['UIBackgroundModes'] = (Array(data['UIBackgroundModes']) + ['processing', 'fetch']).uniq
data['BGTaskSchedulerPermittedIdentifiers'] = (Array(data['BGTaskSchedulerPermittedIdentifiers']) + ['$(PRODUCT_BUNDLE_IDENTIFIER).analysis.*', 'co.local.personas.analytics.sync']).uniq
Xcodeproj::Plist.write_to_path(data, plist)
puts 'Proyecto iOS configurado con motor, modelos y extensión de compartir.'
