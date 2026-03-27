Pod::Spec.new do |s|
  s.name             = 'fluera_engine'
  s.version          = '1.0.0'
  s.summary          = 'A professional 2D canvas engine for Flutter.'
  s.description      = <<-DESC
Fluera Engine provides low-latency drawing, predicted touches,
120Hz ProMotion sync, and advanced haptic feedback for professional
canvas applications.
                       DESC
  s.homepage         = 'https://github.com/flueraengine/fluera_engine'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Fluera Engine' => 'dev@flueraengine.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.swift', 'Classes/**/*.metal', 'Classes/rnnoise_src/{denoise,nnet,nnet_default,rnn,rnnoise_data,rnnoise_tables,pitch,kiss_fft,celt_lpc,parse_lpcnet_weights}.c', 'Classes/rnnoise_src/*.h', 'Classes/rnnoise_include/**/*.h'
  s.public_header_files = 'Classes/rnnoise_include/**/*.h'
  s.dependency 'Flutter'
  # PyTorch Mobile Lite for on-device pix2tex LaTeX recognition
  s.dependency 'LibTorchLite', '~> 2.1.0'
  s.platform         = :ios, '13.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) HAVE_CONFIG_H=1',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/Classes/rnnoise_src" "${PODS_TARGET_SRCROOT}/Classes/rnnoise_include"'
  }
  s.swift_version    = '5.0'
end
