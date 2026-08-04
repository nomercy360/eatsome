platform :ios, '17.0'

# MediaPipe Tasks ships for iOS through CocoaPods only, so the project is a
# workspace. Everything else is SwiftPM.
target 'Shaman' do
  use_frameworks!
  pod 'MediaPipeTasksVision'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      # Pod sources are not ours to make Swift 6 concurrency-clean.
      config.build_settings['SWIFT_STRICT_CONCURRENCY'] = 'minimal'
    end
  end
end
