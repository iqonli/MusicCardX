Pod::Spec.new do |s|
 s.name = 'mcx_background'
 s.version = '1.0.0'
 s.summary = 'MusicCardX portable background core'
 s.description = 'Native CPU seed-driven backgrounds.'
 s.homepage = 'https://github.com/iqonli/MusicCardX'
 s.license = { :type => 'LGPL-3.0-or-later', :file => '../LICENSE' }
 s.author = { 'IQ Online Studio' => 'https://github.com/iqonli' }
 s.source = { :path => '.' }
 s.source_files = 'Classes/**/*.cpp', '../src/*.hpp'
 s.platform = :osx, '10.15'
 s.libraries = 'c++'
 s.pod_target_xcconfig = { 'DEFINES_MODULE'=>'YES', 'CLANG_CXX_LANGUAGE_STANDARD'=>'c++17', 'GCC_PREPROCESSOR_DEFINITIONS'=>'$(inherited) FLOW_NO_IMAGE_IO=1', 'OTHER_CPLUSPLUSFLAGS'=>'$(inherited) -O3 -fno-fast-math -ffp-contract=off' }
 s.user_target_xcconfig = { 'OTHER_LDFLAGS'=>'$(inherited) -Wl,-u,_mcx_render -Wl,-u,_mcx_alloc -Wl,-u,_mcx_free' }
end
