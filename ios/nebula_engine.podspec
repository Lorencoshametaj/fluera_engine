Pod::Spec.new do |s|
  s.name             = 'nebula_engine'
  s.version          = '1.0.0'
  s.summary          = 'A professional 2D canvas engine for Flutter.'
  s.description      = <<-DESC
Nebula Engine provides low-latency drawing, predicted touches,
120Hz ProMotion sync, and advanced haptic feedback for professional
canvas applications.
                       DESC
  s.homepage         = 'https://github.com/nebulaengine/nebula_engine'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Nebula Engine' => 'dev@nebulaengine.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  # PyTorch Mobile Lite for on-device pix2tex LaTeX recognition
  s.dependency 'LibTorchLite', '~> 2.1.0'
  s.platform         = :ios, '13.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
end
