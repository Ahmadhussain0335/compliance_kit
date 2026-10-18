#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint compliance_integrity.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'compliance_integrity'
  s.version          = '0.1.0-beta.1'
  s.summary          = 'App Attest integrity checks for compliance_integrity.'
  s.description      = <<-DESC
App Attest (DeviceCheck) integration for the compliance_integrity Flutter plugin.
                       DESC
  s.homepage         = 'https://github.com/Ahmadhussain0335/compliance_kit'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ahmad Hussain' => 'https://github.com/Ahmadhussain0335' }
  s.source           = { :path => '.' }
  s.source_files = 'compliance_integrity/Sources/compliance_integrity/**/*'
  s.dependency 'Flutter'
  s.frameworks = 'DeviceCheck', 'CryptoKit', 'Security'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  s.resource_bundles = {'compliance_integrity_privacy' => ['compliance_integrity/Sources/compliance_integrity/PrivacyInfo.xcprivacy']}
end
