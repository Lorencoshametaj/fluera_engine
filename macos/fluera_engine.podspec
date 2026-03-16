Pod::Spec.new do |s|
  s.name             = 'fluera_engine'
  s.version          = '1.0.0'
  s.summary          = 'A professional 2D canvas engine for Flutter.'
  s.description      = <<-DESC
Fluera Engine provides low-latency drawing, GPU-accelerated stroke rendering,
and advanced brush effects for professional canvas applications on macOS.
                       DESC
  s.homepage         = 'https://github.com/flueraengine/fluera_engine'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Fluera Engine' => 'dev@flueraengine.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.swift', 'Classes/**/*.metal'
  s.dependency 'FlutterMacOS'
  s.platform         = :osx, '10.14'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }
  s.swift_version    = '5.0'
end
